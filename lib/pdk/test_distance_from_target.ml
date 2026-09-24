open Prismel
open Pdk

let fail message = raise (Failure message)
let check condition message = if not condition then fail message
let get_ok = function
  | Ok value -> value
  | Error error -> fail (Error.to_string error)
let close left right = abs_float (left -. right) <= 1e-10

let point_group name length predicate =
  Group.init ~grain:1 ~owner:Group.Point ~name length predicate

let float_attribute name geometry =
  match Geometry.find_attribute ~owner:Attribute.Point name geometry with
  | Some attribute ->
      (match Attribute.Private.storage attribute with
       | Attribute.Float values -> values
       | _ -> fail (name ^ " has wrong storage"))
  | None -> fail ("missing " ^ name)

let with_float name values geometry =
  let attribute = Attribute.create_owned ~owner:Attribute.Point ~name
      (Attribute.Float values) |> Result.get_ok in
  Geometry.with_attribute attribute geometry |> Result.get_ok

let same_float_array left right =
  Array.length left = Array.length right
  && let same = ref true in
     for index = 0 to Array.length left - 1 do
       if Int64.bits_of_float left.(index) <> Int64.bits_of_float right.(index)
       then same := false
     done;
     !same

let test_projections () =
  let source = Ops.points [|3., 4., 0.; 1., 2., 3.; 0., -2., 0.|] in
  let spherical = Ops.distance_from_target ~grain:1 source |> get_ok in
  let values = float_attribute "distance" spherical in
  check (close values.(0) 5. && close values.(1) (sqrt 14.)
      && close values.(2) 2.) "Distance From Target spherical distance";
  let cylindrical = Ops.distance_from_target ~grain:1
      ~projection:Ops.Distance_target_cylindrical ~direction:Vec3.unit_y source
      |> get_ok in
  let values = float_attribute "distance" cylindrical in
  check (close values.(0) 3. && close values.(1) (sqrt 10.)
      && close values.(2) 0.) "Distance From Target cylindrical distance";
  let planar = Ops.distance_from_target ~grain:1
      ~projection:Ops.Distance_target_planar ~direction:(Vec3.create 0. 2. 0.)
      ~radius:(Ops.Distance_fixed 4.) ~mask_attribute:"mask" source |> get_ok in
  check (same_float_array (float_attribute "distance" planar) [|4.; 2.; 2.|])
    "Distance From Target absolute planar distance";
  check (same_float_array (float_attribute "mask" planar) [|0.; 0.5; 0.5|])
    "Distance From Target fixed planar mask";
  let signed = Ops.distance_from_target ~grain:1
      ~projection:Ops.Distance_target_planar ~direction:Vec3.unit_y
      ~metric:Ops.Distance_target_signed ~radius:Ops.Distance_maximum
      ~mask_attribute:"mask" source |> get_ok in
  check (same_float_array (float_attribute "distance" signed) [|4.; 2.; -2.|])
    "Distance From Target signed planar distance";
  check (same_float_array (float_attribute "mask" signed) [|0.; 0.5; 0.5|])
    "Distance From Target signed magnitude mask"

let test_affected_and_mask_only () =
  let source = Ops.points [|0., 0., 0.; 2., 0., 0.; 4., 0., 0.|]
      |> with_float "distance" [|90.; 91.; 92.|]
      |> with_float "mask" [|80.; 81.; 82.|] in
  let affected = point_group "affected" 3 (fun point -> point <> 1) in
  let output = Ops.distance_from_target ~grain:1
      ~affected:(Ops.Selected_points affected)
      ~origin:(Vec3.create 1. 0. 0.) ~radius:Ops.Distance_maximum
      ~mask_attribute:"mask" source |> get_ok in
  check (same_float_array (float_attribute "distance" output) [|1.; 91.; 3.|])
    "Distance From Target affected distance preservation";
  let masks = float_attribute "mask" output in
  check (close masks.(0) (2. /. 3.) && masks.(1) = 81. && masks.(2) = 0.)
    "Distance From Target affected mask preservation";
  let only = Ops.distance_from_target ~grain:1 ~distance_attribute:None
      ~origin:(Vec3.create 1. 0. 0.) ~radius:(Ops.Distance_fixed 3.)
      ~falloff:Ops.Soft_cubic ~mask_attribute:"only" source |> get_ok in
  check (same_float_array (float_attribute "distance" only) [|90.; 91.; 92.|]
      && Array.length (float_attribute "only" only) = 3)
    "Distance From Target mask-only output";
  let zero = Ops.points [|0., 0., 0.; 1., 0., 1.|] in
  let zero = Ops.distance_from_target ~grain:1
      ~projection:Ops.Distance_target_planar ~direction:Vec3.unit_y
      ~distance_attribute:None ~mask_attribute:"mask" zero |> get_ok in
  check (same_float_array (float_attribute "mask" zero) [|1.; 1.|])
    "Distance From Target zero-extent maximum mask"

