let fail message=raise(Failure message)
let expect kind=function Error(error:Ogpu.Error.t)when error.kind=kind->()|_->fail"unexpected result"
let run () =
  let d1=Ogpu.Handle.create_device()and d2=Ogpu.Handle.create_device()in
  let h=Ogpu.Handle.create ~device:d1 in
  (match Ogpu.Handle.validate_for ~operation:"test" d1 h with Ok()->()|_->fail"live handle rejected");
  expect Ogpu.Error.Cross_device(Ogpu.Handle.validate_for ~operation:"test" d2 h);
  Ogpu.Handle.destroy h;Ogpu.Handle.destroy h;
  expect Ogpu.Error.Stale_handle(Ogpu.Handle.validate ~operation:"test" h);
  let stale=Ogpu.Handle.create ~device:d1 in Ogpu.Handle.destroy_device d1;Ogpu.Handle.destroy_device d1;
  expect Ogpu.Error.Stale_handle(Ogpu.Handle.validate ~operation:"test" stale);
  let caps=Ogpu.Capabilities.minimum_m1 in
  let profile=match Ogpu.Caps.create caps ~timestamp_queries:false ~sparse_memory:false ~conservative_limits:[] with Ok value->value|Error _->fail"valid caps rejected" in
  if not(Ogpu.Caps.has profile Ogpu.Caps.Buffer) || Ogpu.Caps.has profile Ogpu.Caps.Ray_tracing then fail"baseline feature map";
  expect Ogpu.Error.Unsupported (Ogpu.Caps.require profile Ogpu.Caps.Timestamp_queries);
  let extended={profile with capabilities={caps with ray_tracing=true;metal_fx=true};timestamp_queries=true;sparse_memory=true} in
  List.iter(fun feature->if not(Ogpu.Caps.has extended feature)then fail"optional feature map")Ogpu.Caps.[Ray_tracing;Metal_fx;Timestamp_queries;Sparse_memory];
  expect Ogpu.Error.Unsupported(Ogpu.Caps.require extended(Ogpu.Caps.Unknown"future"));
  let bad_buffers=[0L;Int64.minus_one;Int64.max_int]in
  List.iter(fun size->expect Ogpu.Error.Invalid_argument(Ogpu.Types.validate_buffer caps {label=None;size;usage=[Ogpu.Types.Copy_dst]}))bad_buffers;
  let bad_textures=[(0,1,1,1,1);(1,0,1,1,1);(1,1,0,1,1);(1,1,1,0,1);(1,1,1,1,0);(20000,1,1,1,1)]in
  List.iter(fun(width,height,depth,mip_levels,sample_count)->expect Ogpu.Error.Invalid_argument(Ogpu.Types.validate_texture caps {label=None;width;height;depth;mip_levels;sample_count;usage=[Ogpu.Types.Texture_binding]}))bad_textures;
  print_endline"OGPU handle and descriptor foundation passed"
