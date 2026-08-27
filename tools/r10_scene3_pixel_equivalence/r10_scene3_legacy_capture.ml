open Prismel

let scene () =
  let mesh = Mesh.sphere ~segments:96 ~rings:48 ~radius:1. () in
  let material = Material.create ~diffuse:(Color.hex_exn "#38bdf8")
      ~ambient:(Color.hex_exn "#082f49") ~specular:Color.white ~shininess:42. () in
  let transforms = Array.init 12 (fun index ->
    let angle = float index /. 12. *. Math.two_pi in
    Mat4.mul (Mat4.translation (Vec3.create (cos angle *. 1.9) (sin angle *. 1.2) 0.))
      (Mat4.scaling (Vec3.create 0.38 0.38 0.38))) in
  let value = Scene3.create ~samples:4 ~ambient:(Color.rgb 18 22 30)
      ~lights:[Light.directional ~direction:(Vec3.create (-0.6) (-1.) (-1.4)) ~diffuse:Color.white ()]
      [Scene3.instances_array ~material ~cull:Scene3.Cull_back mesh transforms]
  and camera = Camera.perspective ~at:(Vec3.create 0. 0. 5.4) ~target:Vec3.zero () in
  camera, value

let () =
  let rgba_path,meta_path=match Array.to_list Sys.argv with
    |[_;rgba;meta]->rgba,meta
    |[_;"scene3"]->Sys.getenv"R10_SCENE3_RGBA",Sys.getenv"R10_SCENE3_META"
    |_->invalid_arg"legacy capture: RGBA META"in
  Preview.start ~width:R10_scene3_semantics.width ~height:R10_scene3_semantics.height ();
  let canvas = Canvas.create_exn ~width:R10_scene3_semantics.width ~height:R10_scene3_semantics.height in
  Fun.protect ~finally:(fun () -> Canvas.destroy canvas;Preview.stop()) (fun () ->
    let camera, scene3 = scene () in
    Canvas.render canvas [Scene.clear Color.transparent; Scene.view3d ~camera scene3];
    let colors = Canvas.pixels canvas in
    let rgba = Bytes.create (Array.length colors * 4) in
    Array.iteri (fun index (color : Color.t) -> let offset=index*4 in
      Bytes.set rgba offset (Char.chr color.r);Bytes.set rgba(offset+1)(Char.chr color.g);
      Bytes.set rgba(offset+2)(Char.chr color.b);Bytes.set rgba(offset+3)(Char.chr color.a)) colors;
    R10_scene3_semantics.write rgba_path rgba;
    R10_scene3_semantics.metadata meta_path ~backend:"legacy-sdl2-software" ~rgba)
