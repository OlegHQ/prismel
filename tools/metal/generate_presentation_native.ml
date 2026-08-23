let declaration_of_json json : Binding_presentation_spec.declaration =
  let open Yojson.Safe.Util in
  { id=json|>member "id"|>to_string; kind=json|>member "kind"|>to_string
  ; owner=json|>member "owner"|>to_string_option; name=json|>member "name"|>to_string
  ; signature=json|>member "signature"|>to_string
  ; classification=json|>member "classification"|>to_string }

let write path contents =
  let channel=open_out_bin path in Fun.protect ~finally:(fun()->close_out channel)
    (fun()->output_string channel contents)

let () =
  let inventory=ref "" and native=ref "" and raw=ref "" in
  Arg.parse ["--inventory",Arg.Set_string inventory,"inventory JSON";
             "--native",Arg.Set_string native,"native output";
             "--raw",Arg.Set_string raw,"raw OCaml output"] ignore "presentation native generator";
  if !inventory="" || !native="" || !raw="" then invalid_arg "missing output option";
  let json=Yojson.Safe.from_file !inventory in
  let declarations=Yojson.Safe.Util.(json|>member "symbols"|>to_list|>List.map declaration_of_json) in
  Binding_presentation_native_codegen.validate declarations;
  write !native (Binding_presentation_native_codegen.render_native declarations);
  write !raw (Binding_presentation_native_codegen.render_raw_externals declarations^"\n")
