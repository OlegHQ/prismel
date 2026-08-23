open Binding_mesh_tile_pipeline_spec

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
          || (previous >= '0' && previous <= '9') || next_lowercase
        then Buffer.add_char output '_'
      end;
      Buffer.add_char output (Char.lowercase_ascii character))
    value;
  Buffer.contents output

let module_name owner = String.capitalize_ascii (snake_case owner)
let enum_type name = "Api." ^ snake_case name

let property_type declaration =
  match property_kind declaration with
  | Enum name -> enum_type name
  | Value_record "MTLSize" -> "Api.mtl_size"
  | Value_record name -> invalid_arg ("unsupported value record " ^ name)
  | Copied_string -> "string option"
  | Borrowed_function `Required -> "Api.function_"
  | Borrowed_function `Optional -> "Api.function_ option"
  | Borrowed_binary_archives -> "Api.binary_archive list"
  | Borrowed_dynamic_libraries -> "Api.dynamic_library list"
  | Linked_functions -> "Api.function_ list"
  | Buffer_descriptors -> "Mtl_pipeline_buffer_descriptor.t list"
  | Color_attachments ->
      if
        declaration.signature
        = "MTLTileRenderPipelineColorAttachmentDescriptorArray * _Nonnull"
      then "Api.tile_color_attachment list"
      else "Mtl_render_pipeline_color_attachment_descriptor.t list"

let owner_properties selection owner =
  List.filter (fun declaration -> declaration.owner = Some owner)
    selection.Binding_mesh_tile_pipeline_plan.properties

let api_signature =
  "module type API = sig\n  type function_\n  type binary_archive\n  type dynamic_library\n  type tile_color_attachment\n  type mtl_size\n  type mtl_blend_factor\n  type mtl_blend_operation\n  type mtl_color_write_mask\n  type mtl_mutability\n  type mtl_pixel_format\nend\n\n"

let add_record output owner properties =
  Printf.bprintf output "  module %s : sig\n    type t =\n      { "
    (module_name owner);
  List.iteri
    (fun index property ->
      if index > 0 then Buffer.add_string output "      ; ";
      Printf.bprintf output "%s : %s\n" (snake_case property.name)
        (property_type property))
    properties;
  Buffer.add_string output "      }\n  end\n\n"

let render_public_mli selection =
  let output = Buffer.create 8192 in
  Buffer.add_string output api_signature;
  Buffer.add_string output "module Make (Api : API) : sig\n";
  [ "MTLPipelineBufferDescriptor"
  ; "MTLRenderPipelineColorAttachmentDescriptor"
  ; "MTLMeshRenderPipelineDescriptor"
  ; "MTLTileRenderPipelineDescriptor"
  ]
  |> List.iter (fun owner ->
    add_record output owner (owner_properties selection owner));
  Buffer.add_string output "end\n";
  Buffer.contents output

let render_public_ml selection =
  let output = Buffer.create 8192 in
  Buffer.add_string output api_signature;
  Buffer.add_string output "module Make (Api : API) = struct\n";
  [ "MTLPipelineBufferDescriptor"
  ; "MTLRenderPipelineColorAttachmentDescriptor"
  ; "MTLMeshRenderPipelineDescriptor"
  ; "MTLTileRenderPipelineDescriptor"
  ]
  |> List.iter (fun owner ->
    let properties = owner_properties selection owner in
    Printf.bprintf output "  module %s = struct\n    type t =\n      { "
      (module_name owner);
    List.iteri
      (fun index property ->
        if index > 0 then Buffer.add_string output "      ; ";
        Printf.bprintf output "%s : %s\n" (snake_case property.name)
          (property_type property))
      properties;
    Buffer.add_string output "      }\n  end\n\n");
  Buffer.add_string output "end\n";
  Buffer.contents output

let render_native_mechanical_materializers selection =
  let output = Buffer.create 8192 in
  let owners =
    selection.Binding_mesh_tile_pipeline_plan.mechanical_properties
    |> List.filter_map (fun declaration -> declaration.owner)
    |> List.sort_uniq String.compare
  in
  List.iter
    (fun owner ->
      let properties =
        selection.mechanical_properties
        |> List.filter (fun declaration -> declaration.owner = Some owner)
      in
      let all_properties = owner_properties selection owner in
      Printf.bprintf output
        "static bool materialize_generated_%s_scalars(%s *descriptor, value raw_properties, NSString **failure) {\n"
        (snake_case owner) owner;
      List.iter
        (fun property ->
          let index =
            let rec find index = function
              | [] -> assert false
              | candidate :: _ when candidate.id = property.id -> index
              | _ :: rest -> find (index + 1) rest
            in
            find 0 all_properties
          in
          Printf.bprintf output "  if (@available(macOS %s, *)) {\n"
            (Option.get property.macos_introduced);
          (match property_kind property with
          | Enum signature ->
              Printf.bprintf output
                "    %s expected_%d = static_cast<%s>(Int64_val(Field(raw_properties, %d)));\n    descriptor.%s = expected_%d;\n    if (descriptor.%s != expected_%d) { *failure = @\"Metal pipeline enum round-trip mismatch\"; return false; }\n"
                signature index signature index property.name index property.name
                index
          | Value_record "MTLSize" ->
              Printf.bprintf output
                "    MTLSize expected_%d = mtl_size_from_generated_value(Field(raw_properties, %d));\n    descriptor.%s = expected_%d;\n    if (!MTLSizeEqual(descriptor.%s, expected_%d)) { *failure = @\"Metal pipeline size round-trip mismatch\"; return false; }\n"
                index index property.name index property.name index
          | Copied_string ->
              Printf.bprintf output
                "    NSString *expected_%d = optional_string_from_ocaml(Field(raw_properties, %d));\n    descriptor.%s = expected_%d;\n    if (!nullable_strings_equal(descriptor.%s, expected_%d)) { *failure = @\"Metal pipeline label round-trip mismatch\"; return false; }\n"
                index index property.name index property.name index
          | _ -> assert false);
          Buffer.add_string output
            "  } else { *failure = @\"Metal pipeline property is unavailable\"; return false; }\n")
        properties;
      Buffer.add_string output "  return true;\n}\n\n")
    owners;
  Buffer.contents output

let render_manifest (selection : Binding_mesh_tile_pipeline_plan.selection) =
  let ids declarations =
    `List (List.map (fun declaration -> `String declaration.id) declarations)
  in
  `Assoc
    [ "declaration_count", `Int (List.length selection.declarations)
    ; "class_count", `Int (List.length selection.classes)
    ; "method_count", `Int (List.length selection.methods)
    ; "property_count", `Int (List.length selection.properties)
    ; ( "mechanical_property_count"
      , `Int (List.length selection.mechanical_properties) )
    ; ( "handwritten_property_count"
      , `Int (List.length selection.handwritten_properties) )
    ; "safe_bound_count", `Int 0
    ; "identifiers", ids selection.declarations
    ; "mechanical_property_ids", ids selection.mechanical_properties
    ; "handwritten_property_ids", ids selection.handwritten_properties
    ]
