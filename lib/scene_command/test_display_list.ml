open Scene_command

let require condition message = if not condition then failwith message

let () =
  let builder = Display_list.Builder.create ~capacity:1 () in
  Display_list.Builder.push_clip builder ~x:0. ~y:0. ~width:64. ~height:64.;
  for index = 0 to 15 do
    Display_list.Builder.solid_rect builder ~x:(float index) ~y:2.
      ~width:3. ~height:4. ~color:(Int32.of_int index)
  done;
  Display_list.Builder.pop_clip builder;
  let stats = Display_list.Builder.stats builder in
  require (stats.command_length = 18 && stats.command_capacity = 32
    && stats.high_water = 18 && stats.growths = 1)
    "display-list geometric growth drift";
  let first = Result.get_ok (Display_list.Builder.publish builder ~id:7L ~version:1L)
  and same = Result.get_ok (Display_list.Builder.publish builder ~id:7L ~version:1L) in
  require (first == same && Display_list.id first = 7L
    && Display_list.version first = 1L)
    "display-list stable publication identity drift";
  let commands = Render_ir.Private.commands_readonly (Display_list.render_ir first) in
  require (Array.length commands = 18)
    "display-list command cardinality drift";
  (match commands.(0), commands.(17) with
   | Render_ir.Push_clip _, Render_ir.Pop_clip -> ()
   | _ -> failwith "display-list command order drift");
  Display_list.Builder.reset builder;
  let reset = Result.get_ok
      (Display_list.Builder.publish builder ~id:7L ~version:1L) in
  require (reset != first
    && Array.length
         (Render_ir.Private.commands_readonly (Display_list.render_ir reset)) = 0)
    "display-list reset reused a stale publication";
  Display_list.Builder.debug_text builder ~x:1. ~y:2. ~color:0xff00ffffl "value";
  let second = Result.get_ok
      (Display_list.Builder.publish builder ~id:7L ~version:2L) in
  require (second != first && Display_list.version second = 2L
    && (Display_list.Builder.stats builder).command_capacity = 32)
    "display-list reset released capacity or failed to republish";
  let invalid = Display_list.Builder.create () in
  Display_list.Builder.pop_clip invalid;
  (match Display_list.Builder.publish invalid ~id:8L ~version:1L with
   | Error Render_ir.Unbalanced_clip -> ()
   | _ -> failwith "display-list accepted an unbalanced clip");
  print_endline "display list: packed growth, exact validation, stable publication"
