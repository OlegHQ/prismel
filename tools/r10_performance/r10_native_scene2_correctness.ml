open Yojson.Safe.Util

let fail format = Printf.ksprintf failwith format
let require condition format = Printf.ksprintf (fun message -> if not condition then failwith message) format
let get = function
  | Ok value -> value
  | Error error ->
      fail "%s" (Format.asprintf "%a" Prismel_next_execution.pp_error error)
let checkpoints = [ 1; 2; 60; 600 ]
let hex_digest value = String.length value = 32 && String.for_all (function '0'..'9'|'a'..'f'->true|_->false) value
let git_commit value = String.length value = 40 && String.for_all (function '0'..'9'|'a'..'f'->true|_->false) value
let command_output command =
  let channel=Unix.open_process_in command in
  Fun.protect ~finally:(fun()->ignore(Unix.close_process_in channel)) (fun()->input_line channel)
let current_commit()=command_output "git rev-parse HEAD"
let require_clean_tree()=
  require (Sys.command "git diff --quiet --ignore-submodules -- && git diff --cached --quiet --ignore-submodules --"=0)
    "native authority requires a clean tracked worktree"
let pixel_key bytes offset =
  Char.code (Bytes.get bytes offset)
  lor (Char.code (Bytes.get bytes (offset + 1)) lsl 8)
  lor (Char.code (Bytes.get bytes (offset + 2)) lsl 16)
  lor (Char.code (Bytes.get bytes (offset + 3)) lsl 24)

let coverage bytes =
  require (Bytes.length bytes mod 4 = 0) "framebuffer is not RGBA8";
  require (Bytes.length bytes >= 4) "framebuffer is empty";
  (* A clear-only frame is uniform regardless of the backend's byte channel
     order or color conversion.  Use the captured corner pixel as the clear
     authority rather than baking a renderer-specific RGBA encoding. *)
  let count = ref 0 in
  let colors = Hashtbl.create 32 in
  let background = pixel_key bytes 0 in
  for pixel = 0 to (Bytes.length bytes / 4) - 1 do
    let offset = pixel * 4 in
    let color = pixel_key bytes offset in
    if color <> background then begin
      incr count;
      Hashtbl.replace colors color ()
    end
  done;
  !count, Hashtbl.length colors

