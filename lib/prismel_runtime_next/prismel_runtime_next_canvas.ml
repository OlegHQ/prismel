open Prismel

module Loop = Prismel_runtime_next_sketch

type t = { mutable surface : Raster2.Surface.t; mutable dead : bool }

let get = function Ok value -> value | Error _ -> failwith "Canvas execution"

let create ~width ~height =
  Result.map (fun surface -> { surface; dead = false })
    (Raster2.Surface.create ~width ~height ())

let resize value ~width ~height =
  if value.dead then Error `Destroyed
  else
    match Raster2.Surface.create ~width ~height () with
    | Error _ -> Error `Invalid_size
    | Ok replacement -> value.surface <- replacement; Ok ()

let render_nested value =
  if value.dead then Error `Destroyed
  else
    let child = get (Raster2.Surface.create ~width:2 ~height:2 ()) in
    Raster2.Surface.clear child 0x112233ffl;
    get (Raster2.Surface.set_rgba child ~x:1 ~y:1 0xaabbcc80l);
    let intermediate = get (Raster2.Surface.create ~width:3 ~height:3 ()) in
    Raster2.Surface.clear intermediate 0x00000000l;
    get (Raster2.Composite.blit ~src:child
      ~src_rect:{x=0;y=0;width=2;height=2} ~dst:intermediate ~dst_x:1 ~dst_y:1
      ~blend:Raster2.Composite.Copy);
    Raster2.Surface.clear value.surface 0x010203ffl;
    get (Raster2.Composite.blit ~src:intermediate
      ~src_rect:{x=0;y=0;width=3;height=3} ~dst:value.surface ~dst_x:0 ~dst_y:0
      ~blend:Raster2.Composite.Source_over);
    Ok (Bytes.copy (Raster2.Surface.bytes value.surface))

let destroy value = value.dead <- true

let test () =
  let canvas = get (create ~width:4 ~height:4) in
  let prepared_before_parent = ref 0 and stop_order = ref []
  and hashes = Hashtbl.create 4 in
  let vertices=Bytes.make 48 '\000'in
  let set i x y=Bytes.set_int64_le vertices(i*16)(Int64.bits_of_float x);
    Bytes.set_int64_le vertices(i*16+8)(Int64.bits_of_float y)in
  set 0 0. 0.;set 1 4. 0.;set 2 0. 4.;
  let indices=Bytes.make 12 '\000'in Bytes.set_int32_le indices 4 1l;
  Bytes.set_int32_le indices 8 2l;
  let draw:Scene_execution.draw={mesh={key="canvas-parent";vertices;
    vertex_count=3;indices;index_count=3};state={viewport=(0,0,4,4);
    scissor=(0,0,4,4);cull=Ogpu.Render_pass.Cull_none;
    depth_compare=Ogpu.Render_pass.Always;depth_write=false;
    depth_load=Ogpu.Render_pass.Clear;depth_clear=1.;transform_uniforms=None;
    stencil_state=None;stencil_load=Ogpu.Render_pass.Clear;stencil_clear=0}}in
  let configuration:Loop.configuration={target=Runtime_next_orchestrator.Headless;
    logical_width=4;logical_height=4;drawable_width=4;drawable_height=4;
    frames=600;dt=1./.60.;web_configuration=None}in
  let result=Loop.run_state~configuration~init:(fun _->())
    ~update:(fun() _->())~view:(fun() _->[Scene.clear Color.black])
    ~prepare:(fun frame _->
      if frame.Frame.count=60 then get(resize canvas~width:8~height:8);
      let pixels=get(render_nested canvas)in
      incr prepared_before_parent;
      if get (Raster2.Surface.get_rgba canvas.surface ~x:1 ~y:1)
           <> 0x112233ffl
         || get (Raster2.Surface.get_rgba canvas.surface ~x:0 ~y:0)
            <> 0x010203ffl then
        failwith "nested Canvas exact texture pixels drift";
      if List.mem frame.count[1;2;60;600]then
        Hashtbl.add hashes frame.count(Digest.to_hex(Digest.bytes pixels));
      Ok[draw])
    ~after_frame:(fun frame _->
      if !prepared_before_parent<>frame.Frame.count then
        failwith"Canvas dependency executed after parent capture")
    ~on_stop:(fun()->destroy canvas;stop_order:="canvas"::!stop_order)()in
  begin match result with Error e->failwith(Ogpu.Error.to_string e)|Ok _->()end;
  let initial=Hashtbl.find hashes 1 in
  if Hashtbl.find hashes 2 <> initial || Hashtbl.find hashes 60 = initial
     || Hashtbl.find hashes 600 <> Hashtbl.find hashes 60 then
    failwith "nested Canvas frame/resize hash drift";
  if !prepared_before_parent <> 600 || !stop_order <> [ "canvas" ]
     || not canvas.dead then
    failwith "Canvas teardown-before-target evidence drift";
  begin
    match render_nested canvas with
    | Error `Destroyed -> ()
    | _ -> failwith "destroyed Canvas executed"
  end;
  print_endline
    "runtime-next Canvas: nested pixels/resize/frame600 ordering passed"

let () =
  match Sys.getenv_opt "PRISMEL_TEST_RUNTIME_NEXT_CANVAS" with
  | Some "1" -> test ()
  | _ -> ()
