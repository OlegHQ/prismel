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

  let complete = Display_list.Builder.create ~capacity:2 () in
  Display_list.Builder.reserve complete 65;
  require ((Display_list.Builder.stats complete).command_capacity = 128)
    "display-list reserve did not use geometric capacity";
  let geometry = { Render_ir.vertices = [|0.; 0.; 2.; 0.; 0.; 2.|];
    indices = [|0; 1; 2|]; color = 0x01020304l }
  and glyphs = [|{ Render_ir.glyph_id = 3; x = 4.; y = 5. }|] in
  Display_list.Builder.clear complete 0x10203040l;
  Display_list.Builder.set_blend complete Render_ir.Multiply;
  Display_list.Builder.push_transform complete
    { xx = 1.; xy = 2.; yx = 3.; yy = 4.; tx = 5.; ty = 6. };
  Display_list.Builder.geometry complete geometry;
  Display_list.Builder.image complete ~resource_id:17
    ~source:{ x = 1.; y = 2.; width = 3.; height = 4. }
    ~destination:{ x = 5.; y = 6.; width = 7.; height = 8. };
  Display_list.Builder.glyphs complete ~resource_id:19 ~color:0xaabbccddl
    glyphs;
  Display_list.Builder.pop_transform complete;
  geometry.vertices.(0) <- 99.;
  glyphs.(0) <- { Render_ir.glyph_id = 99; x = 99.; y = 99. };
  let complete = Result.get_ok
      (Display_list.Builder.publish complete ~id:9L ~version:4L) in
  (match Array.to_list
      (Render_ir.Private.commands_readonly (Display_list.render_ir complete)) with
   | [ Clear 0x10203040l; Set_blend Multiply;
       Push_transform { xx = 1.; xy = 2.; yx = 3.; yy = 4.; tx = 5.; ty = 6. };
       Geometry owned;
       Image { resource_id = 17;
         source = { x = 1.; y = 2.; width = 3.; height = 4. };
         destination = { x = 5.; y = 6.; width = 7.; height = 8. } };
       Glyphs { resource_id = 19; color = 0xaabbccddl; glyphs = owned_glyphs };
       Pop_transform ]
       when owned.vertices.(0) = 0. && owned_glyphs.(0).glyph_id = 3 -> ()
   | _ -> failwith "display-list complete command or ownership parity drift");

  let hot = Display_list.Builder.create ~capacity:10_000 () in
  let before = Gc.allocated_bytes () in
  for _ = 0 to 9_999 do
    Display_list.Builder.solid_rect hot ~x:0. ~y:0.
      ~width:1. ~height:1. ~color:0xffffffffl
  done;
  let allocated = Gc.allocated_bytes () -. before in
  require (allocated <= 512.)
    (Printf.sprintf "display-list packed append allocated %.0f bytes" allocated);
  print_endline "display list: packed growth, exact validation, stable publication"
