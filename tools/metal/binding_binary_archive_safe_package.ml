type descriptor_kind = Function | Stitched_library | Mesh_pipeline | Render_pipeline | Tile_pipeline
type owned = { token : int; device : int; destroyed : bool }
type descriptor = { owned : owned; kind : descriptor_kind }
type archive = { device : int; mutable retained : int list; mutable destroyed : bool }

let callable_ids =
  [ "method:-[MTLBinaryArchive addFunctionWithDescriptor:library:error:]"
  ; "method:-[MTLBinaryArchive addLibraryWithDescriptor:error:]"
  ; "method:-[MTLBinaryArchive addMeshRenderPipelineFunctionsWithDescriptor:error:]"
  ; "method:-[MTLBinaryArchive addRenderPipelineFunctionsWithDescriptor:error:]"
  ; "method:-[MTLBinaryArchive addTileRenderPipelineFunctionsWithDescriptor:error:]" ]

let create ~device = { device; retained = []; destroyed = false }

let validate_owned (archive : archive) label (owned : owned) =
  if archive.destroyed then Error "destroyed binary archive"
  else if owned.destroyed then Error ("destroyed " ^ label)
  else if owned.device <> archive.device then Error (label ^ " belongs to another device")
  else Ok ()

let add (archive : archive) ~expected_kind ~(descriptor : descriptor) ~(library : owned option) ~native_result =
  if descriptor.kind <> expected_kind then Error "binary archive descriptor kind mismatch"
  else match validate_owned archive "binary archive descriptor" descriptor.owned with
  | Error error -> Error error
  | Ok () ->
      (match library with
       | Some library ->
           (match validate_owned archive "function library" library with
            | Error error -> Error error
            | Ok () ->
                (match native_result with
                 | Error error -> Error error
                 | Ok () -> archive.retained <- library.token :: descriptor.owned.token :: archive.retained; Ok ()))
       | None ->
           (match native_result with
            | Error error -> Error error
            | Ok () -> archive.retained <- descriptor.owned.token :: archive.retained; Ok ()))

let add_function archive ~descriptor ~library ~native_result =
  add archive ~expected_kind:Function ~descriptor ~library:(Some library) ~native_result
let add_library archive ~descriptor ~native_result =
  add archive ~expected_kind:Stitched_library ~descriptor ~library:None ~native_result
let add_mesh_pipeline archive ~descriptor ~native_result =
  add archive ~expected_kind:Mesh_pipeline ~descriptor ~library:None ~native_result
let add_render_pipeline archive ~descriptor ~native_result =
  add archive ~expected_kind:Render_pipeline ~descriptor ~library:None ~native_result
let add_tile_pipeline archive ~descriptor ~native_result =
  add archive ~expected_kind:Tile_pipeline ~descriptor ~library:None ~native_result

let retained_tokens archive = List.rev archive.retained
let destroy archive = if not archive.destroyed then begin archive.destroyed <- true; archive.retained <- [] end

let validate_handoff () =
  if List.length callable_ids <> 5 || List.length (List.sort_uniq String.compare callable_ids) <> 5 then
    invalid_arg "BinaryArchive callable5 drift"
