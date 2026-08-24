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

let render_raw_ml entries =
  "module Generated_globals = struct\n" ^ render_raw_body entries ^ "end\n"

let render_raw_mli entries =
  "module Generated_globals : sig\n" ^ render_raw_body entries ^ "end\n"

let unavailable entry =
  Printf.sprintf "Metal global %s requires macOS %s" entry.name
    (Binding_availability.canonical entry.macos_introduced)

let render_native entries =
  let output = Buffer.create 16384 in
  List.iter
    (fun entry ->
      Printf.bprintf output
        "extern \"C\" CAMLprim value\n%s(value unit) {\n  CAMLparam1(unit);\n  CAMLlocal2(copied, result);\n  @autoreleasepool {\n    if (@available(macOS %s, *)) {\n      static_assert(std::is_same_v<decltype(%s), %s const>,\n                    \"Metal SDK global type drift: %s\");\n      NSString *native_value = %s;\n      if (native_value == nil || native_value.UTF8String == nullptr)\n        CAMLreturn(result_error_text(\"Metal returned an invalid nonnull NSString global\"));\n      copied = caml_copy_string(native_value.UTF8String);\n      result = result_ok(copied);\n      CAMLreturn(result);\n    }\n    CAMLreturn(result_error_text(%S));\n  }\n}\n\n"
        (c_symbol entry)
        (Binding_availability.canonical entry.macos_introduced)
        entry.name entry.objc_typedef entry.name entry.name (unavailable entry))
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
  Buffer.add_string output
    "module Make (Error : sig\n  type t\n  val of_native : operation:string -> string -> t\nend) = struct\n  module Common_counter = struct type t = string let of_string value = value let to_string value = value end\n  module Common_counter_set = struct type t = string let of_string value = value let to_string value = value end\n";
  List.iter
    (fun entry ->
      let wrap = if String.equal entry.objc_typedef "MTLCommonCounter" then "Common_counter.of_string" else if String.equal entry.objc_typedef "MTLCommonCounterSet" then "Common_counter_set.of_string" else "Fun.id" in
      Printf.bprintf output
        "  let %s () =\n    match Metal_raw.Generated_globals.%s () with\n    | Ok value -> Ok (%s value)\n    | Error message -> Error (Error.of_native ~operation:%S message)\n"
        (safe_name entry) (ocaml_name entry) wrap ("Metal.Global." ^ safe_name entry))
    entries;
  Buffer.add_string output "end\n";
  Buffer.contents output

let render_safe_mli entries =
  let output = Buffer.create 4096 in
  Buffer.add_string output
    "module Make (Error : sig\n  type t\n  val of_native : operation:string -> string -> t\nend) : sig\n  module Common_counter : sig type t = private string val to_string : t -> string end\n  module Common_counter_set : sig type t = private string val to_string : t -> string end\n";
  List.iter
    (fun entry ->
      let result_type = if String.equal entry.objc_typedef "MTLCommonCounter" then "Common_counter.t" else if String.equal entry.objc_typedef "MTLCommonCounterSet" then "Common_counter_set.t" else "string" in
      Printf.bprintf output "  val %s : unit -> (%s, Error.t) result\n"
        (safe_name entry) result_type)
    entries;
  Buffer.add_string output "end\n";
  Buffer.contents output
