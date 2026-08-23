let string name json = Yojson.Safe.Util.(json |> member name |> to_string)
let optional_string name json =
  match Yojson.Safe.Util.(json |> member name) with
  | `String value -> Some value | `Null -> None | _ -> failwith name

let declaration json : Binding_acceleration_operations_plan.declaration =
  { id = string "id" json; kind = string "kind" json
  ; owner = optional_string "owner" json; name = string "name" json
  ; header = string "header" json; signature = string "signature" json
  ; macos_introduced = optional_string "macos_introduced" json
  ; classification = string "classification" json }

let () =
  if Array.length Sys.argv <> 2 && Array.length Sys.argv <> 3 then
    failwith "inventory path and optional native output required";
  let json = Yojson.Safe.from_file Sys.argv.(1) in
  let declarations =
    Yojson.Safe.Util.(json |> member "symbols" |> to_list |> List.map declaration)
  in
  let selection = Binding_acceleration_operations_plan.select declarations in
  Binding_acceleration_operations_evidence.validate selection;
  let native = Binding_acceleration_operations_codegen.render_native_calls selection in
  let raw = Binding_acceleration_operations_codegen.render_raw_mli selection in
  let policies = Binding_acceleration_operations_codegen.render_safe_policies selection in
  if String.length native < 35_000 || String.length raw < 13_000
     || String.length policies < 14_000 then
    failwith
      (Printf.sprintf "operational generated output too small: %d/%d/%d"
         (String.length native) (String.length raw) (String.length policies));
  if String.contains native '\000' || String.contains raw '\000' then
    failwith "operational generated output invalid";
  let contains source needle =
    let rec loop index =
      index + String.length needle <= String.length source
      && (String.sub source index (String.length needle) = needle
          || loop (index + 1))
    in
    needle = "" || loop 0
  in
  if contains native "objc_msgSend" || contains native "NSSelectorFromString"
  then failwith "operational native code uses dynamic dispatch";
  if not (contains raw "_bytecode") then
    failwith "high-arity raw bytecode entry points missing";
  if not (contains policies "same_device_completion_retained")
     || not (contains policies "owned_result")
     || not (contains policies "encoder_state_retained") then
    failwith "safe operational policy closure missing";
  if Array.length Sys.argv = 3 then begin
    let channel = open_out_bin Sys.argv.(2) in
    output_string channel "#import <Foundation/Foundation.h>\n#import <Metal/Metal.h>\n";
    output_string channel native;
    close_out channel
  end;
  Printf.printf
    "Metal acceleration operational batch: %d IDs / %d methods across %d owners\n"
    (List.length selection.identifiers) selection.method_count
    (List.length selection.owners)
