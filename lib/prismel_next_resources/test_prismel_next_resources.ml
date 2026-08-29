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
  let sw,sh,sg,snapshot=get(Canvas.snapshot canvas)in
  if(sw,sh,sg,snapshot)<>(4,4,Canvas.generation canvas,replacement)then
    failwith"canvas atomic snapshot";
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
  let hot=get(Canvas.create~width:640~height:480)in
  get(Canvas.clear hot 0x102030ffl);
  let leased_image=get(Image.create~width:640~height:480~rgba:(Bytes.make(640*480*4)'\000'))in
  get(Canvas.copy_to_image hot leased_image);
  let _,_,_,leased_pixels,lease1=get(Image.Private.borrow_snapshot leased_image)in
  let leased_copy=Bytes.copy leased_pixels in
  let lease_target=get(Image.create~width:1~height:1~rgba:(Bytes.make 4 '\x5c'))in
  let lease_target_before=get(Image.pixels lease_target)in
  (match Image.replace_owned lease_target leased_image with
   |Error{kind=Invalid_argument;_}->()
   |_->failwith"leased source storage was moved");
  if Image.destroyed leased_image||get(Image.pixels lease_target)<>lease_target_before then
    failwith"leased owned replacement was not atomic";
  get(Image.destroy lease_target);
  get(Canvas.clear hot 0xaabbccffl);get(Canvas.copy_to_image hot leased_image);
  if leased_pixels<>leased_copy then failwith"image mutation changed leased snapshot";
  let _,_,_,_,lease2=get(Image.Private.borrow_snapshot leased_image)in
  get(Canvas.clear hot 0x112233ffl);
  (match Canvas.copy_to_image hot leased_image with
   |Error{kind=Invalid_argument;_}->()
   |_->failwith"bounded image snapshot buffers were exceeded");
  Image.Private.release_snapshot lease1;
  get(Canvas.copy_to_image hot leased_image);
  Image.Private.release_snapshot lease2;
  Image.Private.release_snapshot lease2;
  get(Image.destroy leased_image);
  let destroy_leased=get(Image.create~width:1~height:1~rgba:(Bytes.of_string"\x12\x34\x56\x78"))in
  let _,_,_,destroy_bytes,destroy_lease=get(Image.Private.borrow_snapshot destroy_leased)in
  get(Image.destroy destroy_leased);
  if destroy_bytes<>Bytes.of_string"\x12\x34\x56\x78"then
    failwith"destroy invalidated leased image bytes";
  Image.Private.release_snapshot destroy_lease;
  Image.Private.release_snapshot destroy_lease;
  get(Canvas.destroy hot);
  let direct=get(Canvas.create~width:640~height:480)in
  let direct_generation=Canvas.generation direct in
  let _,_,first_bank=get(Canvas.Private.prepare_write direct)in
  Bytes.fill first_bank 0(Bytes.length first_bank)'\x2a';
  get(Canvas.Private.commit_write direct);
  if Canvas.generation direct<>direct_generation+1 then
    failwith"direct Canvas write did not commit one generation";
  let direct_image=get(Canvas.capture direct)in
  let _,_,second_bank=get(Canvas.Private.prepare_write direct)in
  if second_bank==first_bank then
    failwith"direct Canvas write changed a published image snapshot";
  get(Canvas.Private.commit_write direct);
  let before=Gc.allocated_bytes()in
  let _,_,reused_bank=get(Canvas.Private.prepare_write direct)in
  if reused_bank!=second_bank then
    failwith"direct Canvas write did not reuse its owned bank";
  get(Canvas.Private.commit_write direct);
  let direct_allocated=Gc.allocated_bytes()-.before in
  if direct_allocated>65536. then
    failwith(Printf.sprintf
      "direct Canvas write allocated %.0f bytes after warmup"direct_allocated);
  get(Image.destroy direct_image);get(Canvas.destroy direct);
  let bank_canvas=get(Canvas.create~width:4~height:4)in
  let bank_image=get(Image.create~width:4~height:4~rgba:(Bytes.make 64 '\000'))in
  get(Canvas.clear bank_canvas 0x2468acffl);
  get(Canvas.copy_to_image bank_canvas bank_image);
  Gc.compact();let bank_live_before=(Gc.quick_stat()).live_words in
  for _=1 to 100_000 do
    get(Canvas.clear bank_canvas 0x2468acffl);
    get(Canvas.copy_to_image bank_canvas bank_image)
  done;
  Gc.compact();let bank_live_after=(Gc.quick_stat()).live_words in
  if bank_live_after-bank_live_before>4096 then failwith"canvas/image two-bank loop did not plateau";
  let second=get(Image.create~width:4~height:4~rgba:(Bytes.make 64 '\x7f'))in
  get(Canvas.copy_to_image bank_canvas second);
  let first_pixels=get(Image.pixels bank_image)in
  get(Canvas.clear bank_canvas 0x2468acffl);
  if get(Image.pixels bank_image)<>first_pixels then failwith"second target changed first image";
  get(Image.replace bank_image~width:4~height:4~rgba:(Bytes.make 64 '\x3c'));
  let _,_,_,canvas_pixels=get(Canvas.snapshot bank_canvas)in
  if canvas_pixels=Bytes.make 64 '\x3c'then failwith"external image replacement changed canvas";
  get(Image.destroy bank_image);
  get(Canvas.clear bank_canvas 0x2468acffl);
  get(Canvas.resize bank_canvas~width:8~height:2);
  if get(Canvas.size bank_canvas)<>(8,2)then failwith"mirrored canvas resize";
  get(Image.destroy second);get(Canvas.destroy bank_canvas);
  List.iter(fun frame->if List.mem frame[1;2;60;600]then let capture=get(Canvas.capture canvas)in if get(Image.size capture)<>(4,4)then failwith"capture";get(Image.destroy capture)) [1;2;60;600];
  get(Canvas.resize canvas~width:8~height:8);if get(Canvas.size canvas)<>(8,8)then failwith"resize";
  let png=Filename.temp_file"prismel-next-"".png"in get(Canvas.save_png canvas png);let input=open_in_bin png in let signature=really_input_string input 8 in close_in input;Sys.remove png;if signature<>"\x89PNG\r\n\x1a\n"then failwith"PNG";
  let assets=Assets.create()and order=ref[]in ignore(get(Assets.borrow assets~destroy:(fun()->order:=1::!order;Image.destroy image)image));ignore(get(Assets.borrow assets~destroy:(fun()->order:=2::!order;Canvas.destroy canvas)canvas));get(Assets.destroy assets);if!order<>[1;2]then failwith"on_stop order";
  for _=1 to 100_000 do let x=get(Image.create~width:1~height:1~rgba:(Bytes.make 4 '\000'))in get(Image.destroy x)done;
  (match Domain.spawn(fun()->Image.create~width:1~height:1~rgba:(Bytes.make 4 '\000'))|>Domain.join with Error{kind=Wrong_domain;_}->()|_->failwith"domain");
  print_endline"prismel_next_resources: image/canvas/assets frame600 PNG 100k passed"
