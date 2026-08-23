let substring_between value left right =
  match String.index_opt value left, String.rindex_opt value right with
  | Some start, Some finish when start < finish ->
      String.sub value (start + 1) (finish - start - 1)
  | _ -> invalid_arg ("malformed render-encoder identity: " ^ value)

let method_selector id =
  let body = substring_between id '[' ']' in
  let prefix = Binding_render_encoder_plan.owner ^ " " in
  if not (String.starts_with ~prefix body) then
    invalid_arg ("unexpected render-encoder owner: " ^ id);
  String.sub body (String.length prefix) (String.length body - String.length prefix)

let argument_types signature =
  let prefix = "instance (" in
  let suffix = ") -> void" in
  if not (String.starts_with ~prefix signature && String.ends_with ~suffix signature)
  then []
  else
    let body =
      String.sub signature (String.length prefix)
        (String.length signature - String.length prefix - String.length suffix)
    in
    if body = "" then []
    else String.split_on_char ',' body |> List.map String.trim

let dummy_argument signature =
  if String.contains signature '*' || String.starts_with ~prefix:"id<" signature
  then "nil"
  else
    match signature with
    | "BOOL" -> "NO"
    | "float" -> "0.0f"
    | "NSUInteger" -> "NSUInteger(0)"
    | "NSInteger" -> "NSInteger(0)"
    | "uint32_t" -> "uint32_t(0)"
    | "uint64_t" -> "uint64_t(0)"
    | "NSRange" -> "NSMakeRange(0, 0)"
    | "MTLSize" -> "MTLSizeMake(1, 1, 1)"
    | "MTLViewport" -> "MTLViewport{}"
    | "MTLScissorRect" -> "MTLScissorRect{}"
    | value when String.starts_with ~prefix:"MTL" value ->
        "static_cast<" ^ value ^ ">(0)"
    | value -> invalid_arg ("unsupported render-encoder argument type: " ^ value)

let render_call symbol =
  let selector = method_selector symbol.Binding_render_encoder_evidence.id in
  let arguments = argument_types symbol.signature in
  if arguments = [] then "    [encoder " ^ selector ^ "];\n"
  else
    let pieces = String.split_on_char ':' selector in
    let pieces =
      match List.rev pieces with "" :: rest -> List.rev rest | _ -> pieces
    in
    if List.length pieces <> List.length arguments then
      invalid_arg ("selector/signature arity mismatch: " ^ symbol.id);
    let call = Buffer.create 256 in
    Buffer.add_string call "    [encoder ";
    List.iter2
      (fun piece argument ->
        Buffer.add_string call piece;
        Buffer.add_char call ':';
        Buffer.add_string call (dummy_argument argument);
        Buffer.add_char call ' ')
      pieces arguments;
    Buffer.add_string call "];\n";
    Buffer.contents call

let render_native_type_checks symbols =
  let selected =
    List.filter
      (fun symbol ->
        symbol.Binding_render_encoder_evidence.owner
        = Some Binding_render_encoder_plan.owner)
      symbols
  in
  let output = Buffer.create 32768 in
  Buffer.add_string output
    "#import <Foundation/Foundation.h>\n#import <Metal/Metal.h>\n#include <cstdint>\n\n/* Exact MTLRenderCommandEncoder owner closure. Every method below is a\n   statically typed direct selector expression; dynamic dispatch is forbidden. */\nstatic void prismel_metal_typecheck_render_encoder_owner(id<MTLRenderCommandEncoder> encoder) {\n  if (false) {\n";
  List.iter
    (fun symbol ->
      Printf.bprintf output "    /* %s :: %s */\n"
        symbol.Binding_render_encoder_evidence.id symbol.signature;
      if symbol.kind = "method" then Buffer.add_string output (render_call symbol))
    (List.sort
       (fun (left : Binding_render_encoder_evidence.symbol)
            (right : Binding_render_encoder_evidence.symbol) ->
         String.compare left.id right.id)
       selected);
  Buffer.add_string output "  }\n}\n";
  let rendered = Buffer.contents output in
  List.iter
    (fun forbidden ->
      if String.contains rendered forbidden.[0] then
        let rec search offset =
          offset + String.length forbidden <= String.length rendered
          && (String.sub rendered offset (String.length forbidden) = forbidden
             || search (offset + 1))
        in
        if search 0 then invalid_arg ("dynamic dispatch forbidden: " ^ forbidden))
    [ "objc_msgSend"; "performSelector"; "valueForKey" ];
  rendered

let render_manifest symbols =
  let identifiers = Binding_render_encoder_evidence.validate_inventory symbols in
  `Assoc
    [ "owner", `String Binding_render_encoder_plan.owner
    ; "declaration_count", `Int (List.length identifiers)
    ; "safe_bound_count", `Int 0
    ; "signature_digest",
      `String Binding_render_encoder_plan.expected_signature_digest
    ; "identifiers", `List (List.map (fun id -> `String id) identifiers)
    ]
