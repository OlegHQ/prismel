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
  let check name uniforms expected=let stable=ref None in List.iter(fun _frame->let state={base with transform_uniforms=Some uniforms}in ignore(get(Runtime_next.render_sampled_resources runtime[Scene_execution.Scene3,Ogpu.Pipeline.Replace,None,None,1,{Scene_execution.mesh;state}]));let bytes=get(Runtime_next.read_pixels runtime~bytes_per_row:16)in let actual=Char.code(Bytes.get bytes 0),Char.code(Bytes.get bytes 1),Char.code(Bytes.get bytes 2)in if actual<>expected then failwith(Printf.sprintf"%s pixel"name);let uploaded=(Runtime_next.stats runtime).uploaded_bytes in match!stable with None->stable:=Some uploaded|Some previous when previous=uploaded->()|Some _->failwith(Printf.sprintf"%s reuploaded"name))[1;2;60;600]in
  check"ambient"(uniform~ambient:(1.,0.,0.,1.)~diffuse:(0.,0.,0.,1.)~global:(1.,1.,1.,1.)~light:None)(255,0,0);
  check"directional"(uniform~ambient:(0.,0.,0.,1.)~diffuse:(1.,1.,1.,1.)~global:(0.,0.,0.,1.)~light:(Some([|0.;0.;-1.|],(0.,1.,0.,1.),1.)))(0,255,0);
  get(Runtime_next.destroy runtime);print_endline"runtime_next Scene3 lighting: ambient/directional frames1/2/60/600"
