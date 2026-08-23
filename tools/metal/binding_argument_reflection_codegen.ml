open Binding_argument_reflection_plan

let result_name = function
  | Bool -> "bool"
  | Unsigned -> "uint64"
  | Enum name -> "enum:" ^ name
  | String -> "copied-string"
  | Retained_object { objc_type; nullable } ->
      (if nullable then "retained-option:" else "retained:") ^ objc_type
  | Retained_array element -> "retained-array:" ^ element

let render_manifest entries =
  entries
  |> List.map (fun entry ->
       Printf.sprintf "%s\t%s\t%s\t%s\t%s"
         entry.sdk_id entry.owner entry.selector (result_name entry.result)
         entry.macos_introduced)
  |> String.concat "\n"
  |> fun body -> body ^ "\n"

let call_arguments entry =
  match entry.arguments with
  | [] -> ""
  | [ String_argument ] -> "native_name"
  | _ -> invalid_arg ("unsupported reflection arguments for " ^ entry.sdk_id)

let render_result entry expression =
  match entry.result with
  | Bool -> "BOOL native_result = " ^ expression ^ ";"
  | Unsigned -> "NSUInteger native_result = " ^ expression ^ ";"
  | Enum name -> name ^ " native_result = " ^ expression ^ ";"
  | String -> "NSString *native_result = " ^ expression ^ "; /* copy UTF-8 */"
  | Retained_object { objc_type; nullable = _ } ->
      objc_type ^ " *native_result = [" ^ expression ^ " retain]; /* owned handle */"
  | Retained_array element ->
      "NSArray<" ^ element ^ " *> *native_result = [" ^ expression
      ^ " copy]; /* retained snapshot and elements */"

let render_native_calls entries =
  entries
  |> List.map (fun entry ->
       let invocation =
         if entry.arguments = [] then
           "[receiver " ^ entry.selector ^ "]"
         else "[receiver " ^ entry.selector ^ call_arguments entry ^ "]"
       in
       Printf.sprintf
         "if (@available(macOS %s, *)) { %s } /* %s, direct typed dispatch */"
         entry.macos_introduced (render_result entry invocation) entry.sdk_id)
  |> String.concat "\n"
  |> fun output ->
  List.iter
    (fun forbidden ->
      if String.length output >= String.length forbidden then
        let rec contains i =
          i + String.length forbidden <= String.length output
          && (String.sub output i (String.length forbidden) = forbidden
             || contains (i + 1))
        in
        if contains 0 then invalid_arg ("dynamic dispatch forbidden: " ^ forbidden))
    [ "objc_msgSend"; "performSelector"; "valueForKey" ];
  output ^ "\n"

let render_snapshot_ownership_helpers () =
  {|
/* A nullable child returned at +0 becomes an ordinary owned Metal handle. */
[[maybe_unused]] static CFTypeRef prismel_reflection_retain_nullable(id child) {
  return child == nil ? nullptr : CFBridgingRetain(child);
}

/* Snapshot NSArray membership before OCaml allocation.  The copied array
   retains every child; each exported temporary handle takes its own +1, then
   releasing the snapshot cannot invalidate a handle during conversion. */
[[maybe_unused]] static CFTypeRef prismel_reflection_copy_members(NSArray *members) {
  return members == nil ? nullptr : CFBridgingRetain([members copy]);
}
[[maybe_unused]] static CFTypeRef prismel_reflection_retain_member(CFTypeRef raw_snapshot, NSUInteger index) {
  NSArray *snapshot = (__bridge NSArray *)raw_snapshot;
  return CFBridgingRetain([snapshot objectAtIndex:index]);
}
[[maybe_unused]] static void prismel_reflection_release_snapshot(CFTypeRef snapshot) {
  if (snapshot != nullptr) CFRelease(snapshot);
}
|}
