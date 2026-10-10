module P=Rays_pathtracer
let rgb=P.Linear_color.rgb
let get=function Ok value->value|Error message->failwith message
let execution=function Ok value->value|Error error->
  failwith(Format.asprintf"%a"Rays_execution.pp_error error)
let live_handles=let _,live=Ogpu.Impl.create_driver()in live

let run () =
  let baseline=live_handles()in
  let cube=get(Result.map_error Rdk.Error.to_string
    (Rdk.Box_generator.box ~size:(Rays.Vec3.create 1. 1. 1.) ()))in
  let scene={ P.objects=[cube,P.material (rgb 0.8 0.6 0.4)]; spheres = []; strands = [];
    environment={sky=rgb 0.6 0.7 0.8;ground=rgb 0.1 0.1 0.1;panels=[]};
    lights=[]}in
  let camera=Rays.Camera.perspective ~fov_y:0.9
    ~at:(Rays.Vec3.create 0. 0. 4.)
    ~target:(Rays.Vec3.create 0. 0. 0.) ()in
  let config={Rays_execution.default_configuration with
    logical_width=48;logical_height=32;drawable_width=48;drawable_height=32;
    title="GPU film test"} in
  let coordinator=execution(Rays_execution.create config)in
  (* A live shared lease keeps the window's device alive. *)
  let lease=execution(Rays_execution.acquire_gpu())in
  assert(Rays_execution.gpu_shared lease);
  assert(Result.is_error(Rays_execution.destroy coordinator));
  Rays_execution.release_gpu lease;
  Fun.protect ~finally:(fun()->execution(Rays_execution.destroy coordinator))
    (fun()->
      let tracer=get(P.create ~width:48 ~height:32 scene)in
      Fun.protect ~finally:(fun()->P.destroy tracer)(fun()->
        get(P.render tracer camera);get(P.flush tracer);
        let image=Rays.Image.Private.resource(P.image tracer)in
        let texture=match Runtime_resources.Image.Private.gpu_snapshot image with
          |Ok(Some(_,_,_,texture))->texture
          |_->failwith"traced film was published through CPU image storage"in
        let direct=match Ogpu.Backend.read_texture texture ~bytes_per_row:(48*4)with
          |Ok bytes->bytes|Error error->failwith(Ogpu.Error.to_string error)in
        let canvas=match Rays.Canvas.create ~width:48 ~height:32 with
          |Ok canvas->canvas|Error error->failwith error in
        Fun.protect ~finally:(fun()->Rays.Canvas.destroy canvas)(fun()->
          Rays.Canvas.render canvas Rays.Scene.[
            image (P.image tracer) ~at:(0,0) ()];
          let colors=Hashtbl.create 16 in
          Array.iter(fun color->Hashtbl.replace colors color.Rays.Color.r ())
            (Rays.Canvas.pixels canvas);
          assert(Hashtbl.length colors>1));
        let colors=Hashtbl.create 16 in
        Bytes.iteri(fun index byte->if index mod 4=0 then Hashtbl.replace colors byte())direct;
        assert(Hashtbl.length colors>1);
        let textures=Hashtbl.create 2 in
        Hashtbl.add textures (Ogpu.Backend.texture_id texture) ();
        for _=1 to 30 do
          get(P.render tracer camera);get(P.flush tracer);
          match Runtime_resources.Image.Private.gpu_snapshot image with
          |Ok(Some(_,_,_,texture))->Hashtbl.replace textures
              (Ogpu.Backend.texture_id texture)()
          |_->failwith"GPU film reverted to CPU storage"
        done;
        assert(Hashtbl.length textures=3)));
  let after=live_handles()in
  assert(after=baseline);
  print_endline"GPU film: direct texture, explicit readback, zero live delta"
