let require condition message = if not condition then failwith message

let () =
  let open Prismel_next_api in
  let linear=Fog3.linear ~color:(Color.gray 128) ~start:2. ~end_:6. in
  require(Fog3.Private.visibility linear ~distance:4.=0.5)"Fog3 linear";
  let material=Material.matte(Color.rgb 10 20 30) in
  require(material.diffuse=Color.rgb 10 20 30)"Material matte";
  let light=Light.spot ~at:(Vec3.create 1. 2. 3.)
      ~direction:(Vec3.create 0. 0. (-1.)) ~cutoff:0.5 ~concentration:4. () in
  require(light.intensity=1.)"Light intensity";
  let node=Node3.create ~position:(Vec3.create 2. 0. 0.) () in
  let child=Node3.create ~position:(Vec3.create 0. 1. 0.) ~parent:node () in
  require(Vec3.nearly_equal(Node3.global_position child)(Vec3.create 2. 1. 0.)
    ~eps:1e-12)"Node3 hierarchy";
  for _=1 to 100_000 do
    require(Vec3.nearly_equal(Node3.global_position child)(Vec3.create 2. 1. 0.)
      ~eps:1e-12)"batch B deterministic plateau"
  done;
  print_endline"Prismel_next_api batch B light/material/node facade passed"
