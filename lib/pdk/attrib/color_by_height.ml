open Prismel_math

let get_ok = function Ok value -> value | Error message -> invalid_arg message

let run_raw ?cancel ?(grain = 16_384) ~low ~high geometry =
  if grain <= 0 then invalid_arg "Pdk.Ops.color_by_height: grain must be positive";
  let positions = Packed.Float3.Private.view (Geometry.positions geometry) in
  let count = Array.length positions.y in
  let minimum = ref infinity and maximum = ref neg_infinity in
  for index = 0 to count - 1 do
    if index land 16383 = 0 then Cancel.check_opt cancel;
    let value = positions.y.(index) in
    if value < !minimum then minimum := value;
    if value > !maximum then maximum := value
  done;
  let lr, lg, lb, la = low and hr, hg, hb, ha = high in
  let r = Array.make count lr and g = Array.make count lg
  and b = Array.make count lb and a = Array.make count la in
  let extent = !maximum -. !minimum in
  if count > 0 then Parallel.for_ ~chunk_size:grain ~start:0 ~finish:(count - 1)
      (fun index ->
        if index land 4095 = 0 then Cancel.check_opt cancel;
        let t = if extent <= 1e-15 then 0. else (positions.y.(index) -. !minimum) /. extent in
        r.(index) <- lr +. ((hr -. lr) *. t);
        g.(index) <- lg +. ((hg -. lg) *. t);
        b.(index) <- lb +. ((hb -. lb) *. t);
        a.(index) <- la +. ((ha -. la) *. t));
  let values = Packed.Float4.of_owned ~x:r ~y:g ~z:b ~w:a |> get_ok in
  let attribute = Attribute.create_key_owned
      (Attribute.color ~owner:Attribute.Point) values |> get_ok in
  Geometry.with_attribute attribute geometry

let run ?cancel ?grain ~low ~high geometry =
  Error.guard ~operation:"color_by_height" ~code:"invalid_geometry" (fun () ->
    run_raw ?cancel ?grain ~low ~high geometry)
