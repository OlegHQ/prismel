open Binding_indirect_command14_safe_contract

let require condition message = if not condition then failwith message

let () =
  validate ();
  require (validate_binding {index=30;offset=8L;length=8L;stride=Some 4L})
    "valid binding rejected";
  require (not (validate_binding {index=31;offset=0L;length=8L;stride=None}))
    "binding index accepted";
  require (not (validate_binding {index=0;offset=9L;length=8L;stride=None}))
    "binding range accepted";
  require (not (validate_binding {index=0;offset=0L;length=8L;stride=Some 0L}))
    "zero stride accepted";
  let indexed = {index_count=3L;index_size=2L;index_offset=2L;
    buffer_length=8L;instance_count=1L;base_instance=0L} in
  require (validate_indexed indexed) "valid indexed draw rejected";
  require (not (validate_indexed {indexed with index_count=Int64.max_int}))
    "overflowing indexed draw accepted";
  require (not (validate_indexed {indexed with index_offset=1L}))
    "misaligned index offset accepted";
  let patch = {control_points=3L;patch_start=0L;patch_count=1L;
    instance_count=1L;base_instance=0L;patch_index_offset=0L;
    patch_index_length=8L;tessellation_offset=0L;
    tessellation_length=16L;tessellation_stride=0L} in
  require (validate_patch ~capability:Tessellation patch)
    "valid patch draw rejected";
  require (not (validate_patch ~capability:Conventional patch))
    "patch draw escaped capability gate";
  require (validate_mesh_binding ~capability:Mesh
    {index=0;offset=0L;length=8L;stride=None})
    "valid mesh binding rejected";
  require (not (validate_mesh_binding ~capability:Conventional
    {index=0;offset=0L;length=8L;stride=None}))
    "mesh binding escaped capability gate";
  print_endline "IndirectCommand14 pending7 safe contracts: ok"
