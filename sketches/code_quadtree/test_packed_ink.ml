open Prismel

let () =
  let live_handles=snd (Ogpu.Impl.create_driver ()) in
  let baseline=live_handles () in
  let plain=ref [] and packed=Packed_ink.create () in
  let add node=plain:=node::!plain in
  for i=0 to 400 do
    let x=i*7 mod 119-4 and y=i*13 mod 121-4 in
    let color=if i mod 3=0 then Color.rgba 200 170 110 130
      else Color.rgb (i mod 255) 160 210 in
    Packed_ink.rect packed x y 5 7 color;
    add (Scene.rect ~at:(x,y) ~w:5 ~h:7 ~fill:color ());
    if i mod 11=0 then begin
      Packed_ink.line packed x y (x+9) (y+3) color;
      add (Scene.line ~from_:(x,y) ~to_:(x+9,y+3) ~color ());
      Packed_ink.outline packed x y 13 8 color;
      add (Scene.rect ~at:(x,y) ~w:13 ~h:8 ~stroke:color ())
    end
  done;
  (* Fractional rectangles use an independently tessellated path as oracle.
     This catches accidental integer snapping anywhere in the packed path. *)
  for i=0 to 31 do
    let x=1.125+.float (i*11 mod 110) and y=2.375+.float (i*17 mod 110) in
    let w=0.75+.float (i mod 7)*.0.125 and h=1.5 in
    let color=Color.rgba 230 221 193 (90+i*5) in
    Packed_ink.rectf packed x y w h color;
    let module P=Scene_command.Path in
    let path=P.of_commands [|P.Move_to {x;y};P.Line_to {x=x+.w;y};
      P.Line_to {x=x+.w;y=y+.h};P.Line_to {x;y=y+.h};P.Close|] in
    let mesh=Result.get_ok (P.tessellate ~tolerance:0.25 ~fill_rule:P.Non_zero path) in
    let vertices=Array.make (Array.length mesh.vertices*2) 0. in
    Array.iteri (fun j (p:P.point) -> vertices.(j*2)<-p.x;vertices.(j*2+1)<-p.y) mesh.vertices;
    let builder=Scene_command.Display_list.Builder.create () in
    Scene_command.Display_list.Builder.geometry builder
      {vertices;indices=mesh.indices;color=Packed_ink.rgba color};
    add (Scene.display_list (Result.get_ok (Scene_command.Display_list.Builder.publish builder
      ~id:(Scene_command.Display_list.fresh_id ()) ~version:0L)))
  done;
  let batch=Option.get (Packed_ink.take packed) in
  let clipped=Packed_ink.create ~ids:[|777L;778L|] ~version:2L ~clip:(3,5,112,107) () in
  Packed_ink.rect clipped 0 0 128 128 Color.white;
  let clipped_batch=Option.get (Packed_ink.take clipped) in
  Packed_ink.set_clip clipped None;
  Packed_ink.rect clipped 0 0 128 128 Color.white;
  let unclipped_batch=Option.get (Packed_ink.take clipped) in
  let canvas=Canvas.create_exn ~width:128 ~height:128 in
  Fun.protect ~finally:(fun () -> Canvas.destroy canvas) (fun () ->
    let clip nodes=Scene.clip ~at:(3,5) ~w:112 ~h:107 nodes in
    Canvas.render canvas [Scene.clear Color.black;clip (List.rev !plain)];
    let expected=Canvas.pixels canvas in
    for _=1 to 4 do
      Canvas.render canvas [Scene.clear Color.black;clip [batch]];
      if Canvas.pixels canvas<>expected then failwith "packed painter order/pixel drift"
    done;
    Canvas.render canvas [Scene.clear Color.black;clipped_batch];
    if Canvas.pixel canvas ~x:0 ~y:0<>Some Color.black ||
       Canvas.pixel canvas ~x:3 ~y:5<>Some Color.white then failwith "internal segment clip";
    Canvas.render canvas [Scene.clear Color.black;unclipped_batch];
    if Canvas.pixel canvas ~x:0 ~y:0<>Some Color.white then failwith "segment clip reset");
  let after=live_handles () in
  if after<>baseline then failwith "packed native handle delta";
  print_endline "packed ink: exact native pixels vs Scene rect/line/stroke, alpha/order/clip, zero handle delta"
