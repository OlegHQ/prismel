let get=function Ok value->value|Error error->failwith(Ogpu.Error.to_string error)
let uniform ~ambient ~diffuse ~global ~light =
  let values=Array.make 1364 0. in
  for matrix=0 to 2 do for diagonal=0 to 3 do values.(matrix*16+diagonal*5)<-1. done done;values.(50)<-1.;
  let color offset(r,g,b,a)=values.(offset)<-r;values.(offset+1)<-g;values.(offset+2)<-b;values.(offset+3)<-a in
  color 52 ambient;color 56 diffuse;color 60(0.,0.,0.,1.);color 64(0.,0.,0.,1.);values.(68)<-16.;color 69 global;
  (match light with None->()|Some(direction,color_value,intensity)->values.(73)<-1.;values.(85)<-direction.(0);values.(86)<-direction.(1);values.(87)<-direction.(2);color 88 color_value;values.(92)<-intensity);
  let bytes=Bytes.create 5456 in Array.iteri(fun index value->Bytes.set_int32_le bytes(index*4)(Int32.bits_of_float value))values;bytes
let ()=match Runtime_next.create~width:4~height:4 with Error _->print_endline"runtime_next Scene3 lighting: skipped"|Ok runtime->
  let indices=Bytes.make 12 '\000'and vertices=Bytes.make(68*3)'\000'in Bytes.set_int32_le indices 4 1l;Bytes.set_int32_le indices 8 2l;
  List.iteri(fun index(x,y)->let offset=index*68 in Bytes.set_int64_le vertices offset(Int64.bits_of_float x);Bytes.set_int64_le vertices(offset+8)(Int64.bits_of_float y);Bytes.set_int64_le vertices(offset+40)(Int64.bits_of_float 1.);Bytes.set_int32_le vertices(offset+48)0xffffffffl)[-1.,-1.;3.,-1.;-1.,3.];
  let mesh:Scene_execution.mesh={key="runtime-scene3-light";vertices;vertex_count=3;indices;index_count=3}in
  let base:Scene_execution.state={viewport=(0,0,4,4);scissor=(0,0,4,4);cull=Ogpu.Render_pass.Cull_none;depth_compare=Ogpu.Render_pass.Always;depth_write=false;depth_load=Ogpu.Render_pass.Clear;depth_clear=1.;transform_uniforms=None}in
  let check name uniforms expected=let stable=ref None in List.iter(fun _frame->let state={base with transform_uniforms=Some uniforms}in ignore(get(Runtime_next.render_sampled_resources runtime[Scene_execution.Scene3,Ogpu.Pipeline.Replace,None,None,1,{Scene_execution.mesh;state}]));let bytes=get(Runtime_next.read_pixels runtime~bytes_per_row:16)in let actual=Char.code(Bytes.get bytes 0),Char.code(Bytes.get bytes 1),Char.code(Bytes.get bytes 2)in if actual<>expected then(let r,g,b=actual in failwith(Printf.sprintf"%s pixel %d,%d,%d"name r g b));let uploaded=(Runtime_next.stats runtime).uploaded_bytes in match!stable with None->stable:=Some uploaded|Some previous when previous=uploaded->()|Some _->failwith(Printf.sprintf"%s reuploaded"name))[1;2;60;600]in
  check"ambient"(uniform~ambient:(1.,0.,0.,1.)~diffuse:(0.,0.,0.,1.)~global:(1.,1.,1.,1.)~light:None)(255,0,0);
  check"directional"(uniform~ambient:(0.,0.,0.,1.)~diffuse:(1.,1.,1.,1.)~global:(0.,0.,0.,1.)~light:(Some([|0.;0.;-1.|],(0.,1.,0.,1.),1.)))(0,255,0);
  let set bytes index value=Bytes.set_int32_le bytes(index*4)(Int32.bits_of_float value)in
  let positional kind color=let bytes=uniform~ambient:(0.,0.,0.,1.)~diffuse:(1.,1.,1.,1.)~global:(0.,0.,0.,1.)~light:(Some([|0.;0.;-1.|],color,1.))in set bytes 84 kind;set bytes 85 0.;set bytes 86 0.;set bytes 87 1.;bytes in
  let point=positional 1.(1.,0.,0.,1.)in set point 93 1.;check"point"point(175,0,0);
  let spot=positional 2.(0.,0.,1.,1.)in set spot 93 0.;set spot 94 0.;set spot 95(-1.);set spot 96 1.;set spot 97 0.5;set spot 98 1.;set spot 99 1.;check"spot"spot(0,0,120);
  let area=positional 3.(1.,0.,0.,1.)in set area 93 0.;set area 94 0.;set area 95(-1.);set area 96 1.;set area 97 1.;set area 98 4.;set area 99 1.;check"area"area(123,0,0);
  let fog kind=let bytes=uniform~ambient:(1.,1.,1.,1.)~diffuse:(0.,0.,0.,1.)~global:(1.,1.,1.,1.)~light:None in set bytes 76 kind;set bytes 77 1.;set bytes 78 0.;set bytes 79 0.;set bytes 80 1.;bytes in
  let linear=fog 1. in set linear 81 0.;set linear 82 1.;check"linear-fog"linear(255,0,0);
  let exponential=fog 2. in set exponential 81 100.;check"exponential-fog"exponential(255,0,0);
  let exponential2=fog 3. in set exponential2 81 100.;check"exponential2-fog"exponential2(255,0,0);
  let too_many=Bytes.copy exponential2 in set too_many 73 65.;let uploaded=(Runtime_next.stats runtime).uploaded_bytes in
  begin match Runtime_next.render_sampled_resources runtime[Scene_execution.Scene3,Ogpu.Pipeline.Replace,None,None,1,{Scene_execution.mesh;state={base with transform_uniforms=Some too_many}}]with Error error when error.Ogpu.Error.kind=Invalid_argument&&uploaded=(Runtime_next.stats runtime).uploaded_bytes->()|_->failwith"over-64 light block was not rejected atomically"end;
  get(Runtime_next.destroy runtime);print_endline"runtime_next Scene3 lighting: ambient/directional frames1/2/60/600"
