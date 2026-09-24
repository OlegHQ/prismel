let fail message=raise(Failure message)
let ok=function Ok value->value|Error e->fail(Ogpu.Error.to_string e)
let expect kind=function Error(e:Ogpu.Error.t)when e.kind=kind->()|_->fail"unexpected acceleration result"
let ()=
  let d1=Ogpu.Handle.create_device()and d2=Ogpu.Handle.create_device()in let buffer=Ogpu.Handle.create ~device:d1 in
  let range={Ogpu.Acceleration.buffer;buffer_size=4096L;offset=0L;length=1024L}in
  let descriptor=Ogpu.Acceleration.Blas{geometries=[|Triangles{vertices=range;vertex_stride=12;vertex_count=3};Bounding_boxes{boxes=range;stride=24;count=1};Curves{control_points=range;radii=range;control_point_count=4};Motion{keyframes=2;geometry=Triangles{vertices=range;vertex_stride=12;vertex_count=3}}|];allow_refit=true}in
  expect Ogpu.Error.Unsupported(Ogpu.Acceleration.create d1 ~ray_tracing:false descriptor);
  let value=ok(Ogpu.Acceleration.create d1 ~ray_tracing:true descriptor)in expect Ogpu.Error.Invalid_state(Ogpu.Acceleration.refit d1 value);ignore(ok(Ogpu.Acceleration.build d1 value));ignore(ok(Ogpu.Acceleration.refit d1 value));expect Ogpu.Error.Cross_device(Ogpu.Acceleration.compact d2 value);let copy,copy_description=ok(Ogpu.Acceleration.copy d1 value)in ignore copy_description;ignore(ok(Ogpu.Acceleration.compact d1 value));expect Ogpu.Error.Invalid_state(Ogpu.Acceleration.compact d1 value);expect Ogpu.Error.Invalid_state(Ogpu.Acceleration.refit d1 value);Ogpu.Acceleration.destroy copy;expect Ogpu.Error.Stale_handle(Ogpu.Acceleration.build d1 copy);
  let invalid_ranges=[{range with offset=(-1L)};{range with offset=2L};{range with offset=4000L;length=128L}]in List.iter(fun vertices->expect Ogpu.Error.Invalid_argument(Ogpu.Acceleration.create d1 ~ray_tracing:true(Blas{geometries=[|Triangles{vertices;vertex_stride=12;vertex_count=3}|];allow_refit=false})))invalid_ranges;
  expect Ogpu.Error.Invalid_argument(Ogpu.Acceleration.create d1 ~ray_tracing:true(Tlas{instances=range;instance_stride=63;instance_count=1;allow_refit=false}));print_endline"OGPU acceleration lifecycle validation passed"
