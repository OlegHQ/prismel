type declaration =
  { id : string
  ; kind : string
  ; owner : string option
  ; name : string
  ; header : string
  ; signature : string
  ; macos_introduced : string option
  ; attributes : string list
  ; classification : string
  }

type property_kind =
  | Enum of string
  | Value_record of string
  | Copied_string
  | Borrowed_function of [ `Required | `Optional ]
  | Borrowed_binary_archives
  | Borrowed_dynamic_libraries
  | Linked_functions
  | Buffer_descriptors
  | Color_attachments

let owners =
  [ "MTLMeshRenderPipelineDescriptor"
  ; "MTLTileRenderPipelineDescriptor"
  ; "MTLPipelineBufferDescriptor"
  ; "MTLPipelineBufferDescriptorArray"
  ; "MTLRenderPipelineColorAttachmentDescriptor"
  ; "MTLRenderPipelineColorAttachmentDescriptorArray"
  ]

let selected declaration =
  declaration.classification = "unreviewed"
  &&
  match declaration.owner with
  | Some owner -> List.mem owner owners
  | None -> declaration.kind = "class" && List.mem declaration.name owners

let property_kind declaration =
  if declaration.kind <> "property" then
    invalid_arg ("not a pipeline descriptor property: " ^ declaration.id);
  match declaration.signature with
  | "NSString * _Nullable" -> Copied_string
  | "MTLSize" -> Value_record "MTLSize"
  | "id<MTLFunction> _Nonnull" -> Borrowed_function `Required
  | "id<MTLFunction> _Nullable" -> Borrowed_function `Optional
  | "NSArray<id<MTLBinaryArchive>> * _Nullable" -> Borrowed_binary_archives
  | "NSArray<id<MTLDynamicLibrary>> * _Nonnull" -> Borrowed_dynamic_libraries
  | "MTLLinkedFunctions * _Null_unspecified" -> Linked_functions
  | "MTLPipelineBufferDescriptorArray * _Nonnull" -> Buffer_descriptors
  | ( "MTLRenderPipelineColorAttachmentDescriptorArray * _Nonnull"
    | "MTLTileRenderPipelineColorAttachmentDescriptorArray * _Nonnull" ) ->
      Color_attachments
  | value when String.starts_with ~prefix:"MTL" value -> Enum value
  | value -> invalid_arg ("unsupported pipeline descriptor property: " ^ value)

let mechanically_generated = function
  | Enum _ | Value_record _ | Copied_string -> true
  | Borrowed_function _ | Borrowed_binary_archives
  | Borrowed_dynamic_libraries | Linked_functions | Buffer_descriptors
  | Color_attachments -> false

let inventory_id_digest declarations =
  declarations |> List.map (fun declaration -> declaration.id)
  |> List.sort String.compare |> String.concat "\n" |> Support.sha256
