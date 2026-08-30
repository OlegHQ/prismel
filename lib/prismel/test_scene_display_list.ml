open Prismel

let () =
  let builder = Scene_command.Display_list.Builder.create () in
  Scene_command.Display_list.Builder.solid_rect builder
    ~x:2. ~y:3. ~width:8. ~height:9. ~color:0xff0000ffl;
  let segment = Result.get_ok
      (Scene_command.Display_list.Builder.publish builder ~id:41L ~version:3L) in
  let node = Scene.display_list segment in
  let staged_ir, staged_resources = Result.get_ok
      (Scene.Private.stage ~width:32 ~height:32 [node]) in
  if staged_ir != Scene_command.Display_list.render_ir segment
     || staged_resources <> [] then
    failwith "root display list was copied during scene staging";
  let direct = Result.get_ok
      (Scene.Private.stage_native ~width:32 ~height:32 [node]) in
  (match direct.layers, direct.retained with
   | [Scene.Private.Scene2_segment (retained, [])],
     Some ("scene2-segment:41", 3L) when retained == segment -> ()
   | _ -> failwith "root display list did not retain direct native identity");
  let transformed = Result.get_ok
      (Scene.Private.stage_native ~width:32 ~height:32
         [Scene.translate 5 7 [node]]) in
  (match transformed.layers, transformed.retained with
   | [Scene.Private.Scene2_layer (ir, [])], Some (identity, 1L)
       when String.starts_with ~prefix:"scene-stage:" identity ->
       (match Array.to_list (Scene_command.Render_ir.Private.commands_readonly ir) with
        | [Scene_command.Render_ir.Push_transform _;
           Scene_command.Render_ir.Geometry _;
           Scene_command.Render_ir.Pop_transform] -> ()
        | _ -> failwith "transformed display-list command order drift")
   | _ -> failwith "transformed display list bypassed retained transform lowering");
  let equivalent () = [Scene.clear Color.black;
    Scene.rect ~at:(3, 4) ~w:12 ~h:9 ~fill:Color.white ()] in
  let first_equivalent = Result.get_ok
      (Scene.Private.stage_native_render ~width:32 ~height:32 (equivalent ()))
  and second_equivalent = Result.get_ok
      (Scene.Private.stage_native_render ~width:32 ~height:32 (equivalent ())) in
  if first_equivalent != second_equivalent then
    failwith "equivalent shallow scene composition missed native stage reuse";
  let changed = Result.get_ok (Scene.Private.stage_native_render
      ~width:32 ~height:32 [Scene.clear Color.black;
        Scene.rect ~at:(3, 4) ~w:13 ~h:9 ~fill:Color.white ()]) in
  if changed == first_equivalent then
    failwith "changed shallow scene composition reused stale native stage";

  let image_builder = Scene_command.Display_list.Builder.create () in
  Scene_command.Display_list.Builder.image image_builder ~resource_id:7
    ~source:{ x = 0.; y = 0.; width = 1.; height = 1. }
    ~destination:{ x = 4.; y = 5.; width = 6.; height = 7. };
  let image_segment = Result.get_ok
      (Scene_command.Display_list.Builder.publish image_builder
         ~id:42L ~version:1L) in
  (match Scene.display_list image_segment with
   | _ -> failwith "display list accepted an unbound image resource"
   | exception Invalid_argument _ -> ());
  let image = Image.create ~width:1 ~height:1 ~color:Color.white () in
  Fun.protect ~finally:(fun () -> Image.destroy image) (fun () ->
    (match Scene.display_list ~images:[7,image;7,image] image_segment with
     | _ -> failwith "display list accepted a duplicate image resource"
     | exception Invalid_argument _ -> ());
    let image_node = Scene.display_list ~images:[7,image] image_segment in
    let first = Result.get_ok
        (Scene.Private.stage_native ~width:32 ~height:32 [image_node]) in
    (match first.layers with
     | [Scene.Private.Scene2_segment (retained,
         [7, Prismel_next_execution.Image resource])]
         when retained == image_segment
           && resource == Image.Private.resource image -> ()
     | _ -> failwith "display-list image binding lost managed identity");
    let replacement = Image.create ~width:1 ~height:1 ~color:Color.black () in
    Image.Private.replace image replacement;
    let second = Result.get_ok
        (Scene.Private.stage_native ~width:32 ~height:32 [image_node]) in
    if first.retained = second.retained then
      failwith "display-list resource generation did not invalidate replay");
  print_endline "Scene display list: direct retained layer and transformed parity"
