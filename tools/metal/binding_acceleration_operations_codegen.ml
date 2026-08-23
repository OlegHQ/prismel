let render_contract
    (selection : Binding_acceleration_operations_plan.selection) =
  let output = Buffer.create 30000 in
  List.iter
    (fun (value : Binding_acceleration_operations_plan.declaration) ->
      Printf.bprintf output "%s\t%s\t%s\t%s\n" value.id value.kind
        (Option.value ~default:"global" value.owner) value.signature)
    selection.declarations;
  Buffer.contents output

let render_safe_model
    (selection : Binding_acceleration_operations_plan.selection) =
  let output = Buffer.create 12000 in
  Buffer.add_string output
    "type ownership = Owned_handle | Completion_retained | Copied_value | Capability_rejected\n";
  List.iter
    (fun (value : Binding_acceleration_operations_plan.declaration) ->
      let ownership =
        if value.kind = "class" || value.kind = "protocol" then "Owned_handle"
        else if String.starts_with ~prefix:"instance () ->" value.signature then
          "Copied_value"
        else if value.kind = "method" then "Completion_retained"
        else "Capability_rejected"
      in
      Printf.bprintf output "let evidence_%d = (%S, %s)\n"
        (Buffer.length output) value.id ownership)
    selection.declarations;
  Buffer.contents output

let split_arguments arguments =
  if String.trim arguments = "" then []
  else
    let depth = ref 0 and start = ref 0 and values = ref [] in
    String.iteri
      (fun index -> function
        | '<' | '(' -> incr depth
        | '>' | ')' -> decr depth
        | ',' when !depth = 0 ->
            values :=
              String.trim (String.sub arguments !start (index - !start))
              :: !values;
            start := index + 1
        | _ -> ())
      arguments;
    List.rev
      (String.sub arguments !start (String.length arguments - !start)
       |> String.trim |> fun value -> value :: !values)

let signature_parts signature =
  let opening = String.index signature '(' in
  let marker = ") -> " in
  let rec find index =
    if index + String.length marker > String.length signature then
      invalid_arg ("Metal operation signature has no result: " ^ signature)
    else if String.sub signature index (String.length marker) = marker then index
    else find (index + 1)
  in
  let closing = find (opening + 1) in
  let arguments =
    String.sub signature (opening + 1) (closing - opening - 1)
    |> split_arguments
  in
  let result =
    String.sub signature (closing + String.length marker)
      (String.length signature - closing - String.length marker)
    |> String.trim
  in
  arguments, result

let selector_labels name =
  if not (String.contains name ':') then [ name ]
  else
    name |> String.split_on_char ':'
    |> List.filter (fun value -> value <> "")

let receiver_type owner =
  if String.ends_with ~suffix:"Descriptor" owner
     || String.ends_with ~suffix:"DescriptorArray" owner
  then owner ^ " *"
  else "id<" ^ owner ^ ">"

let native_result owner kind result =
  if kind = "class" && String.starts_with ~prefix:"instancetype" result then
    owner ^ " *"
  else result

