let ok=function Ok x->x|Error e->failwith e
let error=function Error _->()|Ok _->failwith"expected Blit rejection"
let ()=let open Binding_blit_command_safe_package in validate_handoff();
 let buffer={token=1;device=7;kind=Buffer;length=256;destroyed=false}and texture={token=2;device=7;kind=Texture;length=0;destroyed=false}in
 ignore(ok(validate_pair~device:7~source_kind:Buffer~destination_kind:Texture buffer texture));error(validate_pair~device:7~source_kind:Buffer~destination_kind:Texture{buffer with device=8}texture);
 ignore(ok(validate_texture_layout~extent:{width=4;height=4;depth=2}~bytes_per_pixel:4~bytes_per_row:16~bytes_per_image:64~buffer~offset:0));error(validate_texture_layout~extent:{width=4;height=4;depth=2}~bytes_per_pixel:4~bytes_per_row:15~bytes_per_image:64~buffer~offset:0);
 let tensor={buffer with kind=Tensor}in ignore(ok(validate_tensor_copy~device:7 tensor tensor~source_origin:[|0L;0L|]~source_dimensions:[|2L;2L|]~destination_origin:[|0L;0L|]~destination_dimensions:[|2L;2L|]));error(validate_tensor_copy~device:7 tensor tensor~source_origin:[|0L|]~source_dimensions:[|2L;2L|]~destination_origin:[|0L|]~destination_dimensions:[|2L|]);
 error(validate_sync{managed_sync=false;access_counters=true}texture);ignore(ok(validate_sync{managed_sync=true;access_counters=true}texture));
 let counter={buffer with kind=Counter_buffer}in ignore(ok(validate_counter{managed_sync=true;access_counters=true}counter{offset=0;length=16}));error(validate_counter{managed_sync=true;access_counters=false}counter{offset=0;length=16});
 let inputs=[|buffer;texture|]in let held=retain inputs in inputs.(0)<-{buffer with destroyed=true};if held.(0).destroyed then failwith"completion resources not snapshotted";
 error(validate_resource~device:7~kind:Fence{buffer with kind=Fence;destroyed=true});
 Printf.printf"BlitCommand safe package: exact25 copy9/fill2/access2/optimize5/reset1/counter2/sync2/fence2 validation and retention passed\n%!"
