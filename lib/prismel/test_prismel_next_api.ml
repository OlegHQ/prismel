let () =
  let open Prismel_next_api in
  let a=Vec2.create 3. 4. in
  if Vec2.length a <> 5. || Vec2.to_pair (Vec2.rotate Vec2.unit_x
      (Float.pi/.2.)) <> (0,1) then failwith "Vec2 parity";
  let normal=Vec3.cross Vec3.unit_x Vec3.unit_y in
  if not(Vec3.nearly_equal normal Vec3.unit_z ~eps:1e-12) then
    failwith "Vec3 parity";
  for _=1 to 100_000 do
    if Vec3.to_triple (Vec3.lerp Vec3.zero Vec3.unit_x 0.5)<>(0.5,0.,0.)
    then failwith "Vec3 deterministic drift"
  done;
  print_endline "Prismel_next_api exact Vec2/Vec3 facade passed"
