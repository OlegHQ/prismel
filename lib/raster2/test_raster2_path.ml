open Raster2.Path

let ok = function Ok value -> value | Error _ -> failwith "unexpected path error"
let p x y = { x; y }

let rectangle ~clockwise x0 y0 x1 y1 =
  let points =
    if clockwise then [| p x0 y0; p x0 y1; p x1 y1; p x1 y0 |]
    else [| p x0 y0; p x1 y0; p x1 y1; p x0 y1 |]
  in
  [| Move_to points.(0); Line_to points.(1); Line_to points.(2); Line_to points.(3); Close |]

let joined a b = Array.init (Array.length a + Array.length b) (fun i -> if i < Array.length a then a.(i) else b.(i - Array.length a))

let area mesh =
  let sum = ref 0. in
  for i = 0 to (Array.length mesh.indices / 3) - 1 do
    let a = mesh.vertices.(mesh.indices.(3 * i))
    and b = mesh.vertices.(mesh.indices.((3 * i) + 1))
    and c = mesh.vertices.(mesh.indices.((3 * i) + 2)) in
    sum := !sum +. abs_float (((b.x -. a.x) *. (c.y -. a.y) -. ((b.y -. a.y) *. (c.x -. a.x))) *. 0.5)
  done;
  !sum

let render rule commands =
  let mesh = ok (tessellate ~tolerance:0.01 ~fill_rule:rule (of_commands commands)) in
  Marshal.to_bytes mesh []

let () =
  let outer = rectangle ~clockwise:false 0. 0. 10. 10.
  and inner_same = rectangle ~clockwise:false 2. 2. 8. 8.
  and inner_opposite = rectangle ~clockwise:true 2. 2. 8. 8. in
  let even_odd = ok (tessellate ~tolerance:0.01 ~fill_rule:Even_odd (of_commands (joined outer inner_same))) in
  let non_zero_solid = ok (tessellate ~tolerance:0.01 ~fill_rule:Non_zero (of_commands (joined outer inner_same))) in
  let non_zero_hole = ok (tessellate ~tolerance:0.01 ~fill_rule:Non_zero (of_commands (joined outer inner_opposite))) in
  assert (area even_odd = 64.);
  assert (area non_zero_solid = 100.);
  assert (area non_zero_hole = 64.);
  let curve = of_commands [| Move_to (p 0. 0.); Cubic_to (p 0. 10., p 10. 10., p 10. 0.); Line_to (p 0. 0.); Close |] in
  let coarse = ok (flatten ~tolerance:2. curve) and fine = ok (flatten ~tolerance:0.05 curve) in
  assert (Array.length fine.(0) > Array.length coarse.(0));
  (match flatten ~tolerance:nan curve with Error (Invalid_tolerance _) -> () | _ -> failwith "accepted NaN tolerance");
  (match flatten ~tolerance:0. (of_commands [| Move_to (p 0. 0.) |]) with Error (Invalid_tolerance _) -> () | _ -> failwith "accepted zero tolerance");
  let expected = render Even_odd (joined outer inner_same) in
  let workers = Array.init 4 (fun _ -> Domain.spawn (fun () -> render Even_odd (joined outer inner_same))) in
  Array.iter (fun worker -> assert (Domain.join worker = expected)) workers;
  print_endline "Raster2 deterministic path tessellation passed"
