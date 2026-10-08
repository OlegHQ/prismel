module B=Ogpu.Backend
module C=Rays_execution.Private.Gpu_circles
let get=function Ok value->value|Error error->failwith(Format.asprintf"%a"Rays_execution.pp_error error)
let native_get=function Ok value->value|Error error->failwith(Ogpu.Error.to_string error)
let ir commands=match Scene_command.Render_ir.create(Array.of_list commands)with
  |Ok value->value|Error _->failwith"GPU drawing IR rejected"
let render execution commands=
  let draws=get(Rays_execution.lower_scene2 execution~density:1~resource:(fun _->None)(ir commands))in
  get(Rays_execution.step~clear:(0.25,0.5,0.75,1.)execution draws);
  get(Rays_execution.capture execution)
let ()=
  List.iter(fun density->
    let execution=get(Rays_execution.create_offscreen{Rays_execution.
      logical_width=32;logical_height=24;drawable_width=32*density;drawable_height=24*density;
      title="GPU drawing parity";vsync=false})in
    let gpu=get(Rays_execution.acquire_gpu())in
    let sink=get(Rays_execution.Private.create_gpu_circles gpu)in
    let positions=native_get(B.create_buffer(Rays_execution.gpu_device gpu)
      {label=Some"GPU parity points";size=24L;usage=[Storage;Copy_dst]})in
    Fun.protect~finally:(fun()->Rays_execution.Private.close_gpu_circles sink;
      ignore(B.destroy_buffer positions);Rays_execution.release_gpu gpu;
      ignore(get(Rays_execution.destroy execution)))(fun()->
      let points=[|8.;8.;0.;20.;14.;0.|]and bytes=Bytes.create 24 in
      Array.iteri(fun index value->Bytes.set_int32_le bytes(index*4)(Int32.bits_of_float value))points;
      native_get(B.write_buffer positions~offset:0L bytes);
      let generation=ref 1 in
      let source stamp()=if !generation=stamp then Some positions else None in
      let conversion=native_get(C.create~device:(Rays_execution.gpu_device gpu)
        ~queue:(Rays_execution.gpu_queue gpu))in
      Fun.protect~finally:(fun()->C.close conversion)(fun()->
        let converted=native_get(C.dispatch conversion~source:positions~count:2~radius:2.5
          ~fill:0x12345678l~stroke:0xff00ff80l~stroke_width:3.)in
        let expected=Scene_command.Shape_batch.Builder.create()in
        for index=0 to 1 do Scene_command.Shape_batch.Builder.circle expected
          ~x:points.(index*3)~y:points.(index*3+1)~radius:2.5
          ~fill:0x12345678l~stroke:0xff00ff80l~stroke_width:3.()done;
        assert(native_get(B.read_buffer converted~offset:0L~length:128)=
          Scene_command.Shape_batch.instances(Scene_command.Shape_batch.Builder.publish expected));
        List.iter(fun(x,radius)->
          let bad=Bytes.copy bytes in Bytes.set_int32_le bad 0(Int32.bits_of_float x);
          native_get(B.write_buffer positions~offset:0L bad);
          match C.dispatch conversion~source:positions~count:2~radius
            ~fill:(-1l)~stroke:0l~stroke_width:0. with
          |Error{Ogpu.Error.kind=Invalid_argument;_}->()
          |_->failwith"GPU circles accepted nonfinite coordinates or bounds")
          [infinity,1.;3.0e38,3.0e38];
        native_get(B.write_buffer positions~offset:0L bytes));
      List.iter(fun(fill,stroke,stroke_width)->
        let token=get(Rays_execution.Private.gpu_circles sink~source:(source !generation)
          ~count:2~radius:2.5~fill~stroke~stroke_width)in
        let cpu=Scene_command.Shape_batch.Builder.create()in
        for index=0 to 1 do Scene_command.Shape_batch.Builder.circle cpu
          ~x:points.(index*3)~y:points.(index*3+1)~radius:2.5~fill~stroke~stroke_width()done;
        let cpu=Scene_command.Shape_batch.Builder.publish cpu in
        let gpu=Scene_command.Shape_batch.Private.of_gpu token in
        let transform:Scene_command.Render_ir.transform={xx=1.25;xy=0.25;yx= -0.25;yy=0.75;tx=1.;ty=2.}in
        let prefix mode=[Scene_command.Render_ir.Set_blend mode;Push_transform transform;
          Push_clip{x=3.;y=2.;width=26.;height=18.}]in
        List.iter(fun mode->
          let commands shapes=prefix mode@[Shapes shapes;Pop_clip;Pop_transform]in
          assert(render execution(commands cpu)=render execution(commands gpu)))
          [Scene_command.Render_ir.Replace;Alpha;Add;Multiply;Screen;Subtract])
        [-1l,0l,1.;0x12345678l,0xff00ff80l,3.;0l,0l,0.];
      let old=get(Rays_execution.Private.gpu_circles sink~source:(source !generation)
        ~count:2~radius:2.5~fill:(-1l)~stroke:0l~stroke_width:1.)in
      let old_ir=ir[Shapes(Scene_command.Shape_batch.Private.of_gpu old)]in
      let old_draws=get(Rays_execution.lower_scene2 execution~density
        ~resource:(fun _->None)old_ir)in
      get(Rays_execution.step execution old_draws);
      incr generation;
      assert(Result.is_error(Rays_execution.step execution old_draws));
      let fresh=get(Rays_execution.Private.gpu_circles sink~source:(source !generation)
        ~count:2~radius:2.5~fill:(-1l)~stroke:0l~stroke_width:1.)in
      assert(Scene_command.Shape_batch.Private.gpu_stamp old<Scene_command.Shape_batch.Private.gpu_stamp fresh);
      Rays_execution.release_gpu gpu;
      assert(Result.is_error(Rays_execution.step execution old_draws));
      assert(Scene_execution.Private.gpu_vertex_count_for_test()=0)))
    [1;2];
  print_endline"GPU circles: exact native parity under transform, clip, six blends, Retina and stale output/lease guards"
