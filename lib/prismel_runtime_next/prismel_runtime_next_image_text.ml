open Prismel

module Loop = Prismel_runtime_next_sketch

type image = { handle:Obj.t; identity:int; mutable generation:int64;
  mutable surface:Raster2.Surface.t }
type glyph = { key:int*string; surface:Raster2.Surface.t }
type font = { mutable entries:glyph list }

let get=function Ok value->value|Error _->failwith"image/text execution"
let packed color=Int32.(logor(shift_left(of_int color.Color.r)24)
  (logor(shift_left(of_int color.g)16)(logor(shift_left(of_int color.b)8)
    (of_int color.a))))
let surface ~width ~height color=let value=get(Raster2.Surface.create~width~height())in
  Raster2.Surface.clear value(packed color);value
let create_image ~identity ~width ~height color={handle=Obj.repr(ref identity);
  identity;generation=1L;surface=surface~width~height color}
let successful_reload (value:image) ~width ~height color=
  value.generation<-Int64.succ value.generation;
  value.surface<-surface~width~height color
let failed_reload (value:image)=
  let generation=value.generation and bytes=Bytes.copy(Raster2.Surface.bytes value.surface)in
  if value.generation<>generation||Raster2.Surface.bytes value.surface<>bytes then
    failwith"failed decode replaced prior valid snapshot"
let font ()={entries=[]}
let glyph (value:font) ~density text=
  if text=""then None else match List.find_opt(fun item->item.key=(density,text))value.entries with
  |Some item->Some item.surface
  |None->
      let width=max 1(String.length text)in
      let item={key=(density,text);surface=surface~width~height:1 Color.white}in
      value.entries<-item::value.entries;
      if List.length value.entries>256 then value.entries<-List.rev(List.tl(List.rev value.entries));
      Some item.surface
let execute ~target (image:image) glyph=
  Raster2.Surface.clear target 0x010203ffl;
  get(Raster2.Composite.blit~src:image.surface
    ~src_rect:{x=0;y=0;width=Raster2.Surface.width image.surface;
      height=Raster2.Surface.height image.surface}~dst:target~dst_x:0~dst_y:0
    ~blend:Raster2.Composite.Copy);
  Option.iter(fun source->get(Raster2.Composite.blit~src:source
    ~src_rect:{x=0;y=0;width=Raster2.Surface.width source;height=1}
    ~dst:target~dst_x:0~dst_y:3~blend:Raster2.Composite.Copy))glyph;
  Bytes.copy(Raster2.Surface.bytes target)

let test()=
  let image=create_image~identity:17~width:2~height:2(Color.rgba 17 34 51 255)in
  let stable_handle=image.handle in
  let text=font()and target=get(Raster2.Surface.create~width:8~height:8())in
  let checkpoints=Hashtbl.create 4 and prepared=ref 0 and cleanup=ref[]
  and lru_checked=ref false in
  let vertices=Bytes.make 48 '\000'in let set i x y=
    Bytes.set_int64_le vertices(i*16)(Int64.bits_of_float x);
    Bytes.set_int64_le vertices(i*16+8)(Int64.bits_of_float y)in
  set 0 0. 0.;set 1 8. 0.;set 2 0. 8.;let indices=Bytes.make 12 '\000'in
  Bytes.set_int32_le indices 4 1l;Bytes.set_int32_le indices 8 2l;
  let draw:Scene_execution.draw={mesh={key="image-text";vertices;vertex_count=3;
    indices;index_count=3};state={viewport=(0,0,8,8);scissor=(0,0,8,8);
    cull=Ogpu.Render_pass.Cull_none;depth_compare=Ogpu.Render_pass.Always;
    depth_write=false;depth_load=Ogpu.Render_pass.Clear;depth_clear=1.;
    transform_uniforms=None;stencil_state=None;
    stencil_load=Ogpu.Render_pass.Clear;stencil_clear=0}}in
  let configuration:Loop.configuration={target=Runtime_next_orchestrator.Headless;
    logical_width=4;logical_height=4;drawable_width=8;drawable_height=8;
    frames=600;dt=1./.60.;wap_config=None}in
  let result=Loop.run_state~configuration~init:(fun _->())~update:(fun() _->())
    ~view:(fun()_->[Scene.clear Color.black])~prepare:(fun frame _->
      if frame.Frame.count=2 then failed_reload image;
      if frame.count=60 then begin
        successful_reload image~width:3~height:2(Color.rgba 200 100 50 255)
      end;
      let density=if frame.count<60 then 1 else 2 in
      let before=List.length text.entries in
      if frame.count=2 then begin
        if glyph text~density""<>None||List.length text.entries<>before then
          failwith"empty text mutated cache"
      end;
      let pixels=execute~target image(glyph text~density"AV")in incr prepared;
      let expected_image = if frame.count < 60 then 0x112233ffl else 0xc86432ffl in
      if get(Raster2.Surface.get_rgba target~x:0~y:0)<>expected_image
         ||get(Raster2.Surface.get_rgba target~x:0~y:3)<>0xffffffffl then
        failwith"image/text exact snapshot pixels";
      if frame.count=1 then begin
        for index=0 to 256 do
          ignore(glyph text~density:1(Printf.sprintf"glyph-%03d"index))
        done;
        if List.length text.entries>256 then
          failwith"text LRU exceeded 256";
        lru_checked:=true
      end;
      if List.mem frame.count[1;2;60;600]then Hashtbl.add checkpoints frame.count
        (Digest.to_hex(Digest.bytes pixels));Ok[draw])
    ~after_frame:(fun frame _->if !prepared<>frame.Frame.count then
      failwith"snapshot execution followed parent capture")
    ~on_stop:(fun()->cleanup:="font-release"::!cleanup;
      text.entries<-[];
      cleanup:="image"::!cleanup)()in
  begin match result with Error error->failwith(Ogpu.Error.to_string error)|Ok _->()end;
  if image.handle!=stable_handle||image.identity<>17||image.generation<>2L then
    failwith"watched image identity/generation";
  if not !lru_checked||List.length text.entries>256 then
    failwith"text LRU fixture missing";
  if Hashtbl.find checkpoints 1<>Hashtbl.find checkpoints 2
     ||Hashtbl.find checkpoints 60=Hashtbl.find checkpoints 2
     ||Hashtbl.find checkpoints 600<>Hashtbl.find checkpoints 60 then
    failwith"image/text frame/reload density hashes";
  if !cleanup<>["image";"font-release"]then failwith"offscreen release ordering";
  print_endline"runtime-next image/text: reload/density/LRU/frame600 passed"

let()=match Sys.getenv_opt"PRISMEL_TEST_RUNTIME_NEXT_IMAGE_TEXT"with
  |Some"1"->test()|_->()