let expect_invalid work message = match work () with
  | Error error -> check (Error.code error = "invalid_distance") message
  | Ok _ -> fail (message ^ ": unexpectedly accepted")

let test_errors_cancellation_and_parallel () =
  let source = Ops.points [|0., 0., 0.; 1., 0., 0.|] in
  expect_invalid (fun () -> Ops.distance_from_target
      ~distance_attribute:None source) "Distance From Target no outputs";
  expect_invalid (fun () -> Ops.distance_from_target
      ~projection:Ops.Distance_target_spherical
      ~metric:Ops.Distance_target_signed source)
    "Distance From Target signed spherical";
  expect_invalid (fun () -> Ops.distance_from_target
      ~projection:Ops.Distance_target_cylindrical ~direction:Vec3.zero source)
    "Distance From Target zero axis";
  expect_invalid (fun () -> Ops.distance_from_target
      ~origin:(Vec3.create Float.nan 0. 0.) source)
    "Distance From Target non-finite origin";
  expect_invalid (fun () -> Ops.distance_from_target
      ~radius:(Ops.Distance_fixed 0.) source)
    "Distance From Target zero radius";
  let wrong = Attribute.create_owned ~owner:Attribute.Point ~name:"distance"
      (Attribute.Int [|1; 2|]) |> Result.get_ok in
  let wrong = Geometry.with_attribute wrong source |> Result.get_ok in
  expect_invalid (fun () -> Ops.distance_from_target wrong)
    "Distance From Target wrong output storage";
  let malformed = point_group "malformed" 3 (fun point -> point = 0) in
  expect_invalid (fun () -> Ops.distance_from_target
      ~affected:(Ops.Selected_points malformed) source)
    "Distance From Target malformed selection";
  let cancelled = Cancel.create () in
  Cancel.cancel cancelled;
  (match Ops.distance_from_target ~cancel:cancelled source with
   | Error error -> check (Error.code error = "cancelled")
       "Distance From Target cancellation code"
   | Ok _ -> fail "cancelled Distance From Target published geometry");
  let dense = Ops.grid ~columns:480 ~rows:300 ~size:20. () |> get_ok
      |> Ops.transform (Mat4.translation (Vec3.create 1.25 (-0.75) 2.5)) in
  let count = Geometry.point_count dense in
  let affected = point_group "affected" count (fun point -> point mod 7 <> 0) in
  let run projection metric domains = Parallel.run ~domains (fun () ->
      Ops.distance_from_target ~grain:257
        ~affected:(Ops.Selected_points affected) ~projection
        ~origin:(Vec3.create 0.5 (-1.25) 2.)
        ~direction:(Vec3.create 1. 2. (-3.)) ~metric
        ~falloff:Ops.Soft_cubic ~radius:Ops.Distance_maximum
        ~mask_attribute:"mask" dense |> get_ok) in
  List.iter (fun (projection, metric) ->
    let one = run projection metric 1 and four = run projection metric 4 in
    check (same_float_array (float_attribute "distance" one)
        (float_attribute "distance" four)
        && same_float_array (float_attribute "mask" one)
             (float_attribute "mask" four))
      "Distance From Target one/four-domain exactness")
    [Ops.Distance_target_spherical, Ops.Distance_target_absolute;
     Ops.Distance_target_cylindrical, Ops.Distance_target_absolute;
     Ops.Distance_target_planar, Ops.Distance_target_signed]

let () =
  test_projections ();
  test_affected_and_mask_only ();
  test_errors_cancellation_and_parallel ();
  print_endline "distance from target tests passed"
