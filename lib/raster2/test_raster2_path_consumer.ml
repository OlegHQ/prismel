open Raster2

let ok = function Ok value -> value | Error _ -> failwith "path consumer error"
let p x y = Path.{ x; y }
let rect ~clockwise x0 y0 x1 y1 =
  let ps = if clockwise then [|p x0 y0;p x0 y1;p x1 y1;p x1 y0|]
    else [|p x0 y0;p x1 y0;p x1 y1;p x0 y1|] in
  [|Path.Move_to ps.(0);Path.Line_to ps.(1);Path.Line_to ps.(2);Path.Line_to ps.(3);Path.Close|]
let append a b = Array.init (Array.length a + Array.length b) (fun i -> if i < Array.length a then a.(i) else b.(i - Array.length a))
let pixel s x y = ok (Surface.get_rgba s ~x ~y)

let render () =
  let surface = ok (Surface.create ~pitch:40 ~width:8 ~height:8 ()) in
  Surface.clear surface 0l;
  let commands = append (rect ~clockwise:false 0. 0. 8. 8.) (rect ~clockwise:false 2. 2. 6. 6.) in
  ok (Path_consumer.draw ~target:surface ~path:(Path.of_commands commands)
    ~style:(Path_consumer.Fill Path.Even_odd) ~tolerance:0.01 ~transform:Path_consumer.identity
    ~clip:{x=0;y=0;width=8;height=8} ~color:0xff0000ffl ~blend:Composite.Source_over
    ~antialias:Disabled);
  if pixel surface 1 1 <> 0xff0000ffl || pixel surface 3 3 <> 0l then failwith "transparent hole";
  let line = Path.of_commands [|Path.Move_to (p 1. 6.);Path.Line_to (p 6. 6.)|] in
  ok (Path_consumer.draw ~target:surface ~path:line
    ~style:(Path_consumer.Stroke {width=2.;cap=Path.Round;join=Path.Round;miter_limit=4.}) ~tolerance:0.05
    ~transform:Path_consumer.identity ~clip:{x=0;y=0;width=8;height=8}
    ~color:0x00ff00ffl ~blend:Composite.Copy ~antialias:Supersample4);
  if pixel surface 3 6 = 0l then failwith "stroke missing";
  let padding = Bytes.sub (Surface.bytes surface) 32 8 in
  if padding <> Bytes.make 8 '\000' then failwith "pitch padding modified";
  Surface.bytes surface

let () =
  let expected = render () in
  for _ = 1 to 600 do if render () <> expected then failwith "frame drift" done;
  let workers = Array.init 4 (fun _ -> Domain.spawn render) in
  Array.iter (fun worker -> if Domain.join worker <> expected then failwith "domain drift") workers;
  print_endline "Raster2 deterministic path consumer passed"
