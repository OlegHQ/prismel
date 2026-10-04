let run () =
  let open Rays in
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
  (* A camera's lens: pinhole by default, focus on the target unless set. *)
  let camera = Camera.perspective ~at:(Vec3.create 0. 0. 4.) ~target:Vec3.zero () in
  if Camera.lens camera <> Camera.pinhole || Camera.focus_distance camera <> 4. then
    failwith "Camera default lens";
  let lens = { Camera.aperture = 0.25; focus_distance = Some 2.5 } in
  let focused = Camera.with_lens lens camera in
  if Camera.lens focused <> lens || Camera.focus_distance focused <> 2.5
     || Camera.focus_distance (Camera.with_lens { lens with focus_distance = None } focused) <> 4.
  then failwith "Camera.with_lens";
  (match Camera.with_lens { lens with aperture = -1. } camera with
   | _ -> failwith "Camera.with_lens accepted a negative aperture"
   | exception Invalid_argument _ -> ());
  print_endline "Rays exact Vec2/Vec3 API passed"
