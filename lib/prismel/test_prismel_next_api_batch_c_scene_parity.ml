open Prismel_next_api

let require condition message = if not condition then failwith message

let resource_ids resources = List.map fst resources

let () =
  let camera =
    Camera.perspective ~at:(Vec3.create 0. 0. 3.) ~target:Vec3.zero ()
  in
  let scene3 = Scene3.create [] in
  let scene =
    [ Scene.clear Color.black;
      Scene.clip ~at:(0, 0) ~w:32 ~h:24
        [ Scene.blend Scene.Alpha
            [ Scene.text ~at:(2, 3) ~size:12 "staged text";
              Scene.view3d ~viewport:(8, 4, 16, 12) ~camera scene3 ] ];
      Scene.rect ~at:(1, 1) ~w:3 ~h:2 ~fill:Color.red () ]
  in
  let first=Result.get_ok(Scene.Private.stage_native~width:32~height:24 scene)in
  let first_ir,first_resources=first.scene2,first.resources in
  let first_commands = Scene_command.Render_ir.commands first_ir in
  let automatic_text_id=ref None in
  require (Array.length first_commands = 6) "complete ordered lowering";
  require(List.length first.scene3=1)"View3d native staging";
  (match Array.to_list first_commands with
  | [ Scene_command.Render_ir.Clear _;
      Push_clip _;
      Set_blend Scene_command.Render_ir.Alpha;
      Image text;
      Pop_clip;
      Geometry _ ] ->
      automatic_text_id:=Some text.resource_id;
  | commands ->
      let tag = function
        | Scene_command.Render_ir.Clear _ -> "clear"
        | Set_blend _ -> "blend"
        | Push_clip _ -> "push-clip"
        | Pop_clip -> "pop-clip"
        | Push_transform _ -> "push-transform"
        | Pop_transform -> "pop-transform"
        | Geometry _ -> "geometry"
        | Image _ -> "image"
        | Glyphs _ -> "glyphs"
        | Debug_text _ -> "debug-text"
      in
      failwith
        ("text/View3d ordering or state scope: "
        ^ String.concat "," (List.map tag commands)));
  require (List.length first_resources = 1) "text resource";
  List.iter
    (fun frame ->
      let staged=Result.get_ok(Scene.Private.stage_native~width:32~height:24 scene)in
      let ir,resources=staged.scene2,staged.resources in
      require
        (Scene_command.Render_ir.serialize ir = Scene_command.Render_ir.serialize first_ir)
        (Printf.sprintf "frame %d deterministic IR" frame);
      require
        (resource_ids resources = resource_ids first_resources)
        (Printf.sprintf "frame %d must not re-upload" frame);
      require(List.length staged.scene3=1)
        (Printf.sprintf"frame %d native View3d drift"frame))
    [ 2; 60; 600 ];
  let diagnostic=Scene.[debug_text~at:(5,7)~color:(Color.rgba 1 2 3 4)"fixed"]in
  let diagnostic_encoding=ref None in
  List.iter(fun frame->
    let ir,resources=Result.get_ok(Scene.Private.stage~width:32~height:24 diagnostic)in
    require(resources=[]) (Printf.sprintf"debug text frame %d allocated resource"frame);
    let encoding=Scene_command.Render_ir.serialize ir in
    (match!diagnostic_encoding with None->diagnostic_encoding:=Some encoding
      |Some expected->require(encoding=expected)(Printf.sprintf"debug text frame %d drift"frame));
    match Array.to_list(Scene_command.Render_ir.commands ir)with
    |[Debug_text{x;y;text;color}]->
        require(x=5.&&y=7.&&text="fixed"&&color=0x01020304l)
          (Printf.sprintf"debug text frame %d semantics"frame)
    |_->failwith"debug text did not lower directly")[1;2;60;600];
  Scene.Private.release diagnostic;
  let after_ir,after_release=Result.get_ok(Scene.Private.stage~width:32~height:24 diagnostic)in
  require(after_release=[])"debug text release acquired ownership";
  require(Some(Scene_command.Render_ir.serialize after_ir)= !diagnostic_encoding)"debug text release changed IR";
  Scene.Private.release scene;
  List.iter
    (function
      | identity, Prismel_next_execution.Image image when Some identity= !automatic_text_id ->
          require (Result.is_ok (Prismel_next_resources.Image.pixels image)) "released automatic cache image"
      | _, Prismel_next_execution.Image image ->
          require (Result.is_error (Prismel_next_resources.Image.pixels image)) "released owned staged image"
      | _, Prismel_next_execution.Text _ | _, Prismel_next_execution.Canvas _ ->
          failwith "unexpected staged resource")
    first_resources;
  Font.shutdown();
  List.iter(function
    |identity,Prismel_next_execution.Image image when Some identity= !automatic_text_id->
      require(Result.is_error(Prismel_next_resources.Image.pixels image))"automatic image survived shutdown"
    |_->())first_resources;
  print_endline "Prismel_next_api Scene text/View3d parity passed"
