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
   | [Scene.Private.Scene2_segment retained],
     Some ("scene2-segment:41", 3L) when retained == segment -> ()
   | _ -> failwith "root display list did not retain direct native identity");
  let transformed = Result.get_ok
      (Scene.Private.stage_native ~width:32 ~height:32
         [Scene.translate 5 7 [node]]) in
  (match transformed.layers, transformed.retained with
   | [Scene.Private.Scene2_layer (ir, [])], None ->
       (match Array.to_list (Scene_command.Render_ir.Private.commands_readonly ir) with
        | [Scene_command.Render_ir.Push_transform _;
           Scene_command.Render_ir.Geometry _;
           Scene_command.Render_ir.Pop_transform] -> ()
        | _ -> failwith "transformed display-list command order drift")
   | _ -> failwith "transformed display list bypassed transform lowering");
  print_endline "Scene display list: direct retained layer and transformed parity"
