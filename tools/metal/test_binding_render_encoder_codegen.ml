open Yojson.Safe.Util

let option_string json name =
  match member name json with `Null -> None | value -> Some (to_string value)

let symbol json : Binding_render_encoder_evidence.symbol =
  { id = json |> member "id" |> to_string
  ; kind = json |> member "kind" |> to_string
  ; owner = option_string json "owner"
  ; signature = json |> member "signature" |> to_string
  ; macos_introduced = option_string json "macos_introduced"
  ; attributes = json |> member "attributes" |> to_list |> List.map to_string
  ; classification = json |> member "classification" |> to_string
  }

let count_substring text pattern =
  let rec loop offset count =
    if offset + String.length pattern > String.length text then count
    else if String.sub text offset (String.length pattern) = pattern then
      loop (offset + String.length pattern) (count + 1)
    else loop (offset + 1) count
  in
  loop 0 0

let () =
  if Array.length Sys.argv <> 3 then
    failwith "usage: test_binding_render_encoder_codegen inventory output";
  let symbols =
    Yojson.Safe.from_file Sys.argv.(1) |> member "symbols" |> to_list
    |> List.map symbol
  in
  let ids = Binding_render_encoder_evidence.validate_inventory symbols in
  let native = Binding_render_encoder_codegen.render_native_type_checks symbols in
  if List.length ids <> 133 then failwith "render encoder owner closure drift";
  if count_substring native "[encoder " <> 131 then
    failwith "render encoder typed selector count drift";
  let channel = open_out_bin Sys.argv.(2) in
  Fun.protect ~finally:(fun () -> close_out channel) (fun () -> output_string channel native);
  Printf.printf "Metal render encoder codegen: 131 typed calls + 2 properties\n"
