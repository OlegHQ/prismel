open Prismel

let require condition message=if not condition then failwith message
let stage scene=
  let _,resources=Result.get_ok(Scene.Private.stage~width:64~height:32 scene)in
  match resources with
  |[identity,Prismel_next_execution.Image image]->identity,image
  |_->failwith"automatic text resource shape"

let ()=
  Font.shutdown();
  let first_identity=ref None and first_pixels=ref None in
  Gc.full_major();let before=Gc.allocated_bytes()in
  for frame=1 to 600 do
    let scene=Scene.[text~at:(3,4)~size:16~color:(Color.rgb 12 34 56)"stable automatic text"]in
    let identity,image=stage scene in
    let pixels=Result.get_ok(Prismel_next_resources.Image.pixels image)in
    (match!first_identity,!first_pixels with
    |None,None->first_identity:=Some identity;first_pixels:=Some pixels
    |Some expected_identity,Some expected_pixels->
      require(identity=expected_identity)(Printf.sprintf"frame %d automatic identity"frame);
      require(pixels=expected_pixels)(Printf.sprintf"frame %d automatic pixels"frame)
    |_->assert false);
    Scene.Private.release scene
  done;
  let per_frame=(Gc.allocated_bytes()-.before)/.600. in
  let entries,fonts,references=Font.Private.automatic_counts()in
  require(entries=1&&fonts=1&&references=0)"stable automatic cache ownership";
  require(per_frame<20_000.)"automatic text allocation regression";
  let retina=Scene.[text~at:(0,0)~size:16~color:(Color.rgb 12 34 56)"density"]in
  let one=Result.get_ok(Scene.Private.stage_native~density:1~width:64~height:32 retina)in
  Scene.Private.release retina;
  let two=Result.get_ok(Scene.Private.stage_native~density:2~width:64~height:32 retina)in
  let size=function
    |[_,Prismel_next_execution.Image image]->
        Result.get_ok(Prismel_next_resources.Image.size image)
    |_->failwith"density text resource"in
  let w1,h1=size one.resources and w2,h2=size two.resources in
  require(abs(w2-w1*2)<=4&&abs(h2-h1*2)<=2)
    (Printf.sprintf"Retina text was not rasterized at density 2 (%dx%d vs %dx%d)"w1 h1 w2 h2);
  let dest ir=
    let found=ref None in
    Array.iter(function
      |Scene_command.Render_ir.Image image->found:=Some image.destination
      |_->())(Scene_command.Render_ir.commands ir);
    match !found with Some rect->rect|None->failwith"density text destination"in
  let d1=dest one.scene2 and d2=dest two.scene2 in
  require(abs_float(d1.width-.d2.width)<3.&&abs_float(d1.height-.d2.height)<2.)
    (Printf.sprintf"Retina text destination left logical space (%.1fx%.1f vs %.1fx%.1f)"
      d1.width d1.height d2.width d2.height);
  Scene.Private.release retina;
  Printf.printf"automatic text allocation: %.0f bytes/frame\n%!"per_frame;
  for index=0 to 299 do
    let scene=Scene.[text~at:(0,0)~size:16(Printf.sprintf"entry-%03d"index)]in
    ignore(stage scene);Scene.Private.release scene
  done;
  let entries,fonts,references=Font.Private.automatic_counts()in
  require(entries=256&&fonts=1&&references=0)"automatic LRU capacity";
  (* If all 256 cached entries are pinned, the next value is transient rather
     than invalidating an image still borrowed by an active scene. *)
  Font.shutdown();
  let scenes=Array.init 257(fun index->Scene.[text~at:(0,0)~size:16(Printf.sprintf"pinned-%03d"index)])in
  let images=Array.map(fun scene->snd(stage scene))scenes in
  let entries,fonts,references=Font.Private.automatic_counts()in
  require(entries=256&&fonts=1&&references=257)"pinned cache overflow policy";
  Array.iter(fun image->require(Result.is_ok(Prismel_next_resources.Image.pixels image))"pinned image invalidated")images;
  Array.iter Scene.Private.release scenes;
  require(Result.is_error(Prismel_next_resources.Image.pixels images.(256)))"transient image retained";
  (* Explicit font cache ownership remains independent of scene release. *)
  let font=Result.get_ok(Font.system~size:15())in
  let explicit=Scene.[font_text font~at:(0,0)"explicit lifetime"]in
  let _,image=stage explicit in Scene.Private.release explicit;
  require(Result.is_ok(Prismel_next_resources.Image.pixels image))"explicit cached text shortened";
  Font.destroy font;
  require(Result.is_error(Prismel_next_resources.Image.pixels image))"explicit font cache not destroyed";
  Font.shutdown();
  let entries,fonts,references=Font.Private.automatic_counts()in
  require(entries=0&&fonts=0&&references=0)"automatic shutdown teardown";
  print_endline"bounded automatic Font/text cache passed"
