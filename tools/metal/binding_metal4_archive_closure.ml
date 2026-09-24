let archive_ids =
  [ "method:-[MTL4Archive newComputePipelineStateWithDescriptor:error:]"
  ; "method:-[MTL4Archive newComputePipelineStateWithDescriptor:dynamicLinkingDescriptor:error:]"
  ; "method:-[MTL4Archive newRenderPipelineStateWithDescriptor:error:]"
  ; "method:-[MTL4Archive newRenderPipelineStateWithDescriptor:dynamicLinkingDescriptor:error:]"
  ]

let pre_archive_callable_count = 147
let authoritative_ownership_count = 151

let validate ~authoritative_ids ~pre_archive_callable_ids =
  let unique xs = List.sort_uniq String.compare xs in
  let archive = unique archive_ids in
  let before = unique pre_archive_callable_ids in
  let authoritative = unique authoritative_ids in
  if List.length archive <> 4 || List.length before <> pre_archive_callable_count
  then failwith "Metal4 pre-archive callable-set drift";
  if List.exists (fun id -> List.mem id before) archive
  then failwith "Metal4 archive closure overlaps pre-archive callable set";
  let after = unique (archive @ before) in
  if List.length after <> authoritative_ownership_count || after <> authoritative
  then failwith "Metal4 callable set does not equal authoritative 151-ID set"
