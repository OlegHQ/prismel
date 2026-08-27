let get = function Ok value->value|Error error->failwith(Ogpu.Error.to_string error)
let () =
  if Array.length Sys.argv <> 3 then invalid_arg "candidate capture: RGBA META";
  let width=R10_scene3_semantics.width and height=R10_scene3_semantics.height in
  let canonical=R10_scene3_legacy_equivalent.create~width~height in
  ignore(Result.get_ok(R10_scene3_equivalence_bridge.prove~width~height canonical));
  let draws=List.map(fun draw->Scene_execution.Scene3,Ogpu.Pipeline.Replace,None,None,4,draw)canonical.software_draws in
  let runtime=get(Runtime_next_headless.create~logical_width:width~logical_height:height~drawable_width:width~drawable_height:height)in
  Fun.protect~finally:(fun()->ignore(Runtime_next_headless.destroy runtime))(fun()->
    if not(get(Runtime_next_headless.render_sampled_resources runtime draws))then failwith"candidate not presented";
    let rgba=get(Runtime_next_headless.read_pixels runtime~bytes_per_row:(width*4))in
    R10_scene3_semantics.write Sys.argv.(1)rgba;
    R10_scene3_semantics.metadata Sys.argv.(2)~backend:"runtime-next-raster2"~rgba)
