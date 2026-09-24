type result =
  | Bool
  | Unsigned
  | Enum of string
  | String
  | Retained_object of { objc_type : string; nullable : bool }
  | Retained_array of string

type argument = String_argument

type entry =
  { sdk_id : string
  ; property_id : string option
  ; owner : string
  ; selector : string
  ; arguments : argument list
  ; result : result
  ; macos_introduced : string
  }

let method_id owner selector = "method:-[" ^ owner ^ " " ^ selector ^ "]"
let property_id owner name = Some ("property:" ^ owner ^ ":" ^ name)

let e ?property ?(arguments = []) ?(macos = "10.11") owner selector result =
  { sdk_id = method_id owner selector
  ; property_id = Option.map (fun name -> Option.get (property_id owner name)) property
  ; owner
  ; selector
  ; arguments
  ; result
  ; macos_introduced = macos
  }

let object_ ?(nullable = true) objc_type = Retained_object { objc_type; nullable }

let entries =
  [ e ~property:"access" "MTLArgument" "access" (Enum "MTLBindingAccess")
  ; e ~property:"arrayLength" ~macos:"10.13" "MTLArgument" "arrayLength" Unsigned
  ; e ~property:"bufferAlignment" "MTLArgument" "bufferAlignment" Unsigned
  ; e ~property:"bufferDataSize" "MTLArgument" "bufferDataSize" Unsigned
  ; e ~property:"bufferDataType" "MTLArgument" "bufferDataType" (Enum "MTLDataType")
  ; e ~property:"bufferPointerType" ~macos:"10.13" "MTLArgument" "bufferPointerType" (object_ "MTLPointerType")
  ; e ~property:"bufferStructType" "MTLArgument" "bufferStructType" (object_ "MTLStructType")
  ; e ~property:"index" "MTLArgument" "index" Unsigned
  ; e ~property:"active" "MTLArgument" "isActive" Bool
  ; e ~property:"isDepthTexture" ~macos:"10.12" "MTLArgument" "isDepthTexture" Bool
  ; e ~property:"name" "MTLArgument" "name" String
  ; e ~property:"textureDataType" "MTLArgument" "textureDataType" (Enum "MTLDataType")
  ; e ~property:"textureType" "MTLArgument" "textureType" (Enum "MTLTextureType")
  ; e ~property:"threadgroupMemoryAlignment" "MTLArgument" "threadgroupMemoryAlignment" Unsigned
  ; e ~property:"threadgroupMemoryDataSize" "MTLArgument" "threadgroupMemoryDataSize" Unsigned
  ; e ~property:"type" "MTLArgument" "type" (Enum "MTLArgumentType")
  ; e ~property:"argumentIndexStride" ~macos:"10.13" "MTLArrayType" "argumentIndexStride" Unsigned
  ; e ~property:"arrayLength" "MTLArrayType" "arrayLength" Unsigned
  ; e "MTLArrayType" "elementArrayType" (object_ "MTLArrayType")
  ; e "MTLArrayType" "elementPointerType" ~macos:"10.13" (object_ "MTLPointerType")
  ; e "MTLArrayType" "elementStructType" (object_ "MTLStructType")
  ; e "MTLArrayType" "elementTensorReferenceType" ~macos:"26.0" (object_ "MTLTensorReferenceType")
  ; e "MTLArrayType" "elementTextureReferenceType" ~macos:"10.13" (object_ "MTLTextureReferenceType")
  ; e ~property:"elementType" "MTLArrayType" "elementType" (Enum "MTLDataType")
  ; e ~property:"stride" "MTLArrayType" "stride" Unsigned
  ; e ~property:"bufferPointerType" ~macos:"13.0" "MTLBufferBinding" "bufferPointerType" (object_ "MTLPointerType")
  ; e ~property:"bufferStructType" ~macos:"13.0" "MTLBufferBinding" "bufferStructType" (object_ "MTLStructType")
  ; e ~property:"access" ~macos:"10.13" "MTLPointerType" "access" (Enum "MTLBindingAccess")
  ; e ~property:"alignment" ~macos:"10.13" "MTLPointerType" "alignment" Unsigned
  ; e ~property:"dataSize" ~macos:"10.13" "MTLPointerType" "dataSize" Unsigned
  ; e "MTLPointerType" "elementArrayType" ~macos:"10.13" (object_ "MTLArrayType")
  ; e ~property:"elementIsArgumentBuffer" ~macos:"10.13" "MTLPointerType" "elementIsArgumentBuffer" Bool
  ; e "MTLPointerType" "elementStructType" ~macos:"10.13" (object_ "MTLStructType")
  ; e ~property:"elementType" ~macos:"10.13" "MTLPointerType" "elementType" (Enum "MTLDataType")
  ; e ~property:"argumentIndex" ~macos:"10.13" "MTLStructMember" "argumentIndex" Unsigned
  ; e "MTLStructMember" "arrayType" (object_ "MTLArrayType")
  ; e ~property:"dataType" "MTLStructMember" "dataType" (Enum "MTLDataType")
  ; e ~property:"name" "MTLStructMember" "name" String
  ; e ~property:"offset" "MTLStructMember" "offset" Unsigned
  ; e "MTLStructMember" "pointerType" ~macos:"10.13" (object_ "MTLPointerType")
  ; e "MTLStructMember" "structType" (object_ "MTLStructType")
  ; e "MTLStructMember" "tensorReferenceType" ~macos:"26.0" (object_ "MTLTensorReferenceType")
  ; e "MTLStructMember" "textureReferenceType" ~macos:"10.13" (object_ "MTLTextureReferenceType")
  ; e "MTLStructType" "memberByName:" ~arguments:[ String_argument ] (object_ "MTLStructMember")
  ; e ~property:"members" "MTLStructType" "members" (Retained_array "MTLStructMember")
  ; e ~property:"dimensions" ~macos:"26.0" "MTLTensorBinding" "dimensions" (object_ "MTLTensorExtents")
  ; e ~property:"indexType" ~macos:"26.0" "MTLTensorBinding" "indexType" (Enum "MTLDataType")
  ; e ~property:"tensorDataType" ~macos:"26.0" "MTLTensorBinding" "tensorDataType" (Enum "MTLTensorDataType")
  ; e ~property:"access" ~macos:"26.0" "MTLTensorReferenceType" "access" (Enum "MTLBindingAccess")
  ; e ~property:"dimensions" ~macos:"26.0" "MTLTensorReferenceType" "dimensions" (object_ "MTLTensorExtents")
  ; e ~property:"indexType" ~macos:"26.0" "MTLTensorReferenceType" "indexType" (Enum "MTLDataType")
  ; e ~property:"tensorDataType" ~macos:"26.0" "MTLTensorReferenceType" "tensorDataType" (Enum "MTLTensorDataType")
  ; e ~property:"access" ~macos:"10.13" "MTLTextureReferenceType" "access" (Enum "MTLBindingAccess")
  ; e ~property:"isDepthTexture" ~macos:"10.13" "MTLTextureReferenceType" "isDepthTexture" Bool
  ; e ~property:"textureDataType" ~macos:"10.13" "MTLTextureReferenceType" "textureDataType" (Enum "MTLDataType")
  ; e ~property:"textureType" ~macos:"10.13" "MTLTextureReferenceType" "textureType" (Enum "MTLTextureType")
  ; e ~property:"dataType" ~macos:"10.13" "MTLType" "dataType" (Enum "MTLDataType")
  ]

let expected_method_count = 57
let expected_property_count = 44
let expected_declaration_count = 101
let inventory_ids =
  List.concat_map (fun entry -> entry.sdk_id :: Option.to_list entry.property_id) entries

let source_paths =
  [ "tools/metal/binding_argument_reflection_plan.ml"
  ; "tools/metal/binding_argument_reflection_plan.mli"
  ; "tools/metal/binding_argument_reflection_codegen.ml"
  ; "tools/metal/binding_argument_reflection_codegen.mli"
  ; "tools/metal/binding_argument_reflection_evidence.ml"
  ; "tools/metal/binding_argument_reflection_evidence.mli"
  ]
