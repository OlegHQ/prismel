let string name json = Yojson.Safe.Util.(json |> member name |> to_string)

let optional_string name json =
  match Yojson.Safe.Util.(json |> member name) with
  | `String value -> Some value
  | `Null -> None
  | _ -> failwith name

let declaration json : Binding_acceleration_ownership_plan.declaration =
  { id = string "id" json
  ; kind = string "kind" json
  ; owner = optional_string "owner" json
  ; name = string "name" json
  ; header = string "header" json
  ; signature = string "signature" json
  ; macos_introduced = optional_string "macos_introduced" json
  ; classification = string "classification" json }

let contains haystack needle =
  let haystack_length = String.length haystack in
  let needle_length = String.length needle in
  let rec loop index =
    index + needle_length <= haystack_length
    && (String.sub haystack index needle_length = needle || loop (index + 1))
  in
  needle_length = 0 || loop 0

let count haystack needle =
  let rec loop offset total =
    if offset + String.length needle > String.length haystack then total
    else if String.sub haystack offset (String.length needle) = needle then
      loop (offset + String.length needle) (total + 1)
    else loop (offset + 1) total
  in
  loop 0 0

let () =
  if Array.length Sys.argv <> 2 then failwith "inventory path required";
  let json = Yojson.Safe.from_file Sys.argv.(1) in
  let declarations =
    Yojson.Safe.Util.(json |> member "symbols" |> to_list |> List.map declaration)
  in
  let selection = Binding_acceleration_ownership_plan.select declarations in
  let generated =
    Binding_acceleration_ownership_adapter.render_native_materializers selection
  in
  if count generated "/* property:" <> 49 then
    failwith "native materializer property count drift";
  if not (contains generated "id<MTLBuffer>") then failwith "buffer materializer missing";
  if not (contains generated "MTL4BufferRange") then failwith "buffer-range materializer missing";
  if not (contains generated "MTLResourceID") then failwith "resource-ID materializer missing";
  if not (contains generated "NSArray *") then failwith "array materializer missing";
  if not (contains generated "NSString *") then failwith "string materializer missing";
  if contains generated "objc_msgSend" then failwith "dynamic dispatch generated";
  if contains generated "NSSelectorFromString" then failwith "string selector generated";
  if String.length generated < 20_000 then failwith "native materializer output too small";
  Printf.printf
    "Metal acceleration ownership materializers: 49 typed properties / 146 IDs (%d bytes)\n"
    (String.length generated)
