open Ogpu.Transfer_pass
let fail s=raise(Failure s)
let ok=function Ok x->x|Error e->fail(Ogpu.Error.to_string e)
let reject=function Error _->()|Ok _->fail"expected rejection"
let ()=let d=Ogpu.Handle.create_device()and f=Ogpu.Handle.create_device()in
 let bd usage:Ogpu.Types.buffer_descriptor={label=None;size=4096L;usage}and td usage:Ogpu.Types.texture_descriptor={label=None;width=8;height=8;depth=1;mip_levels=2;sample_count=1;usage}in
 let bh=Ogpu.Handle.create~device:d and dh=Ogpu.Handle.create~device:d and th=Ogpu.Handle.create~device:d and th2=Ogpu.Handle.create~device:d in
 let src=buffer~device:d bh(bd[Copy_src])and dst=buffer~device:d dh(bd[Copy_dst])and tex=texture~device:d th(td[Texture_copy_dst;Texture_copy_src])and tex2=texture~device:d th2(td[Texture_copy_dst])in
 let e=create d in ignore(ok(copy_buffer e~src~src_offset:0L~dst~dst_offset:16L~length:32L));ignore(ok(fill_buffer e dst~offset:0L~length:16L~value:7));
 let o={x=0;y=0;z=0}and n={width=8;height=8;depth=1}in ignore(ok(buffer_to_texture e~src~offset:0L~bytes_per_row:256L~bytes_per_image:2048L~dst:tex~mip:0~origin:o~extent:n));ignore(ok(texture_to_buffer e~src:tex~mip:0~origin:o~extent:n~dst~offset:0L~bytes_per_row:256L~bytes_per_image:2048L));ignore(ok(copy_texture e~src:tex~src_mip:0~src_origin:o~dst:tex2~dst_mip:0~dst_origin:o~extent:n));let descriptions=ok(finish e)in if Array.length descriptions<>5 then fail"description order";reject(fill_buffer e dst~offset:0L~length:1L~value:0);
 let bad=create d in reject(copy_buffer bad~src~src_offset:(-1L)~dst~dst_offset:0L~length:1L);reject(buffer_to_texture bad~src~offset:0L~bytes_per_row:4L~bytes_per_image:32L~dst:tex~mip:0~origin:o~extent:n);let foreign=buffer~device:f(Ogpu.Handle.create~device:f)(bd[Copy_src])in reject(copy_buffer bad~src:foreign~src_offset:0L~dst~dst_offset:0L~length:1L);Ogpu.Handle.destroy bh;reject(copy_buffer bad~src~src_offset:0L~dst~dst_offset:0L~length:1L);
 let prepare()=let x=create d in ignore(ok(fill_buffer x dst~offset:0L~length:16L~value:1));ok(finish x)in let expected=prepare()in let ws=Array.init 4(fun _->Domain.spawn prepare)in Array.iter(fun w->if Domain.join w<>expected then fail"domain drift")ws;print_endline"OGPU transfer-pass validation passed"
