let () =
  if Array.length Sys.argv <> 3 then invalid_arg "candidate capture: RGBA META";
  let width=R10_scene3_semantics.width and height=R10_scene3_semantics.height in
  let canonical=R10_scene3_legacy_equivalent.create~width~height in
  ignore(Result.get_ok(R10_scene3_equivalence_bridge.prove~width~height canonical));
  let public=R10_scene3_equivalence_bridge.public_workload()in
  let render ()=
    let image=Prismel_next_api.Scene3_image.render~width~height
      ~camera:public.camera public.scene in
    Fun.protect~finally:(fun()->Prismel_next_api.Image.destroy image)(fun()->
      Result.get_ok(Prismel_next_api.Image.Private.pixels image))in
  let rgba=render()in
  List.iter(fun frame->
    let repeated=render()in
    if repeated<>rgba then
      failwith(Printf.sprintf"candidate frame %d changed"frame))
    [2;60;600];
  R10_scene3_semantics.write Sys.argv.(1)rgba;
  R10_scene3_semantics.metadata Sys.argv.(2)
    ~backend:"prismel-next-scene3-native"~rgba
