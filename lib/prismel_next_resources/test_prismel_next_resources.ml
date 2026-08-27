open Prismel_next_resources
let get=function Ok x->x|Error e->failwith(Format.asprintf"%a"pp_error e)
let ()=
  let original=Bytes.of_string"\x11\x22\x33\xff\x44\x55\x66\xff\x77\x88\x99\xff\xaa\xbb\xcc\xff"in
  let image=get(Image.create~width:2~height:2~rgba:original)in Bytes.fill original 0 16 '\000';
  let identity=Image.identity image and generation=Image.generation image in
  (match Image.reload_file image"/definitely/missing.png"with Error _->()|Ok()->failwith"failed watch replaced image");
  if Image.identity image<>identity||Image.generation image<>generation||Bytes.get(get(Image.pixels image))0<>'\x11'then failwith"stable watched image retention";
  get(Image.replace image~width:1~height:1~rgba:(Bytes.of_string"\xff\x00\x00\xff"));
  if Image.identity image<>identity||Image.generation image<>generation+1 then failwith"image identity/generation";
  let canvas=get(Canvas.create~width:4~height:4)in
  let canvas_generation=Canvas.generation canvas in
  get(Canvas.clear canvas 0x010203ffl);get(Canvas.draw_image canvas image~x:1~y:1);
  if Canvas.generation canvas<>canvas_generation+2 then failwith"canvas mutation generation";
  let replacement=Bytes.make(4*4*4)'\x7f' in
  get(Canvas.replace_pixels canvas replacement);
  if Canvas.generation canvas<>canvas_generation+3 then failwith"canvas bulk generation";
  (match Canvas.replace_pixels canvas Bytes.empty with Error{kind=Invalid_argument;_}->()|_->failwith"canvas accepted malformed bulk pixels");
  let stable=get(Image.create~width:4~height:4~rgba:(Bytes.make 64 '\000'))in
  let stable_identity=Image.identity stable and stable_generation=Image.generation stable in
  get(Canvas.copy_to_image canvas stable);
  if Image.identity stable<>stable_identity||Image.generation stable<>stable_generation+1
     ||get(Image.pixels stable)<>replacement then failwith"canvas stable image copy";
  let moved=get(Image.create~width:4~height:4~rgba:(Bytes.make 64 '\x42'))in
  let moved_generation=Image.generation stable in
  get(Image.replace_owned stable moved);
  if not(Image.destroyed moved)||Image.identity stable<>stable_identity
     ||Image.generation stable<>moved_generation+1
     ||get(Image.pixels stable)<>Bytes.make 64 '\x42'
  then failwith"owned image replacement";
  let rejected=get(Image.create~width:1~height:1~rgba:(Bytes.make 4 '\x31'))in
  let rejected_pixels=get(Image.pixels rejected)and stable_pixels=get(Image.pixels stable)
  and stable_generation=Image.generation stable in
  (match Image.replace_owned stable stable with
   |Error{kind=Invalid_argument;_}->()
   |_->failwith"self owned replacement accepted");
  if Image.destroyed rejected||get(Image.pixels rejected)<>rejected_pixels
     ||Image.generation stable<>stable_generation||get(Image.pixels stable)<>stable_pixels
  then failwith"owned replacement rejection mutated images";
  get(Image.destroy rejected);
  let allocation=ref 0. in
  for _=1 to 32 do
    let source=get(Image.create~width:640~height:480~rgba:(Bytes.make(640*480*4)'\x5a'))in
    let before=Gc.allocated_bytes()in
    get(Image.replace_owned stable source);
    allocation:=!allocation+.(Gc.allocated_bytes()-.before)
  done;
  if !allocation/.32.>2048. then
    failwith(Printf.sprintf"owned replacement allocated %.0f bytes/copy"(!allocation/.32.));
  get(Image.destroy stable);
  let before=get(Canvas.capture canvas)in
  let before_pixels=get(Image.pixels before)and before_generation=Canvas.generation canvas in
  let missing=Result.get_ok(Raster2.Render_ir.create[|Raster2.Render_ir.Image{
    resource_id=404;source={x=0.;y=0.;width=1.;height=1.};
    destination={x=0.;y=0.;width=1.;height=1.}}|])in
  (match Canvas.render_ir canvas~lookup:(fun _->None)missing with
   |Error{kind=Invalid_argument;_}->()|_->failwith"canvas accepted missing render resource");
  let after_rejection=get(Canvas.capture canvas)in
  if Canvas.generation canvas<>before_generation||get(Image.pixels after_rejection)<>before_pixels
  then failwith"canvas rejected render was not atomic";
  get(Image.destroy after_rejection);get(Image.destroy before);
  List.iter(fun frame->if List.mem frame[1;2;60;600]then let capture=get(Canvas.capture canvas)in if get(Image.size capture)<>(4,4)then failwith"capture";get(Image.destroy capture)) [1;2;60;600];
  get(Canvas.resize canvas~width:8~height:8);if get(Canvas.size canvas)<>(8,8)then failwith"resize";
  let png=Filename.temp_file"prismel-next-"".png"in get(Canvas.save_png canvas png);let input=open_in_bin png in let signature=really_input_string input 8 in close_in input;Sys.remove png;if signature<>"\x89PNG\r\n\x1a\n"then failwith"PNG";
  let assets=Assets.create()and order=ref[]in ignore(get(Assets.borrow assets~destroy:(fun()->order:=1::!order;Image.destroy image)image));ignore(get(Assets.borrow assets~destroy:(fun()->order:=2::!order;Canvas.destroy canvas)canvas));get(Assets.destroy assets);if!order<>[1;2]then failwith"on_stop order";
  for _=1 to 100_000 do let x=get(Image.create~width:1~height:1~rgba:(Bytes.make 4 '\000'))in get(Image.destroy x)done;
  (match Domain.spawn(fun()->Image.create~width:1~height:1~rgba:(Bytes.make 4 '\000'))|>Domain.join with Error{kind=Wrong_domain;_}->()|_->failwith"domain");
  print_endline"prismel_next_resources: image/canvas/assets frame600 PNG 100k passed"
