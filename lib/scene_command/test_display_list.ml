open Scene_command

let require condition message = if not condition then failwith message

let () =
  let builder = Display_list.Builder.create () in
  Display_list.Builder.push_clip builder ~x:0. ~y:0. ~width:64. ~height:64.;
  Display_list.Builder.pop_clip builder;
  let first = Result.get_ok (Display_list.Builder.publish builder ~id:7L ~version:1L)
  and same = Result.get_ok (Display_list.Builder.publish builder ~id:7L ~version:1L) in
  require (first == same && Display_list.id first = 7L
    && Display_list.version first = 1L)
    "display-list stable publication identity drift";
  require (Render_ir.Private.identity (Display_list.render_ir first) =
    Render_ir.Private.identity (Display_list.render_ir same))
    "unchanged display-list IR lost its identity";
  let commands = Render_ir.Private.commands_readonly (Display_list.render_ir first) in
  require (Array.length commands = 2)
    "display-list command cardinality drift";
  (match commands.(0), commands.(1) with
   | Render_ir.Push_clip _, Render_ir.Pop_clip -> ()
   | _ -> failwith "display-list command order drift");
  Display_list.Builder.reset builder;
  let reset = Result.get_ok
      (Display_list.Builder.publish builder ~id:7L ~version:1L) in
  require (reset != first
    && Array.length
         (Render_ir.Private.commands_readonly (Display_list.render_ir reset)) = 0)
    "display-list reset reused a stale publication";
  require (Render_ir.Private.identity (Display_list.render_ir reset) <>
    Render_ir.Private.identity (Display_list.render_ir first))
    "changed display-list IR reused its old identity";
  let invalid = Display_list.Builder.create () in
  Display_list.Builder.pop_clip invalid;
  (match Display_list.Builder.publish invalid ~id:8L ~version:1L with
   | Error Render_ir.Unbalanced_clip -> ()
   | _ -> failwith "display-list accepted an unbalanced clip");

  let complete = Display_list.Builder.create () in
  let geometry = { Render_ir.vertices = [|0.; 0.; 2.; 0.; 0.; 2.|];
    indices = [|0; 1; 2|]; color = 0x01020304l } in
  Display_list.Builder.geometry complete geometry;
  Display_list.Builder.image complete ~resource_id:17
    ~source:{ x = 1.; y = 2.; width = 3.; height = 4. }
    ~destination:{ x = 5.; y = 6.; width = 7.; height = 8. };
  geometry.vertices.(0) <- 99.;
  let complete = Result.get_ok
      (Display_list.Builder.publish complete ~id:9L ~version:4L) in
  (match Array.to_list
      (Render_ir.Private.commands_readonly (Display_list.render_ir complete)) with
   | [ Geometry owned;
       Image { resource_id = 17;
         source = { x = 1.; y = 2.; width = 3.; height = 4. };
         destination = { x = 5.; y = 6.; width = 7.; height = 8. } } ]
       when owned.vertices.(0) = 0. -> ()
   | _ -> failwith "display-list complete command or ownership parity drift");

  print_endline "display list: exact validation, stable publication"
