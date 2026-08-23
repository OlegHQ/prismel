open Binding_global_string_spec

let render_raw_body entries =
  let output = Buffer.create 4096 in
  List.iter
    (fun entry ->
      Printf.bprintf output
        "  external %s : unit -> (string, string) result = %S\n"
        (ocaml_name entry) (c_symbol entry))
    entries;
  Buffer.contents output

let render_raw entries =
  "module Generated_globals = struct\n" ^ render_raw_body entries ^ "end\n"

let render_raw_ml = render_raw
let render_raw_mli = render_raw

let unavailable entry =
  Printf.sprintf "Metal global %s requires macOS %s" entry.name
    (Binding_availability.canonical entry.macos_introduced)

let render_native entries =
  let output = Buffer.create 16384 in
  List.iter
    (fun entry ->
      Printf.bprintf output
        "static_assert(std::is_same_v<decltype(%s), %s const>,\n              \"Metal SDK global type drift: %s\");\n"
        entry.name entry.objc_typedef entry.name;
      Printf.bprintf output
        "extern \"C\" CAMLprim value\n%s(value unit) {\n  CAMLparam1(unit);\n  CAMLlocal2(copied, result);\n  @autoreleasepool {\n    if (@available(macOS %s, *)) {\n      NSString *native_value = %s;\n      if (native_value == nil || native_value.UTF8String == nullptr)\n        CAMLreturn(result_error_text(\"Metal returned an invalid nonnull NSString global\"));\n      copied = caml_copy_string(native_value.UTF8String);\n      result = result_ok(copied);\n      CAMLreturn(result);\n    }\n    CAMLreturn(result_error_text(%S));\n  }\n}\n\n"
        (c_symbol entry)
        (Binding_availability.canonical entry.macos_introduced)
        entry.name (unavailable entry))
    entries;
  let result = Buffer.contents output in
  List.iter
    (fun forbidden ->
      if String.contains result forbidden.[0] then begin
        let length = String.length forbidden in
        let rec contains offset =
          offset + length <= String.length result
          && (String.sub result offset length = forbidden || contains (offset + 1))
        in
        if contains 0 then invalid_arg ("forbidden dynamic dispatch: " ^ forbidden)
      end)
    [ "objc_msgSend"; "performSelector"; "valueForKey" ];
  result

let safe_name entry =
  let generated = ocaml_name entry in
  let prefix_length = String.length "generated_global_" in
  String.sub generated prefix_length (String.length generated - prefix_length)

let render_safe_ml entries =
  let output = Buffer.create 4096 in
  List.iter
    (fun entry ->
      Printf.bprintf output "let %s () = Raw.Generated_globals.%s ()\n"
        (safe_name entry) (ocaml_name entry))
    entries;
  Buffer.contents output

let render_safe_mli entries =
  let output = Buffer.create 4096 in
  List.iter
    (fun entry ->
      Printf.bprintf output "val %s : unit -> (string, string) result\n"
        (safe_name entry))
    entries;
  Buffer.contents output
