open Prismel_next_api
let check condition message=if not condition then failwith message
let ()=
  let path=Path.empty|>Path.move_to 0. 0.|>Path.line_to 4. 0.|>Path.quadratic_to~control:(6.,2.)~to_:(4.,4.)|>Path.line_to 0. 4.|>Path.close in
  check(Path.is_closed path&&List.length(Path.points~steps:8 path)>8)"Path flatten";
  let sequential=Parallel.run~domains:1(fun()->Parallel.init_array~grain:64 100_000(fun i->i*i))
  and parallel=Parallel.run~domains:4(fun()->Parallel.init_array~grain:64 100_000(fun i->i*i))in
  check(sequential=parallel)"Parallel exact 100k";
  let colors=[Color.red;Color.green;Color.blue;Color.white]in
  let texture=Texture.create_exn~width:2~height:2 colors|>Texture.generate_mipmaps in
  check(Texture.mipmap_count texture=2)"Texture mipmaps";
  check(Texture.sample texture~filter:Nearest~u:0.~v:0.=Color.red)"Texture nearest";
  let canvas=match Prismel_next_resources.Canvas.create~width:2~height:2 with Ok x->x|Error _->failwith"canvas"in
  ignore(Prismel_next_resources.Canvas.clear canvas 0x112233ffl);let file=Filename.temp_file"next-texture-"".png"in
  ignore(Prismel_next_resources.Canvas.save_png canvas file);let loaded=Texture.load_exn file in
  check(Texture.pixel loaded~x:0~y:0=Some(Color.rgba 0x11 0x22 0x33 0xff))"Texture SDL3 load";
  Sys.remove file;ignore(Prismel_next_resources.Canvas.destroy canvas);
  let shader=Shader3.create~varying_count:1~vertex:(fun input->{(Shader3.default_vertex input)with varyings=[float input.vertex_index]})~fragment:Shader3.default_fragment()in
  check(Shader3.varying_count shader=1&&not(Shader3.has_geometry shader))"Shader3 stages";
  let values=Compute3.dispatch~grain:64~groups:(1000,10,10)~local_size:(1,1,1)(fun invocation->invocation.linear_index)in
  let exact=ref(Array.length values=100_000)in Array.iteri(fun index value->if index<>value then exact:=false)values;
  check !exact"Compute3 exact 100k";
  Parallel.release_current_domain_pools();
  print_endline"Prismel_next_api batch D path/parallel/texture/shader/compute passed"
