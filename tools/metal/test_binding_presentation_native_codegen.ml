let contains text needle =
  let rec loop i=i+String.length needle<=String.length text &&
    (String.sub text i (String.length needle)=needle || loop(i+1)) in loop 0
let () =
  if List.length Binding_presentation_native_codegen.generated_ids <> 104 then
    failwith "presentation mechanical count drift";
  let native=In_channel.with_open_bin Sys.argv.(1) In_channel.input_all in
  let raw=In_channel.with_open_bin Sys.argv.(2) In_channel.input_all in
  if contains native "objc_msgSend" || contains native "performSelector" then
    failwith "dynamic selector dispatch generated";
  List.iter (fun id->if not(contains native id) && String.starts_with ~prefix:"method:" id
    then failwith("missing native method "^id))
    Binding_presentation_native_codegen.generated_ids;
  if not(contains raw "external presentation_") then failwith "raw externals missing"
  else
    let line_count prefix text =
      text |> String.split_on_char '\n'
      |> List.fold_left (fun count line ->
           if String.starts_with ~prefix line then count+1 else count) 0
    in
    if line_count "static " native <> 72 then failwith "typed adapter count drift";
    if line_count "extern \"C\" CAMLprim" native <> 72 then
      failwith "CAML wrapper count drift";
    if line_count "external " raw <> 72 then failwith "raw external count drift"
