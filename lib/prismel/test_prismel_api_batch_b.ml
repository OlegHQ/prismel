let require condition message = if not condition then failwith message

let run () =
  let open Prismel in
  let material=Material.matte(Color.rgb 10 20 30) in
  require(material.diffuse=Color.rgb 10 20 30)"Material matte";
  let light=Light.spot ~at:(Vec3.create 1. 2. 3.)
      ~direction:(Vec3.create 0. 0. (-1.)) ~cutoff:0.5 ~concentration:4. () in
  require(light.intensity=1.)"Light intensity";
  let box=Mesh.box ~width:2. ~height:3. ~depth:4. () in
  require(Mesh.vertex_count box=24&&Mesh.index_count box=36)"Mesh box";
  let camera=Camera.perspective ~at:(Vec3.create 0. 0. 5.)
      ~target:Vec3.zero () in
  require(Option.is_some(Camera.world_to_screen ~viewport:(0,0,64,64)
    camera Vec3.zero))"Camera projection";
  let easy=Easy_camera.create ~target:Vec3.zero ~distance:5. () in
  require(Easy_camera.distance easy=5.)"Easy_camera distance";
  print_endline"Prismel batch B camera/light/mesh API passed"
