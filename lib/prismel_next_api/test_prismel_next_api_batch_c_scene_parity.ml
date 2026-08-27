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
  let first_ir, first_resources =
    Result.get_ok (Scene.Private.stage ~width:32 ~height:24 scene)
  in
  let first_commands = Raster2.Render_ir.commands first_ir in
  require (Array.length first_commands = 7) "complete ordered lowering";
  (match Array.to_list first_commands with
  | [ Raster2.Render_ir.Clear _;
      Push_clip _;
      Set_blend Raster2.Composite.Alpha;
      Image text;
      Image view;
      Pop_clip;
      Geometry _ ] ->
      require (text.resource_id <> view.resource_id) "distinct staged resources"
  | commands ->
      let tag = function
        | Raster2.Render_ir.Clear _ -> "clear"
        | Set_blend _ -> "blend"
        | Push_clip _ -> "push-clip"
        | Pop_clip -> "pop-clip"
        | Push_transform _ -> "push-transform"
        | Pop_transform -> "pop-transform"
        | Geometry _ -> "geometry"
        | Image _ -> "image"
        | Glyphs _ -> "glyphs"
      in
      failwith
        ("text/View3d ordering or state scope: "
        ^ String.concat "," (List.map tag commands)));
  require (List.length first_resources = 2) "text and view resources";
  List.iter
    (fun frame ->
      let ir, resources =
        Result.get_ok (Scene.Private.stage ~width:32 ~height:24 scene)
      in
      require
        (Raster2.Render_ir.serialize ir = Raster2.Render_ir.serialize first_ir)
        (Printf.sprintf "frame %d deterministic IR" frame);
      require
        (resource_ids resources = resource_ids first_resources)
        (Printf.sprintf "frame %d must not re-upload" frame))
    [ 2; 60; 600 ];
  Scene.Private.release scene;
  List.iter
    (function
      | _, Prismel_next_execution.Image image ->
          require (Result.is_error (Image.pixels image)) "released staged image"
      | _, Prismel_next_execution.Text _ | _, Prismel_next_execution.Canvas _ ->
          failwith "unexpected staged resource")
    first_resources;
  print_endline "Prismel_next_api Scene text/View3d parity passed"
