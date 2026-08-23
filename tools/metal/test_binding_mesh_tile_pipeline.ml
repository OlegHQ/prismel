let fail format = Printf.ksprintf failwith format

let declaration json : Binding_mesh_tile_pipeline_spec.declaration =
  let open Yojson.Safe.Util in
  let optional_string name =
    match json |> member name with
    | `String value -> Some value
    | `Null -> None
    | _ -> fail "invalid %s" name
  in
  { id = json |> member "id" |> to_string
  ; kind = json |> member "kind" |> to_string
  ; owner = optional_string "owner"
  ; name = json |> member "name" |> to_string
  ; header = json |> member "header" |> to_string
  ; signature = json |> member "signature" |> to_string
  ; macos_introduced = optional_string "macos_introduced"
  ; attributes =
      json |> member "attributes" |> to_list |> List.map to_string
  ; classification = json |> member "classification" |> to_string
  }

let contains text fragment =
  let rec loop offset =
    offset + String.length fragment <= String.length text
    && (String.sub text offset (String.length fragment) = fragment
        || loop (offset + 1))
  in
  loop 0

let require text fragment =
  if not (contains text fragment) then fail "generated output lacks %S" fragment

let () =
  if Array.length Sys.argv <> 2 then fail "usage: %s INVENTORY" Sys.argv.(0);
  let inventory = Yojson.Safe.from_file Sys.argv.(1) in
  let declarations =
    Yojson.Safe.Util.(inventory |> member "symbols" |> to_list)
    |> List.map declaration
  in
  let selection = Binding_mesh_tile_pipeline_plan.select declarations in
  Binding_mesh_tile_pipeline_evidence.validate selection;
  let mli = Binding_mesh_tile_pipeline_codegen.render_public_mli selection in
  let ml = Binding_mesh_tile_pipeline_codegen.render_public_ml selection in
  let native =
    Binding_mesh_tile_pipeline_codegen.render_native_mechanical_materializers
      selection
  in
  require mli "module Mtl_mesh_render_pipeline_descriptor";
  require mli "object_function : Api.function_ option";
  require mli "required_threads_per_mesh_threadgroup : Api.mtl_size";
  require mli "module Mtl_tile_render_pipeline_descriptor";
  require mli "tile_function : Api.function_";
  require mli "module Mtl_render_pipeline_color_attachment_descriptor";
  require mli "source_rgb_blend_factor : Api.mtl_blend_factor";
  require ml "module Make (Api : API) = struct";
  require native "descriptor.requiredThreadsPerMeshThreadgroup";
  require native "nullable_strings_equal(descriptor.label";
  List.iter
    (fun forbidden ->
      if contains native forbidden then fail "dynamic dispatch emitted: %s" forbidden)
    [ "objc_msgSend"; "performSelector"; "valueForKey" ];
  let manifest = Binding_mesh_tile_pipeline_codegen.render_manifest selection in
  let count = Yojson.Safe.Util.(manifest |> member "declaration_count" |> to_int) in
  if count <> 105 then fail "manifest declaration count drift";
  Printf.printf
    "Metal mesh/tile pipeline foundation: %d classes + %d methods + %d properties = %d IDs; %d mechanical and %d ownership-aware properties\n"
    (List.length selection.classes) (List.length selection.methods)
    (List.length selection.properties) (List.length selection.declarations)
    (List.length selection.mechanical_properties)
    (List.length selection.handwritten_properties)