let render_native_calls
    (selection : Binding_acceleration_operations_plan.selection) =
  let output = Buffer.create 70000 in
  Buffer.add_string output
    "#pragma clang diagnostic push\n#pragma clang diagnostic ignored \"-Wnullability-completeness\"\n";
  selection.declarations
  |> List.filter
       (fun (value : Binding_acceleration_operations_plan.declaration) ->
         value.kind = "method")
  |> List.iteri (fun index
      (value : Binding_acceleration_operations_plan.declaration) ->
    let owner = Option.get value.owner in
    let arguments, result = signature_parts value.signature in
    let class_method = String.starts_with ~prefix:"class " value.signature in
    let result = native_result owner (if class_method then "class" else "instance") result in
    let availability = Option.value ~default:"10.11" value.macos_introduced in
    Printf.bprintf output
      "/* %s */ API_AVAILABLE(macos(%s)) static __attribute__((unused)) %s prismel_acceleration_operation_%03d("
      value.id availability result index;
    if not class_method then
      Printf.bprintf output "%s receiver%s" (receiver_type owner)
        (if arguments = [] then "" else ", ");
    arguments |> List.iteri (fun argument_index argument ->
      Printf.bprintf output "%s argument_%d%s" argument argument_index
        (if argument_index + 1 = List.length arguments then "" else ", "));
    Buffer.add_string output ") { ";
    if result <> "void" then Buffer.add_string output "return ";
    Printf.bprintf output "[%s " (if class_method then owner else "receiver");
    let labels = selector_labels value.name in
    (match arguments with
    | [] -> Buffer.add_string output value.name
    | _ ->
        List.iteri (fun argument_index _ ->
          Printf.bprintf output "%s:argument_%d%s"
            (List.nth labels argument_index) argument_index
            (if argument_index + 1 = List.length arguments then "" else " "))
          arguments);
    Buffer.add_string output "]; }\n");
  Buffer.add_string output "#pragma clang diagnostic pop\n";
  Buffer.contents output

let raw_type signature =
  if signature = "void" then "unit"
  else if signature = "BOOL" then "bool"
  else if signature = "NSUInteger" || String.starts_with ~prefix:"MTL" signature
          && not (String.contains signature '*') then "int64"
  else if String.contains signature '*' || String.starts_with ~prefix:"id<" signature
  then "handle"
  else "operation_value"

let render_raw_mli
    (selection : Binding_acceleration_operations_plan.selection) =
  let output = Buffer.create 30000 in
  Buffer.add_string output "type operation_value\n";
  selection.declarations
  |> List.filter
       (fun (value : Binding_acceleration_operations_plan.declaration) ->
         value.kind = "method")
  |> List.iteri (fun index
      (value : Binding_acceleration_operations_plan.declaration) ->
    let arguments, result = signature_parts value.signature in
    let class_method = String.starts_with ~prefix:"class " value.signature in
    Printf.bprintf output "external acceleration_operation_%03d : " index;
    if not class_method then Buffer.add_string output "handle -> ";
    List.iter (fun argument -> Printf.bprintf output "%s -> " (raw_type argument)) arguments;
    let symbol = Printf.sprintf "caml_prismel_metal_acceleration_operation_%03d" index in
    Printf.bprintf output "(%s, string) result = " (raw_type result);
    if List.length arguments + (if class_method then 0 else 1) > 5 then
      Printf.bprintf output "%S %S\n" (symbol ^ "_bytecode") symbol
    else Printf.bprintf output "%S\n" symbol);
  Buffer.contents output

let render_safe_policies
    (selection : Binding_acceleration_operations_plan.selection) =
  let output = Buffer.create 30000 in
  selection.declarations
  |> List.filter
       (fun (value : Binding_acceleration_operations_plan.declaration) ->
         value.kind = "method")
  |> List.iteri (fun index
      (value : Binding_acceleration_operations_plan.declaration) ->
    let policy =
      if String.starts_with ~prefix:"new" value.name
         || String.starts_with ~prefix:"functionHandle" value.name
      then "owned_result"
      else if String.starts_with ~prefix:"set" value.name
           || String.starts_with ~prefix:"use" value.name
           || String.starts_with ~prefix:"build" value.name
           || String.starts_with ~prefix:"refit" value.name
           || String.starts_with ~prefix:"copy" value.name
      then "same_device_completion_retained"
      else if String.starts_with ~prefix:"sample" value.name
           || String.starts_with ~prefix:"wait" value.name
           || String.starts_with ~prefix:"update" value.name
      then "encoder_state_retained"
      else "copied_value"
    in
    Printf.bprintf output "let acceleration_operation_%03d_policy = %S, %S\n"
      index value.id policy);
  Buffer.contents output
