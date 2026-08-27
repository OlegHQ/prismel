type error =
  | Destroyed
  | Invalid_size
  | Scene2 of Scene_raster2_lowering.error
  | Scene3 of Scene3_raster2_lowering.error
  | Offscreen of Raster2.Offscreen.error
  | Scene3_render of Raster2.Scene3_consumer.error
  | Ir of Raster2.Render_ir.error
  | Surface
  | Depth

type frame = {
  rgba : bytes;
  pitch : int;
  logical_width : int;
  logical_height : int;
  drawable_width : int;
  drawable_height : int;
  generation : int;
}

type image_cache_entry = {
  source : Image.t;
  snapshot : Scene_raster2_lowering.image_snapshot;
}

type t = {
  mutable target : Raster2.Offscreen.t;
  mutable color3 : Raster2.Surface.t;
  mutable depth3 : Raster2.Depth_stencil.t;
  mutable logical_width : int;
  mutable logical_height : int;
  mutable drawable_width : int;
  mutable drawable_height : int;
  mutable generation : int;
  mutable destroyed : bool;
  mutable images : image_cache_entry list;
  image_capacity : int;
}

type callbacks = {
  scene2 : Scene_raster2_lowering.resources;
  scene3 : Scene3_raster2_lowering.resources;
}

let create_surface width height =
  match Raster2.Surface.create ~width ~height () with
  | Ok value -> Ok value
  | Error _ -> Error Surface

let create_depth width height =
  match Raster2.Depth_stencil.create ~width ~height () with
  | Ok value -> Ok value
  | Error _ -> Error Depth

let create ~logical_width ~logical_height ~drawable_width ~drawable_height =
  if logical_width <= 0 || logical_height <= 0 || drawable_width <= 0 ||
      drawable_height <= 0 then Error Invalid_size
  else
    match Raster2.Offscreen.create ~depth:true ~width:drawable_width
        ~height:drawable_height (), create_surface drawable_width drawable_height,
      create_depth drawable_width drawable_height with
    | Ok target, Ok color3, Ok depth3 -> Ok {
        target; color3; depth3; logical_width; logical_height; drawable_width;
        drawable_height; generation = 1; destroyed = false; images = [];
        image_capacity = 256;
      }
    | Error error, _, _ -> Error (Offscreen error)
    | _, Error error, _ | _, _, Error error -> Error error

let resize value ~logical_width ~logical_height ~drawable_width ~drawable_height =
  if value.destroyed then Error Destroyed
  else if logical_width <= 0 || logical_height <= 0 || drawable_width <= 0 ||
      drawable_height <= 0 then Error Invalid_size
  else if value.logical_width = logical_width &&
      value.logical_height = logical_height &&
      value.drawable_width = drawable_width &&
      value.drawable_height = drawable_height then Ok ()
  else
    match create_surface drawable_width drawable_height,
      create_depth drawable_width drawable_height with
    | Error error, _ | _, Error error -> Error error
    | Ok color3, Ok depth3 ->
        match Raster2.Offscreen.resize value.target ~width:drawable_width
            ~height:drawable_height with
        | Error error -> Error (Offscreen error)
        | Ok () ->
            value.color3 <- color3;
            value.depth3 <- depth3;
            value.logical_width <- logical_width;
            value.logical_height <- logical_height;
            value.drawable_width <- drawable_width;
            value.drawable_height <- drawable_height;
            value.generation <- value.generation + 1;
            Ok ()

let cached_image value callback source =
  let previous = List.find_opt (fun entry -> entry.source == source) value.images in
  match callback source with
  | Ok snapshot ->
      value.images <- { source; snapshot } ::
        List.filter (fun entry -> entry.source != source) value.images;
      if List.length value.images > value.image_capacity then
        value.images <- List.rev (List.tl (List.rev value.images));
      Ok snapshot
  | Error _ as failure ->
      begin match previous with
      | Some entry -> Ok entry.snapshot
      | None -> failure
      end

let scene2_resources value (callbacks : Scene_raster2_lowering.resources) =
  { callbacks with Scene_raster2_lowering.image =
      cached_image value callbacks.image }

let lookup resources id =
  Array.find_opt (fun (entry : Scene_raster2_lowering.resource_entry) ->
    entry.id = id) resources
  |> Option.map (fun (entry : Scene_raster2_lowering.resource_entry) ->
       entry.value)

let render_ir value ir resources =
  match Raster2.Offscreen.view value.target with
  | Error error -> Error (Offscreen error)
  | Ok view ->
      let result = Raster2.Offscreen.render view ~lookup:(lookup resources) ir in
      let released = Raster2.Offscreen.release_view view in
      begin match result, released with
      | Error error, _ | _, Error error -> Error (Offscreen error)
      | Ok (), Ok () -> Ok ()
      end

let render_scene3 value callbacks node =
  match Scene3_raster2_lowering.lower_view3d ~resources:callbacks
      ~default_viewport:(0, 0, value.drawable_width, value.drawable_height) node with
  | Error error -> Error (Scene3 error)
  | Ok prepared ->
      let target : Raster2.Scene3_consumer.target = {
        color = value.color3; depth = Some value.depth3; multisample = None;
      } in
      begin match Raster2.Scene3_consumer.render ~target ~clear:0x00000000l
          ~clear_depth:prepared.clear_depth ~draws:prepared.draws with
      | Error error -> Error (Scene3_render error)
      | Ok () ->
          let resource_id = 1 in
          let rect = Raster2.Render_ir.{ x = 0.; y = 0.;
            width = float value.drawable_width;
            height = float value.drawable_height } in
          match Raster2.Render_ir.create [|Raster2.Render_ir.Image {
              resource_id; source = rect; destination = rect }|] with
          | Error error -> Error (Ir error)
          | Ok ir -> render_ir value ir [|{
              Scene_raster2_lowering.id = resource_id;
              identity = Image_identity (Int64.of_int value.generation);
              value = Raster2.Consumer.Image value.color3;
            }|]
      end

