open Rays
open Procedural
module Bridge = Sketch_support.Bridge

let get=function Ok value->value|Error _->failwith"terminal normal fixture"

let geometry () =
  let positions=Rdk.Packed.Float3.Private.of_owned_exn
    ~x:[|-0.5;0.5;0.|]~y:[|-0.5;-0.5;0.5|]~z:[|0.;0.;0.|]in
  let builder=Rdk.Topology.Builder.create~point_count:3()in
  Rdk.Topology.Builder.add_triangle builder 0 2 1;
  let topology=Rdk.Topology.Builder.freeze builder in
  let values=Rdk.Packed.Float3.Private.of_owned_exn
    ~x:[|0.;0.;0.|]~y:[|0.;0.;0.|]~z:[|-1.;-1.;-1.|]in
  let normal=get(Rdk.Attribute.create_owned~name:"N"~owner:Rdk.Attribute.Vertex
    (Rdk.Attribute.Float3 values))in
  get(Rdk.Geometry.create~positions~topology~attributes:[normal]())

let snapshot domains = Rays.Parallel.run~domains(fun()->
  let source=geometry()in let node=Sop.snapshot source in
  let instances=Instances.create~transforms:[|Mat4.identity|]node in
  let session=get(Session.create~max_entries:8~max_payload_bytes:1_048_576)in
  let bridge=get(Bridge.create~max_entries:8~max_payload_bytes:1_048_576 session)in
  let context=get(Context.create~domains())in
  let scene,_=get(Bridge.cook_to_scene3 bridge~context instances)in
  let drawing=List.hd(Scene3.Private.drawings(Scene3.create[scene]))in
  let mesh=Mesh.Private.packed_view drawing.mesh in
  let normals=Option.get mesh.normals in
  if normals.z<>[|-1.;-1.;-1.|]then failwith"reversed authored N was overwritten";
  let first_mesh,_,_=get(Bridge.cook_to_instances bridge~context instances)in
  List.iter(fun _frame->let current,_,_=get(Bridge.cook_to_instances bridge~context instances)in
    if current!=first_mesh then failwith"terminal mesh cache reuploaded") [1;2;60;600];
  let stats=Bridge.stats bridge in
  if stats.misses<>1||stats.hits<>5 then failwith"terminal mesh cache accounting";
  let result=(Array.copy mesh.indices,Array.copy normals.x,Array.copy normals.y,
    Array.copy normals.z)in Session.close session;result)

let malformed () =
  let source=geometry()in
  let bad=get(Rdk.Attribute.create_owned~name:"N"~owner:Rdk.Attribute.Vertex
    (Rdk.Attribute.Float2(get(Rdk.Packed.Float2.of_owned~x:[|0.;0.;0.|]
      ~y:[|0.;0.;0.|]))))in
  let source=Rdk.Geometry.without_attribute~owner:Rdk.Attribute.Vertex"N"source in
  let source=get(Rdk.Geometry.with_attribute bad source)in
  let session=get(Session.create~max_entries:8~max_payload_bytes:1_048_576)in
  let bridge=get(Bridge.create~max_entries:8~max_payload_bytes:1_048_576 session)in
  let context=get(Context.create())in
  let instances=Instances.create(Sop.snapshot source)in
  (match Bridge.cook_to_scene3 bridge~context instances with Error _->()|Ok _->
    failwith"malformed terminal N was accepted");
  if(Bridge.stats bridge).retained<>0 then failwith"malformed N mutated mesh cache";
  Session.close session

let run () =
  let one=snapshot 1 and four=snapshot 4 in
  if one<>four then failwith"terminal normal domain drift";
  let workers=Array.init 4(fun _->Domain.spawn(fun()->snapshot 4))in
  Array.iter(fun worker->if Domain.join worker<>one then
    failwith"terminal normal worker drift")workers;
  malformed();
  print_endline"terminal reversed Boolean normals survive packed Scene3 bridge"
