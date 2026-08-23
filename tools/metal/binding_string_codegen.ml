open Binding_string_spec

let qualified_entries () =
  List.filter
    (fun entry ->
      match entry.receiver_status with
      | Qualified_direct _ | Qualified_polymorphic _ -> true
      | Pending_receiver_catalog -> false)
    Binding_string_properties.entries

let suffix = function `Getter -> "get" | `Setter -> "set"

let snake_case value =
  let output = Buffer.create (String.length value + 8) in
  String.iteri
    (fun index character ->
      let uppercase = character >= 'A' && character <= 'Z' in
      if uppercase && index > 0 then begin
        let previous = value.[index - 1] in
        let next_lowercase =
          index + 1 < String.length value
          && value.[index + 1] >= 'a' && value.[index + 1] <= 'z'
        in
        if
          (previous >= 'a' && previous <= 'z')
          || (previous >= '0' && previous <= '9')
          || next_lowercase
        then
          Buffer.add_char output '_'
      end;
      Buffer.add_char output (Char.lowercase_ascii character))
    value;
  Buffer.contents output

let ocaml_name entry direction =
  "generated_" ^ snake_case entry.owner ^ "_" ^ snake_case entry.name ^ "_"
  ^ suffix direction

let c_symbol entry direction =
  "caml_prismel_metal_" ^ ocaml_name entry direction

let add_external output entry direction =
  let argument_type, result_type =
    match direction with
    | `Getter -> "Types.handle", getter_ocaml_type entry
    | `Setter ->
        (match setter_ocaml_type entry with
        | Some value -> "Types.handle -> " ^ value, "unit"
        | None -> invalid_arg ("readonly Metal string property: " ^ entry.property_sdk_id))
  in
  Printf.bprintf output "  external %s :\n    %s -> (%s, string) result =\n    %S\n\n"
    (ocaml_name entry direction) argument_type result_type
    (c_symbol entry direction)

let render_raw_body entries =
  let output = Buffer.create 2048 in
  List.iter
    (fun entry ->
      add_external output entry `Getter;
      Option.iter (fun _ -> add_external output entry `Setter) entry.setter_sdk_id)
    entries;
  Buffer.contents output

let render_raw entries =
  "module Make (Types : sig\n  type handle\nend) = struct\n"
  ^ render_raw_body entries ^ "end\n"

let render_raw_ml = render_raw
let render_raw_mli = render_raw

let c_string value = Printf.sprintf "%S" value

let add_receiver output receiver =
  match receiver.Binding_receiver_catalog.bridge_access with
  | Binding_receiver_catalog.Object_of_handle ->
      Printf.bprintf output "        %s %s =\n            object_of_handle(raw_receiver, Handle_kind::%s);\n"
        receiver.objc_receiver_type receiver.local_name receiver.handle_kind
  | Binding_receiver_catalog.Object_of_helper helper ->
      Printf.bprintf output "        %s %s = %s(raw_receiver);\n"
        receiver.objc_receiver_type receiver.local_name helper
  | Binding_receiver_catalog.Wrapped_property { wrapper_type; property } ->
      Printf.bprintf output "        %s receiver_state =\n            object_of_handle(raw_receiver, Handle_kind::%s);\n"
        wrapper_type receiver.handle_kind;
      Printf.bprintf output "        %s %s = receiver_state.%s;\n"
        receiver.objc_receiver_type receiver.local_name property

let availability entry = Binding_availability.canonical entry.macos_introduced

let unavailable entry =
  Printf.sprintf "Metal selector %s requires macOS %s" entry.name
    (availability entry)

let add_getter output entry receiver =
  Printf.bprintf output "extern \"C\" CAMLprim value\n%s(value raw_receiver) {\n"
    (c_symbol entry `Getter);
  Buffer.add_string output "  CAMLparam1(raw_receiver);\n  CAMLlocal3(result, option, copied);\n  @autoreleasepool {\n";
  Printf.bprintf output "    if (@available(macOS %s, *)) {\n      @try {\n"
    (availability entry);
  add_receiver output receiver;
  Printf.bprintf output "        NSString *native_result = [%s %s];\n"
    receiver.local_name (getter_selector entry);
  (match entry.nullability with
  | Nullable ->
      Buffer.add_string output
        "        option = copy_optional_string(native_result);\n        result = result_ok(option);\n"
  | Nonnull ->
      Buffer.add_string output
        "        if (native_result == nil || native_result.UTF8String == nullptr) {\n          CAMLreturn(result_error_text(\"Metal returned an invalid nonnull NSString\"));\n        }\n        copied = caml_copy_string(native_result.UTF8String);\n        result = result_ok(copied);\n");
  Buffer.add_string output
    "        CAMLreturn(result);\n      } @catch (NSException *exception) {\n        CAMLreturn(result_error(exception.reason));\n      }\n    }\n";
  Printf.bprintf output "    CAMLreturn(result_error_text(%s));\n  }\n}\n\n"
    (c_string (unavailable entry))

let add_setter output entry receiver selector =
  Printf.bprintf output "extern \"C\" CAMLprim value\n%s(value raw_receiver, value raw_value) {\n"
    (c_symbol entry `Setter);
  Buffer.add_string output "  CAMLparam2(raw_receiver, raw_value);\n  @autoreleasepool {\n";
  Printf.bprintf output "    if (@available(macOS %s, *)) {\n      @try {\n"
    (availability entry);
  add_receiver output receiver;
  (match entry.nullability with
  | Nullable ->
      Buffer.add_string output
        "        NSString *native_value = raw_value == Val_none ? nil : string_from_ocaml(Field(raw_value, 0));\n"
  | Nonnull ->
      Buffer.add_string output
        "        NSString *native_value = string_from_ocaml(raw_value);\n");
  Printf.bprintf output "        [%s %snative_value];\n        CAMLreturn(result_unit());\n"
    receiver.local_name selector;
  Buffer.add_string output
    "      } @catch (NSException *exception) {\n        CAMLreturn(result_error(exception.reason));\n      }\n    }\n";
  Printf.bprintf output "    CAMLreturn(result_error_text(%s));\n  }\n}\n\n"
    (c_string (unavailable entry))

let render_native entries =
  let output = Buffer.create 8192 in
  List.iter
    (fun entry ->
      match entry.receiver_status with
      | Pending_receiver_catalog ->
          invalid_arg ("unqualified Metal string receiver: " ^ entry.owner)
      | Qualified_direct receiver ->
          add_getter output entry receiver;
          Option.iter (add_setter output entry receiver) (setter_selector entry)
      | Qualified_polymorphic receiver ->
          let direct : Binding_receiver_catalog.receiver =
            { sdk_owner = receiver.sdk_owner
            ; objc_receiver_type = receiver.objc_receiver_type
            ; handle_kind = ""
            ; local_name = receiver.local_name
            ; raw_name = receiver.raw_name
            ; owner_binding = Binding_receiver_catalog.One_to_one
            ; bridge_access =
                Binding_receiver_catalog.Object_of_helper receiver.helper
            }
          in
          add_getter output entry direct;
          Option.iter (add_setter output entry direct) (setter_selector entry))
    entries;
  let result = Buffer.contents output in
  List.iter
    (fun forbidden ->
      if String.length result >= String.length forbidden then
        let rec contains offset =
          if offset + String.length forbidden > String.length result then false
          else if String.sub result offset (String.length forbidden) = forbidden then true
          else contains (offset + 1)
        in
        if contains 0 then invalid_arg ("forbidden dynamic dispatch: " ^ forbidden))
    [ "objc_msgSend"; "performSelector"; "valueForKey" ];
  result
