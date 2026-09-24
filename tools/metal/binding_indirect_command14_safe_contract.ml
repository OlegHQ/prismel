type capability = Conventional | Tessellation | Mesh

type binding =
  { index : int
  ; offset : int64
  ; length : int64
  ; stride : int64 option }

type indexed_draw =
  { index_count : int64
  ; index_size : int64
  ; index_offset : int64
  ; buffer_length : int64
  ; instance_count : int64
  ; base_instance : int64 }

type patch_draw =
  { control_points : int64
  ; patch_start : int64
  ; patch_count : int64
  ; instance_count : int64
  ; base_instance : int64
  ; patch_index_offset : int64
  ; patch_index_length : int64
  ; tessellation_offset : int64
  ; tessellation_length : int64
  ; tessellation_stride : int64 }

let checked_span ~offset ~count ~element_size ~length =
  offset >= 0L && count >= 0L && element_size > 0L && offset <= length &&
  count <= Int64.div (Int64.sub length offset) element_size

let validate_binding {index;offset;length;stride} =
  index >= 0 && index < 31 && offset >= 0L && offset <= length &&
  match stride with None -> true | Some value -> value > 0L

let validate_indexed value =
  value.index_count > 0L && value.instance_count > 0L &&
  value.base_instance >= 0L &&
  (value.index_size = 2L || value.index_size = 4L) &&
  Int64.rem value.index_offset value.index_size = 0L &&
  checked_span ~offset:value.index_offset ~count:value.index_count
    ~element_size:value.index_size ~length:value.buffer_length

let validate_patch ~capability value =
  capability = Tessellation && value.control_points > 0L &&
  value.patch_start >= 0L && value.patch_count > 0L &&
  value.instance_count > 0L && value.base_instance >= 0L &&
  value.patch_index_offset >= 0L &&
  value.patch_index_offset <= value.patch_index_length &&
  value.tessellation_offset >= 0L &&
  value.tessellation_offset <= value.tessellation_length &&
  value.tessellation_stride >= 0L

let validate_mesh_binding ~capability binding =
  capability = Mesh && validate_binding binding

let pending_operations =
  [ "compute_buffer_stride"; "mesh_buffer"; "object_buffer"
  ; "vertex_buffer_stride"; "indexed_draw"; "patch_draw"
  ; "indexed_patch_draw" ]

let validate () =
  if List.length pending_operations <> 7 ||
     List.length (List.sort_uniq String.compare pending_operations) <> 7 then
    invalid_arg "IndirectCommand14 pending contract drift"