let capture candidate frame width height =
  R10_scene2_candidate.render candidate ~width ~height;
  let bytes = R10_scene2_candidate.capture candidate in
  let changed, distinct_colors = coverage bytes in
  require (changed > 0) "frame %d is clear-only" frame;
  require (distinct_colors >= 4)
    "frame %d has only %d non-background RGBA colors (fallback-color rendering)"
    frame distinct_colors;
  `Assoc [ "frame", `Int frame; "digest", `String (Digest.to_hex (Digest.bytes bytes));
    "non_clear_pixels", `Int changed;
    "distinct_non_background_colors", `Int distinct_colors ]

let run_scenario scenario =
  let public = match scenario with
    | "basic" -> R10_scene2_legacy_equivalent.Basic | "pxui" -> Pxui
    | _ -> fail "invalid scenario %S" scenario
  in
  let candidate = Result.get_ok (R10_scene2_candidate.create ~target:`Native ~width:640 ~height:480 public) in
  Fun.protect ~finally:(fun () -> R10_scene2_candidate.destroy candidate) (fun () ->
    ignore (get (Prismel_next_execution.hide candidate.execution));
    let hidden_before=not (get (Prismel_next_execution.visible candidate.execution)) in
    require hidden_before "%s: hidden transition not observed" scenario;
    ignore (get (Prismel_next_execution.show candidate.execution));
    let shown=get (Prismel_next_execution.visible candidate.execution) in
    require shown "%s: visible transition not observed" scenario;
    ignore (get (Prismel_next_execution.hide candidate.execution));
    let hidden_after=not (get (Prismel_next_execution.visible candidate.execution)) in
    require hidden_after "%s: final hidden transition not observed" scenario;
    let captured = ref [] in
    for frame = 1 to 600 do
      if List.mem frame checkpoints then captured := capture candidate frame 640 480 :: !captured
      else R10_scene2_candidate.render candidate ~width:640 ~height:480
    done;
    ignore (get (Prismel_next_execution.resize candidate.execution ~logical_width:800 ~logical_height:600 ~drawable_width:800 ~drawable_height:600));
    let resized = capture candidate 601 800 600 in
    `Assoc [ "scenario", `String scenario;
      "visibility_observed", `List [`Bool hidden_before;`Bool shown;`Bool hidden_after];
      "checkpoints", `List (List.rev !captured); "resized", resized ])

let entries value = value |> member "checkpoints" |> to_list
let digest item = item |> member "digest" |> to_string

let validate_scenario value =
  require (List.mem (value |> member "scenario" |> to_string) [ "basic"; "pxui" ]) "wrong scenario";
  let items = entries value in
  require (value |> member "visibility_observed" |> to_list |> List.map to_bool = [true;true;true]) "visibility proof drift";
  require (List.map (fun x -> x |> member "frame" |> to_int) items = checkpoints) "checkpoint labels drift";
  List.iter (fun item -> require (item |> member "non_clear_pixels" |> to_int > 0) "clear-only checkpoint";
    require (item |> member "distinct_non_background_colors" |> to_int >= 4)
      "fallback-color checkpoint";
    require (hex_digest(digest item)) "invalid digest") items;
  let resized = value |> member "resized" in
  require (resized |> member "frame" |> to_int = 601) "resize label drift";
  require (resized |> member "non_clear_pixels" |> to_int > 0) "clear-only resize";
  require (resized |> member "distinct_non_background_colors" |> to_int >= 4)
    "fallback-color resize";
  require (hex_digest(digest resized)) "invalid resize digest"

let scenarios value = value |> member "scenarios" |> to_list
let validate_report value =
  require (value |> member "schema" |> to_int = 2) "wrong schema";
  require (value |> member "target" |> to_string = "native") "wrong target";
  require (value |> member "comparison" |> to_string = "exact-framebuffer-digest") "wrong comparison";
  require (value |> member "width" |> to_int = 640 && value |> member "height" |> to_int = 480) "wrong extent";
  require (value |> member "pixel_tolerance" |> to_int = 3) "frozen tolerance drift";
  let provenance=value |> member "provenance" in
  require (git_commit(provenance |> member "renderer_commit" |> to_string)) "invalid renderer commit";
  require (provenance |> member "tracked_tree_clean" |> to_bool) "dirty renderer provenance";
  require (provenance |> member "host" |> to_string = "Apple M1") "authority is not an Apple M1 run";
  require (hex_digest(provenance |> member "executable_digest" |> to_string)) "invalid executable digest";
  let values = scenarios value in
  require (List.map (fun x -> x |> member "scenario" |> to_string) values = [ "basic"; "pxui" ]) "scenario matrix drift";
  List.iter validate_scenario values;
  let basic, pxui = match values with [ a; b ] -> a, b | _ -> assert false in
  require (List.exists2 (fun a b -> digest a <> digest b) (entries basic) (entries pxui)) "Basic and PXUI checkpoint digests are indistinguishable";
  require (digest (basic |> member "resized") <> digest (pxui |> member "resized")) "Basic and PXUI resize digests are indistinguishable"

let comparable value = (value |> member "provenance" |> member "renderer_commit" |> to_string,
  List.map (fun scenario ->
  scenario |> member "scenario" |> to_string,
  List.map (fun item -> digest item, item |> member "non_clear_pixels" |> to_int,
    item |> member "distinct_non_background_colors" |> to_int) (entries scenario),
  (digest (scenario |> member "resized"),
    scenario |> member "resized" |> member "non_clear_pixels" |> to_int,
    scenario |> member "resized" |> member "distinct_non_background_colors" |> to_int))
  (scenarios value))

let validate report authority =
  let actual = Yojson.Safe.from_file report and expected = Yojson.Safe.from_file authority in
  validate_report actual; validate_report expected;
  require (comparable actual = comparable expected) "native authority drift";
  print_endline "native Scene2 correctness authority passed"

let run_matrix renderer_commit =
  require_clean_tree();
  require (current_commit()=renderer_commit) "renderer commit does not match clean HEAD";
  let executable_digest=Digest.to_hex(Digest.file(Sys.executable_name))in
  let json = `Assoc [ "schema", `Int 2; "target", `String "native";
    "comparison", `String "exact-framebuffer-digest";
    "provenance", `Assoc ["renderer_commit",`String renderer_commit;
      "tracked_tree_clean",`Bool true;"host",`String "Apple M1";
      "executable_digest",`String executable_digest];
    "width", `Int 640;
    "height", `Int 480; "pixel_tolerance", `Int 3;
    "scenarios", `List [ run_scenario "basic"; run_scenario "pxui" ] ] in
  validate_report json; json

let () =
  let report = ref "" and actual = ref "" and authority = ref "" and renderer_commit=ref "" in
  Arg.parse [ "--report", Arg.Set_string report, "write real Native matrix JSON";
    "--validate", Arg.Set_string actual, "validate matrix report JSON";
    "--authority", Arg.Set_string authority, "pinned authority JSON";
    "--renderer-commit",Arg.Set_string renderer_commit,"clean renderer HEAD to record" ]
    (fun value -> fail "unexpected argument %S" value) "r10_native_scene2_correctness";
  if !actual <> "" || !authority <> "" then begin
    require (!actual <> "" && !authority <> "") "validation requires report and authority";
    validate !actual !authority
  end else begin
    require (!report <> "" && git_commit !renderer_commit) "run requires --report and a 40-hex --renderer-commit";
    let output = open_out_bin !report in
    Fun.protect ~finally:(fun () -> close_out output) (fun () ->
      Yojson.Safe.pretty_to_channel output (run_matrix !renderer_commit); output_char output '\n')
  end
