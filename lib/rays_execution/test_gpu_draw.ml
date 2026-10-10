module B=Ogpu.Backend
module C=Rays_execution.Private.Gpu_circles
let get=function Ok value->value|Error error->failwith(Format.asprintf"%a"Rays_execution.pp_error error)
let native_get=function Ok value->value|Error error->failwith(Ogpu.Error.to_string error)
let ()=
  List.iter(fun density->
    let execution=get(Rays_execution.create_offscreen{Rays_execution.
      logical_width=32;logical_height=24;drawable_width=32*density;drawable_height=24*density;
      title="GPU drawing parity";vsync=false;high_density=true})in
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
        List.iter(fun(x,_radius)->
          let bad=Bytes.copy bytes in Bytes.set_int32_le bad 0(Int32.bits_of_float x);
          native_get(B.write_buffer positions~offset:0L bad))
          [infinity,1.;3.0e38,3.0e38];
        native_get(B.write_buffer positions~offset:0L bytes));
      let old=get(Rays_execution.Private.gpu_circles sink~source:(source !generation)
        ~count:2~radius:2.5~fill:(-1l)~stroke:0l~stroke_width:1.)in
      incr generation;
      let fresh=get(Rays_execution.Private.gpu_circles sink~source:(source !generation)
        ~count:2~radius:2.5~fill:(-1l)~stroke:0l~stroke_width:1.)in
      assert(Scene_command.Shape_batch.Private.gpu_stamp old<Scene_command.Shape_batch.Private.gpu_stamp fresh);
      Rays_execution.release_gpu gpu;
      assert(Scene_execution.Private.gpu_vertex_count_for_test()=0)))
    [1;2];
  print_endline"GPU circles: exact native parity under transform, clip, six blends, Retina and stale output/lease guards"
