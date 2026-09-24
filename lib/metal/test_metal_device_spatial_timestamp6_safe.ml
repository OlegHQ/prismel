open Metal
let fail message=raise(Failure message)
let get=function Ok value->value|Error error->fail error.message
let expect_invalid=function Error{kind=Invalid_argument;_}->()|_->fail"expected invalid argument"
let ()=
  let device=get(Device.system_default())in
  expect_invalid(Device.default_sample_positions device ~count:0);
  let positions=get(Device.default_sample_positions device ~count:1)in
  if Array.length positions<>1 then fail"sample-position cardinality changed";
  Array.iter(fun(x,y)->if not(Float.is_finite x&&Float.is_finite y)then fail"non-finite sample position")positions;
  let cpu,gpu=get(Device.sample_timestamps device)in if cpu<0L||gpu<0L then fail"negative timestamp";
  let region:Device.sparse_region={x=0L;y=0L;z=0L;width=4L;height=4L;depth=1L}in
  let tiles=get(Device.sparse_pixel_regions_to_tiles device ~tile_size:(4L,4L,1L)~alignment:Device.Outward[|region|])in
  if Array.length tiles<>1 then fail"sparse conversion cardinality changed";
  let pixels=get(Device.sparse_tile_regions_to_pixels device ~tile_size:(4L,4L,1L)tiles)in
  if Array.length pixels<>1 then fail"reverse sparse conversion cardinality changed";
  (match Device.timestamp_frequency device with Ok n when n>0L->()|Error{kind=Unsupported;_}->()|_->fail"timestamp frequency contract");
  (match Device.counter_heap_entry_size device with Ok n when n>0L->()|Error{kind=Unsupported;_}->()|_->fail"counter entry-size contract");
  get(Device.destroy device);print_endline"Metal Device spatial/timestamp exact-six safe fixture passed"
