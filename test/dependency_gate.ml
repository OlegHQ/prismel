(* One dependency gate over the real library graph, read from every
   lib/**/dune. Rules are "may never reach" constraints on the transitive
   closure plus a token scan for Metal outside its backends. Known violations
   are listed with the plan item that removes them; delete an exception when
   its item lands, and the gate then keeps it fixed. Run from the repo root. *)

(* ---- a tiny s-expression reader: enough for dune files ---- *)
type sexp = Atom of string | List of sexp list

let parse text =
  let n = String.length text and i = ref 0 in
  let rec skip () =
    if !i < n then match text.[!i] with
      | ' ' | '\n' | '\t' | '\r' -> incr i; skip ()
      | ';' -> while !i < n && text.[!i] <> '\n' do incr i done; skip ()
      | _ -> () in
  let rec item () =
    skip ();
    match text.[!i] with
    | '(' -> incr i; let rec items acc = skip ();
               if text.[!i] = ')' then (incr i; List (List.rev acc))
               else items (item () :: acc) in items []
    | '"' -> incr i; let start = !i in
        while text.[!i] <> '"' do (if text.[!i] = '\\' then incr i); incr i done;
        incr i; Atom (String.sub text start (!i - start - 1))
    | _ -> let start = !i in
        while !i < n && not (String.contains " \n\t\r()\";" text.[!i]) do incr i done;
        Atom (String.sub text start (!i - start)) in
  let rec all acc = skip (); if !i >= n then List.rev acc else all (item () :: acc) in
  all []

let read path = In_channel.with_open_bin path In_channel.input_all

let rec files dir = Sys.readdir dir |> Array.to_list |> List.concat_map (fun name ->
  let path = Filename.concat dir name in
  if Sys.is_directory path then (if name = "_build" then [] else files path) else [path])

(* library name -> direct in-repo dependencies (public names resolved) *)
let graph roots =
  let stanzas = List.concat_map files roots
    |> List.filter (fun p -> Filename.basename p = "dune")
    |> List.concat_map (fun p -> parse (read p) |> List.filter_map (function
      | List (Atom "library" :: fields) ->
          let field key = List.find_map (function
            | List (Atom k :: values) when k = key -> Some values | _ -> None) fields in
          let atoms = function Some v -> List.filter_map (function Atom a -> Some a | _ -> None) v | None -> [] in
          (match atoms (field "name") with
           | [name] -> Some (name, atoms (field "public_name"), atoms (field "libraries"))
           | _ -> None)
      | _ -> None)) in
  let resolve = Hashtbl.create 64 in
  List.iter (fun (name, public, _) ->
    Hashtbl.replace resolve name name; List.iter (fun p -> Hashtbl.replace resolve p name) public) stanzas;
  List.map (fun (name, _, deps) -> name, List.filter_map (Hashtbl.find_opt resolve) deps) stanzas

let reach graph =
  let memo = Hashtbl.create 64 in
  let rec go name = match Hashtbl.find_opt memo name with
    | Some set -> set
    | None -> Hashtbl.replace memo name [];
        let direct = Option.value ~default:[] (List.assoc_opt name graph) in
        let set = List.sort_uniq compare (direct @ List.concat_map go direct) in
        Hashtbl.replace memo name set; set in
  go

let gpu = ["sdl3"; "sdl3_image"; "sdl3_ttf"; "sdl3_mixer"; "metal"; "ogpu"; "ogpu_metal";
           "runtime_next"; "runtime_next_orchestrator"; "scene_execution"]
let upper = ["prismel"; "pxui"; "pxui_graph"; "sop_ui"; "procedural"; "pdk"; "geom";
             "sop_catalog"; "sketch_support"; "sketch_ui"]
let foundational = ["sdl3"; "sdl3_image"; "sdl3_ttf"; "sdl3_mixer"; "metal"; "ogpu";
                    "native_layer_token"; "scene_command"]

(* (library, libraries it may never reach) *)
let rules =
  List.map (fun lib -> lib, "runtime_next" :: "runtime_next_orchestrator"
                            :: "prismel_next_execution" :: upper) foundational
  @ [ "ogpu", ["sdl3"; "metal"; "ogpu_metal"; "native_layer_token"];
      "ogpu_metal", ["sdl3"; "runtime_next"; "prismel"; "scene_execution"];
      "runtime_next", upper; "runtime_next_input", upper;
      "prismel_next_execution", ["runtime_next_input"];
      "prismel", ["pxui"; "pxui_graph"; "sop_ui"; "procedural"; "pdk"; "geom";
                  "sop_catalog"; "sketch_support"; "sketch_ui"];
      "pdk", "geom" :: "procedural" :: "pxui" :: "sop_ui" :: "sop_catalog" :: gpu;
      "geom", ["procedural"; "pxui"; "sop_ui"; "sop_catalog"];
      "procedural", "pxui" :: "pxui_graph" :: "sop_ui" :: "sop_catalog"
                    :: "sketch_support" :: "sketch_ui" :: gpu;
      "pxui", ["procedural"; "pdk"; "geom"; "pxui_graph"; "sop_ui"; "sketch_support"; "sketch_ui"];
      "sop_ui", ["pxui_graph"; "sketch_support"; "sketch_ui"; "sop_catalog"];
      "pxui_graph", ["sop_ui"; "sketch_support"; "sketch_ui"; "sop_catalog"];
      "sop_catalog", ["geom"; "pxui"; "pxui_graph"; "sop_ui"; "sketch_support"; "sketch_ui"];
      "sketch_support", ["geom"; "pxui"; "pxui_graph"; "sop_ui"; "sketch_ui"] ]

