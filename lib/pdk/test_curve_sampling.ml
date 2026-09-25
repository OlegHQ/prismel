open Pdk
open Prismel_math

let p2 x y = Vec2.create x y
let p3 x y z = Vec3.create x y z
let get = function Ok value -> value | Error error -> failwith (Error.to_string error)
let check condition message = if not condition then failwith message

let run () =
  let sample domains = Parallel.run ~domains (fun () ->
    Curve_sampling.catmull_rom2 ~resolution:2
      [p2 0. 0.; p2 2. 2.; p2 4. 0.] |> get) in
  let expected = [p2 0. 0.; p2 0.875 1.125; p2 2. 2.;
    p2 3.125 1.125; p2 4. 0.] in
  check (sample 1 = expected && sample 4 = expected)
    "Catmull-Rom 2D ordered samples or domain parity changed";
  let cubic = Curve_sampling.cubic2 ~resolution:2
      ~from_:(p2 0. 0.) ~control1:(p2 1. 2.)
      ~control2:(p2 3. 2.) ~to_:(p2 4. 0.) () |> get in
  check (cubic = [p2 0. 0.; p2 2. 1.5; p2 4. 0.])
    "cubic Bézier 2D ordered samples changed";
  let quadratic = Curve_sampling.quadratic2 ~resolution:2
      ~from_:(p2 0. 0.) ~control:(p2 1. 2.) ~to_:(p2 2. 0.) () |> get in
  check (quadratic = [p2 0. 0.; p2 1. 1.; p2 2. 0.])
    "quadratic Bézier 2D ordered samples changed";
  let cubic3 = Curve_sampling.cubic3 ~resolution:2
      ~from_:(p3 0. 0. 0.) ~control1:(p3 1. 0. 1.)
      ~control2:(p3 2. 0. 1.) ~to_:(p3 3. 0. 0.) () |> get in
  check (cubic3 = [p3 0. 0. 0.; p3 1.5 0. 0.75; p3 3. 0. 0.])
    "cubic Bézier 3D ordered samples changed";
  let quadratic3 = Curve_sampling.quadratic3 ~resolution:2
      ~from_:(p3 0. 0. 0.) ~control:(p3 1. 2. 3.)
      ~to_:(p3 2. 0. 0.) () |> get in
  check (quadratic3 = [p3 0. 0. 0.; p3 1. 1. 1.5; p3 2. 0. 0.])
    "quadratic Bézier 3D ordered samples changed";
  let controls = [p3 0. 0. 1.; p3 2. 2. 1.; p3 4. 0. 1.] in
  let run3 domains = Parallel.run ~domains (fun () ->
    Curve_sampling.catmull_rom3 ~resolution:2 controls |> get) in
  let expected3 = List.map (fun value -> p3 value.Vec2.x value.y 1.) expected in
  check (run3 1 = expected3 && run3 4 = expected3)
    "Catmull-Rom 3D ordered samples or domain parity changed";
  (match Curve_sampling.catmull_rom2 ~resolution:0 [p2 0. 0.; p2 1. 1.] with
   | Error _ -> () | Ok _ -> failwith "zero resolution succeeded");
  (match Curve_sampling.catmull_rom3 ~resolution:2 [p3 0. 0. 0.] with
   | Error _ -> () | Ok _ -> failwith "insufficient controls succeeded");
  (match Curve_sampling.catmull_rom3 ~resolution:2 ~tension:Float.nan controls with
   | Error _ -> () | Ok _ -> failwith "nonfinite tension succeeded");
  let cancel = Cancel.create () in
  Cancel.cancel cancel;
  (match Curve_sampling.cubic2 ~cancel ~resolution:2
      ~from_:(p2 0. 0.) ~control1:(p2 1. 1.)
      ~control2:(p2 2. 1.) ~to_:(p2 3. 0.) () with
   | Error error when Error.code error = "cancelled" -> ()
   | _ -> failwith "cancelled curve sampling succeeded");
  print_endline "PDK curve sampling fixtures passed"
