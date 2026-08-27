open Prismel_next_api

let require condition message = if not condition then failwith message
let nearly left right = abs_float (left -. right) < 1e-12

let () =
  let rgba = Bytes.of_string "\xff\x00\x00\xff\x00\x00\xff\xff" in
  let image = Result.get_ok (Prismel_next_resources.Image.create ~width:2 ~height:1 ~rgba) |> Image.Private.of_resource in
  let scene =
    [ Scene.clear Color.transparent;
      Scene.clip ~at:(4, 3) ~w:11 ~h:9
        [ Scene.translate 2 1
            [ Scene.image image ~at:(5, 6) ~scale:2. ~angle:(Float.pi /. 2.)
                ~center:(1, 0) ~flip_x:true () ] ] ]
  in
  let ir, resources = Result.get_ok (Scene.Private.stage ~width:24 ~height:20 scene) in
  require (List.length resources = 1) "one image resource";
  (match Array.to_list (Raster2.Render_ir.commands ir) with
  | [ Clear _; Push_clip clip; Push_transform outer; Push_transform image_transform;
      Image command; Pop_transform; Pop_transform; Pop_clip ] ->
      require (clip.x = 4. && clip.y = 3. && clip.width = 11. && clip.height = 9.)
        "clip facts";
      require (outer.tx = 2. && outer.ty = 1.) "outer translation";
      require
        (command.destination.x = 5. && command.destination.y = 6.
         && command.destination.width = 4. && command.destination.height = 2.)
        "scaled image destination";
      require (nearly image_transform.xx 0. && nearly image_transform.xy (-1.))
        "rotation/flip xx/xy";
      require (nearly image_transform.yx (-1.) && nearly image_transform.yy 0.)
        "rotation/flip yx/yy";
      require (nearly image_transform.tx 12. && nearly image_transform.ty 12.)
        "custom center pivot"
  | _ -> failwith "image transform/order/clip command stream");
  let render () =
    let target = Result.get_ok (Raster2.Surface.create ~width:24 ~height:20 ()) in
    let owned = ref [] in
    let lookup id =
      match List.assoc_opt id resources with
      | Some (Prismel_next_execution.Image value) ->
          let width, height = Result.get_ok (Prismel_next_resources.Image.size value) in
          let pixels = Result.get_ok (Prismel_next_resources.Image.pixels value) in
          let surface = Result.get_ok (Raster2.Surface.of_bytes ~width ~height ~pitch:(width * 4) pixels) in
          owned := surface :: !owned;
          Some (Raster2.Consumer.Image surface)
      | _ -> None
    in
    Result.get_ok (Raster2.Consumer.execute ~lookup ~target ir);
    Bytes.copy (Raster2.Surface.bytes target)
  in
  let pixels = render () in
  require (pixels = render ()) "deterministic transformed image capture";
  require
    (Bytes.exists (fun value -> value <> '\000') pixels)
    "transformed image must draw real pixels";
  List.iter
    (fun frame -> require (pixels = render ()) (Printf.sprintf "frame %d pixels" frame))
    [ 2; 60; 600 ];
  Image.destroy image;
  print_endline "Scene image scale/angle/center/flip/order/clip parity passed"
