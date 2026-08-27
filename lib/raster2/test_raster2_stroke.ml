open Raster2.Path

let p x y = { x; y }
let ok = function Ok value -> value | Error _ -> failwith "stroke failed"
let line = of_commands [| Move_to (p 0. 0.); Line_to (p 10. 0.) |]
let style ?(cap = Butt) ?(join = Miter) path =
  ok (stroke ~tolerance:0.05 ~width:2. ~cap ~join ~miter_limit:4. path)

let encoded path = Marshal.to_bytes (style ~cap:Round ~join:Round path) []

let () =
  let butt = style line and square = style ~cap:Square line and round = style ~cap:Round line in
  assert (Array.length butt.indices = 6);
  assert (Array.length square.indices = 18);
  assert (Array.length round.indices > Array.length square.indices);
  let corner = of_commands [| Move_to (p 0. 0.); Line_to (p 5. 0.); Line_to (p 5. 5.) |] in
  assert (Array.length (style ~join:Bevel corner).indices = 15);
  assert (Array.length (style ~join:Round corner).indices > 15);
  assert (Array.length (style ~join:Miter corner).indices = 15);
  let closed = of_commands [| Move_to (p 0. 0.); Line_to (p 4. 0.); Line_to (p 4. 4.); Close |] in
  assert (Array.length (style closed).indices > 0);
  let degenerate = of_commands [| Move_to (p 1. 1.); Line_to (p 1. 1.) |] in
  assert (Array.length (style degenerate).indices = 0);
  (match stroke ~tolerance:0.1 ~width:nan ~cap:Butt ~join:Miter ~miter_limit:4. line with
  | Error (Invalid_width _) -> () | _ -> failwith "accepted invalid width");
  (match stroke ~tolerance:0.1 ~width:1. ~cap:Butt ~join:Miter ~miter_limit:0.5 line with
  | Error (Invalid_miter_limit _) -> () | _ -> failwith "accepted invalid miter limit");
  let expected = encoded corner in
  let workers = Array.init 4 (fun _ -> Domain.spawn (fun () -> encoded corner)) in
  Array.iter (fun worker -> assert (Domain.join worker = expected)) workers;
  print_endline "Raster2 deterministic stroke tessellation passed"
