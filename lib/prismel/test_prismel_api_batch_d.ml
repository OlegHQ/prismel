open Prismel
let check condition message=if not condition then failwith message
let run () =
  let path=Path.empty|>Path.move_to 0. 0.|>Path.line_to 4. 0.|>Path.quadratic_to~control:(6.,2.)~to_:(4.,4.)|>Path.line_to 0. 4.|>Path.close in
  check(Path.is_closed path&&List.length(Path.points~steps:8 path)>8)"Path flatten";
  let sequential=Parallel.run~domains:1(fun()->Parallel.init_array~grain:64 100_000(fun i->i*i))
  and parallel=Parallel.run~domains:4(fun()->Parallel.init_array~grain:64 100_000(fun i->i*i))in
  check(sequential=parallel)"Parallel exact 100k";
  let colors=[Color.red;Color.green;Color.blue;Color.white]in
  let texture=Texture.create_exn~width:2~height:2 colors|>Texture.generate_mipmaps in
  check(Texture.mipmap_count texture=2)"Texture mipmaps";
  check(Texture.sample texture~filter:Nearest~u:0.~v:0.=Color.red)"Texture nearest";
  let canvas=match Runtime_resources.Canvas.create~width:2~height:2 with Ok x->x|Error _->failwith"canvas"in
  ignore(Runtime_resources.Canvas.clear canvas 0x112233ffl);let file=Filename.temp_file"next-texture-"".png"in
  ignore(Runtime_resources.Canvas.save_png canvas file);let loaded=Texture.load_exn file in
  check(Texture.pixel loaded~x:0~y:0=Some(Color.rgba 0x11 0x22 0x33 0xff))"Texture SDL3 load";
  Sys.remove file;ignore(Runtime_resources.Canvas.destroy canvas);
  Parallel.release_current_domain_pools();
  print_endline"Prismel batch D path/parallel/texture passed"
