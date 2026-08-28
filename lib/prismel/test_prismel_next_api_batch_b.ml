let require condition message = if not condition then failwith message

let () =
  let open Prismel in
  let linear=Fog3.linear ~color:(Color.gray 128) ~start:2. ~end_:6. in
  require(Fog3.Private.visibility linear ~distance:4.=0.5)"Fog3 linear";
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
  let node=Node3.create ~position:(Vec3.create 2. 0. 0.) () in
  let child=Node3.create ~position:(Vec3.create 0. 1. 0.) ~parent:node () in
  require(Vec3.nearly_equal(Node3.global_position child)(Vec3.create 2. 1. 0.)
    ~eps:1e-12)"Node3 hierarchy";
  for _=1 to 100_000 do
    require(Vec3.nearly_equal(Node3.global_position child)(Vec3.create 2. 1. 0.)
      ~eps:1e-12)"batch B deterministic plateau"
  done;
  print_endline"Prismel_next_api batch B camera/light/mesh facade passed"