(* Known violations: (library, reached, plan item that removes it). *)
let reach_exceptions =
  List.concat_map (fun (lib, item) -> List.map (fun g -> lib, g, item) gpu)
    [ "pdk", "K1"; "procedural", "K1" ]

(* Direct Metal use outside lib/metal and lib/ogpu_metal: (path prefix, item). *)
let metal_exceptions = [
  "lib/runtime/", "G4"; "lib/prismel_pathtracer/", "G3";
  (* tests that read Metal's release-queue stats for leak checks *)
  "lib/prismel/test_canvas_native.ml", "G4";
  "lib/prismel_next_execution/test_", "G4"; "lib/scene_execution/test_", "G4";
  "sketches/code_quadtree/test_packed_ink.ml", "S5" ]

(* identifiers outside comments and string literals *)
let code_tokens text =
  let n = String.length text and out = Buffer.create (String.length text) in
  let rec go i depth =
    if i < n then
      if i + 1 < n && text.[i] = '(' && text.[i+1] = '*' then (Buffer.add_char out ' '; go (i + 2) (depth + 1))
      else if depth > 0 && i + 1 < n && text.[i] = '*' && text.[i+1] = ')' then go (i + 2) (depth - 1)
      else if depth > 0 then go (i + 1) depth
      else if text.[i] = '"' then
        let rec skip j = if j >= n then j else if text.[j] = '\\' then skip (j + 2)
          else if text.[j] = '"' then j + 1 else skip (j + 1) in
        (Buffer.add_char out ' '; go (skip (i + 1)) 0)
      else (Buffer.add_char out text.[i]; go (i + 1) 0) in
  go 0 0; Buffer.contents out

let uses_metal text =
  let code = code_tokens text in
  let rec find i = match String.index_from_opt code i 'M', String.index_from_opt code i 'O' with
    | None, None -> false
    | a, b ->
        let j = min (Option.value a ~default:max_int) (Option.value b ~default:max_int) in
        let starts word = String.length code >= j + String.length word
          && String.sub code j (String.length word) = word
          && (j = 0 || not (match code.[j-1] with 'a'..'z'|'A'..'Z'|'0'..'9'|'_'|'.' -> true | _ -> false)) in
        (starts "Metal." || starts "Ogpu_metal.") || find (j + 1) in
  find 0 || List.exists (fun w -> List.mem w ["Metal"; "Ogpu_metal"])
    (let words = String.split_on_char ' ' (String.map (function '\n'|'\t'|';' -> ' ' | c -> c) code) in
     let rec opens = function "open" :: w :: rest -> w :: opens rest | _ :: rest -> opens rest | [] -> [] in
     opens words)

let violations graph ~scan =
  let reach = reach graph in
  let edge_errors = List.concat_map (fun (lib, forbidden) ->
    List.filter_map (fun target ->
      if List.mem target (reach lib)
         && not (List.exists (fun (l, t, _) -> l = lib && t = target) reach_exceptions)
      then Some (Printf.sprintf "%s reaches forbidden library %s" lib target) else None)
      forbidden) rules in
  let token_errors = List.filter_map (fun (path, text) ->
    let allowed = String.starts_with ~prefix:"lib/metal/" path
      || String.starts_with ~prefix:"lib/ogpu_metal/" path
      || List.exists (fun (prefix, _) -> String.starts_with ~prefix path) metal_exceptions in
    if not allowed && uses_metal text then Some (path ^ " uses Metal outside lib/metal and lib/ogpu_metal")
    else None) scan in
  edge_errors @ token_errors

let run () =
  let graph = graph ["lib"; "ppx"] in
  if List.length graph < 20 then failwith "dependency gate found too few libraries (wrong cwd?)";
  List.iter (fun name -> if List.mem_assoc name graph then
    failwith ("retired facade returned: " ^ name)) ["runtime"; "prismel_next_api"];
  (* injected violations must fire *)
  let inject lib dep = List.map (fun (l, d) -> l, if l = lib then dep :: d else d) graph in
  List.iter (fun (lib, dep) ->
    if violations (inject lib dep) ~scan:[] = [] then
      failwith (Printf.sprintf "gate accepted injected edge %s -> %s" lib dep))
    ["ogpu", "metal"; "prismel", "pxui"; "pxui", "procedural"; "sdl3", "prismel";
     "pdk", "geom"; "prismel_next_execution", "runtime_next_input"];
  if violations graph ~scan:["lib/prismel/injected.ml", "let x = Metal.Device.system_default"] = []
     || violations graph ~scan:["lib/prismel/injected.ml", "open Ogpu_metal"] = [] then
    failwith "gate accepted injected Metal reference";
  if violations graph ~scan:["lib/prismel/ok.ml", "(* Metal.foo *) let s = \"Metal.framework\""] <> [] then
    failwith "gate flagged Metal inside a comment or string";
  let scan = List.concat_map files ["lib"; "examples"; "sketches"]
    |> List.filter (fun p -> Filename.check_suffix p ".ml" || Filename.check_suffix p ".mli")
    |> List.map (fun p -> p, read p) in
  match violations graph ~scan with
  | [] -> Printf.printf "dependency gate: %d libraries, %d rules, %d listed exceptions\n"
            (List.length graph) (List.length rules)
            (List.length reach_exceptions + List.length metal_exceptions)
  | errors -> List.iter prerr_endline errors; exit 1
