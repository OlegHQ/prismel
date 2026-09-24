let ok=function Ok x->x|Error e->failwith e
let error=function Error _->()|Ok _->failwith"expected ComputePass rejection"
let ()=let open Binding_compute_pass_safe_package in validate_handoff();
 let capability={concurrent_dispatch=true;max_attachments=2}and buffer={token=1;device=7;sample_count=4;destroyed=false}in
 let attachment={buffer=Some buffer;start_index=1;end_index=3}in
 let input=[|Some attachment;None|]in let descriptor=ok(create_descriptor~capability~device:7~dispatch:Concurrent~attachments:input)in input.(0)<-None;if descriptor.attachments.(0)=None then failwith"pass graph not snapshotted";
 error(create_descriptor~capability:{capability with concurrent_dispatch=false}~device:7~dispatch:Concurrent~attachments:[||]);
 error(validate_attachment~device:7{attachment with start_index=3;end_index=2});error(validate_attachment~device:7{attachment with end_index=4});error(validate_attachment~device:7{attachment with buffer=Some{buffer with device=8}});error(validate_attachment~device:7{attachment with buffer=Some{buffer with destroyed=true}});
 ignore(ok(validate_attachment~device:7{buffer=None;start_index=dont_sample;end_index=dont_sample}));error(validate_attachment~device:7{buffer=None;start_index=0;end_index=0});
 let next=ok(replace_attachment descriptor~index:1(Some attachment))in if descriptor.attachments.(1)<>None||List.length(retained_buffers next)<>2 then failwith"attachment replacement/retention";error(replace_attachment descriptor~index:2 None);
 Printf.printf"ComputePass safe package: callable17 dispatch3/sample-index6/pass2/sample-buffer4/array2 capability/order/device/bounds/retention passed\n%!"