let render value callbacks scene =
  if value.destroyed then Error Destroyed
  else
    let resources = scene2_resources value callbacks.scene2 in
    let rec loop = function
      | [] ->
          begin match Raster2.Offscreen.view value.target with
          | Error error -> Error (Offscreen error)
          | Ok view ->
              let captured = Raster2.Offscreen.capture view in
              let released = Raster2.Offscreen.release_view view in
              begin match captured, released with
              | Error error, _ | _, Error error -> Error (Offscreen error)
              | Ok capture, Ok () -> Ok {
                  rgba = capture.pixels; pitch = capture.pitch;
                  logical_width = value.logical_width;
                  logical_height = value.logical_height;
                  drawable_width = capture.width;
                  drawable_height = capture.height;
                  generation = value.generation;
                }
              end
          end
      | (Scene_description.View3d _ as node) :: rest ->
          begin match render_scene3 value callbacks.scene3 node with
          | Error _ as failure -> failure
          | Ok () -> loop rest
          end
      | node :: rest ->
          begin match Scene_raster2_lowering.lower_with_resources resources
              [node] with
          | Error error -> Error (Scene2 error)
          | Ok plan ->
              match render_ir value plan.ir plan.resources with
              | Error _ as failure -> failure
              | Ok () -> loop rest
          end
    in
    loop scene

let destroy value =
  if value.destroyed then Ok ()
  else match Raster2.Offscreen.destroy value.target with
  | Error error -> Error (Offscreen error)
  | Ok () -> value.destroyed <- true; value.images <- []; Ok ()

let self_test () =
  let ok = function Ok value -> value | Error _ -> failwith "renderer error" in
  let surface color =
    let value = ok (Raster2.Surface.create ~width:2 ~height:2 ()) in
    Raster2.Surface.clear value color; value
  in
  let key : Image.t = Obj.magic (ref 0) in
  let fail = ref false and cached = surface 0x00ff00ffl in
  let scene2 = Scene_raster2_lowering.{
    image = (fun _ -> if !fail then Error Resource_failure else
      Ok { resource_id = 7; generation = 1L; surface = cached });
    font_text = (fun _ _ _ _ -> Error Resource_failure);
    system_text = (fun _ _ -> Error Resource_failure);
    debug_text = (fun _ -> Error Resource_failure);
  } in
  let scene3 = Scene3_raster2_lowering.{
    texture = (fun _ -> Error Texture_error);
    shadow = (fun _ -> Error Shadow_error);
  } in
  let mesh = Mesh.create_exn ~normals:[Vec3.unit_z; Vec3.unit_z; Vec3.unit_z]
      [Vec3.create (-0.5) (-0.5) 0.; Vec3.create 0.5 (-0.5) 0.;
       Vec3.create 0. 0.5 0.] in
  let camera = Camera.orthographic ~height:2. ~at:(Vec3.create 0. 0. 2.)
      ~target:Vec3.zero () in
  let scene3_value = Scene3.create [Scene3.mesh
      ~material:(Material.unlit Color.red) ~cull:Scene3.Cull_none mesh] in
  let scene = [Scene_description.Clear Color.black;
    Scene_description.Image (key, (0, 0), None, None, None, None);
    Scene_description.View3d (camera, scene3_value, None)] in
  let callbacks = { scene2; scene3 } in
  let renderer = ok (create ~logical_width:16 ~logical_height:16
      ~drawable_width:16 ~drawable_height:16) in
  let draw () = (ok (render renderer callbacks scene)).rgba in
  let expected = draw () in
  List.iter (fun _ -> if draw () <> expected then failwith "frame drift")
    [2; 60; 600];
  fail := true;
  if draw () <> expected then failwith "failed reload identity";
  ok (resize renderer ~logical_width:9 ~logical_height:7
      ~drawable_width:18 ~drawable_height:14);
  let resized = ok (render renderer callbacks scene) in
  if resized.generation <> 2 || resized.drawable_width <> 18 then
    failwith "resize generation";
  ok (destroy renderer);
  let baseline = Raster2.Offscreen.counters () in
  for _ = 1 to 100_000 do
    let target = ok (create ~logical_width:1 ~logical_height:1
        ~drawable_width:1 ~drawable_height:1) in
    ok (destroy target)
  done;
  if Raster2.Offscreen.counters () <> baseline then failwith "counter plateau";
  let domain_render () =
    let target = ok (create ~logical_width:16 ~logical_height:16
        ~drawable_width:16 ~drawable_height:16) in
    fail := false;
    let bytes = (ok (render target callbacks scene)).rgba in
    ok (destroy target); bytes
  in
  let sequential = domain_render () in
  let workers = Array.init 4 (fun _ -> Domain.spawn domain_render) in
  Array.iter (fun worker -> if Domain.join worker <> sequential then
    failwith "domain drift") workers

let () =
  match Sys.getenv_opt "PRISMEL_TEST_RASTER2_RENDERER" with
  | Some "1" -> self_test ()
  | _ -> ()
