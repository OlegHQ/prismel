open Yojson.Safe.Util
open Binding_render_encoder_safe_spec

let option_string json name = match member name json with `Null -> None | value -> Some (to_string value)
let symbol json : Binding_render_encoder_evidence.symbol =
  { id = json |> member "id" |> to_string; kind = json |> member "kind" |> to_string
  ; owner = option_string json "owner"; signature = json |> member "signature" |> to_string
  ; macos_introduced = option_string json "macos_introduced"
  ; attributes = json |> member "attributes" |> to_list |> List.map to_string
  ; classification = json |> member "classification" |> to_string }

let () =
  if Array.length Sys.argv <> 2 then failwith "inventory path required";
  let symbols = Yojson.Safe.from_file Sys.argv.(1) |> member "symbols" |> to_list |> List.map symbol in
  let entries = select symbols in
  if List.length entries <> 133 then failwith "safe wrapper closure drift";
  List.iter (fun (group, expected) ->
    let actual = List.fold_left (fun total entry -> if entry.group = group then total + 1 else total) 0 entries in
    if actual <> expected then failwith (Printf.sprintf "%s count %d, expected %d" (group_name group) actual expected)) expected_group_counts;
  let deprecated = List.filter (fun entry -> entry.disposition = Deprecated_alias) entries in
  if List.length deprecated <> 5 then failwith "deprecated partition drift";
  List.iter (fun entry ->
    if entry.obligations = [] || not (List.mem Encoder_open entry.obligations) then
      failwith ("missing state validation: " ^ entry.id)) entries;
  Printf.printf "Metal render encoder safe spec: 133 declarations in 9 exhaustive groups\n"
