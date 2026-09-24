open Prismel
open Pdk

let fail message = raise (Failure message)
let check condition message = if not condition then fail message
let get_ok = function
  | Ok value -> value
  | Error error -> fail (Error.to_string error)
let close left right = abs_float (left -. right) <= 1e-10

let line_with_free_point () =
  let positions = Packed.Float3.Private.of_owned_exn
      ~x:[|0.; 1.; 0.1; 3.; 4.|] ~y:(Array.make 5 0.)
      ~z:(Array.make 5 0.) in
  let topology = Topology.Builder.create ~point_count:5 ~vertex_capacity:4
      ~primitive_capacity:1 () in
  Topology.Builder.add_open_polyline topology [|0; 1; 3; 4|];
  Geometry.create ~positions ~topology:(Topology.Builder.freeze topology) ()
  |> Result.get_ok

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

let test_distance_and_masks () =
  let source = line_with_free_point () in
  let start = point_group "start" 5 (fun point -> point = 0) in
  let fixed = Ops.distance_along_geometry ~grain:1
      ~start:(Ops.Selected_points start) ~radius:(Ops.Distance_fixed 3.5)
      ~mask_attribute:"mask" source |> get_ok in
  let distance = float_attribute "distance" fixed
  and mask = float_attribute "mask" fixed in
  check (close distance.(0) 0. && close distance.(1) 1.
      && close distance.(2) (-1.) && close distance.(3) 3.
      && close distance.(4) 4.)
    "Distance Along Geometry raw edge distances";
  check (close mask.(0) 1. && close mask.(1) (1. -. (1. /. 3.5))
      && close mask.(2) 0. && close mask.(3) (1. -. (3. /. 3.5))
      && close mask.(4) 0.)
    "Distance Along Geometry fixed mask";
  let maximum = Ops.distance_along_geometry ~grain:1
      ~start:(Ops.Selected_points start) ~mask_attribute:"mask"
      ~falloff:Ops.Soft_quadratic source |> get_ok in
  let mask = float_attribute "mask" maximum in
  check (close mask.(0) 1. && close mask.(1) (1. -. (1. /. 16.))
      && close mask.(2) 0. && close mask.(3) (1. -. (9. /. 16.))
      && close mask.(4) 0.)
    "Distance Along Geometry maximum-distance mask";
  let mask_only = Ops.distance_along_geometry ~grain:1
      ~start:(Ops.Selected_points start) ~distance_attribute:None
      ~mask_attribute:"mask" ~radius:(Ops.Distance_fixed 3.5) source |> get_ok in
  check (Geometry.find_attribute ~owner:Attribute.Point "distance" mask_only = None)
    "Distance Along Geometry omitted raw output";
  check (same_float_array (float_attribute "mask" fixed)
      (float_attribute "mask" mask_only))
    "Distance Along Geometry bounded mask-only traversal"

let test_affected_and_promotion () =
  let source = line_with_free_point ()
      |> with_float "distance" [|90.; 91.; 92.; 93.; 94.|]
      |> with_float "mask" [|80.; 81.; 82.; 83.; 84.|] in
  let topology = Topology.Private.view (Geometry.topology source) in
  let vertices = Group.init ~grain:1 ~owner:Group.Vertex ~name:"first_vertex"
      (Geometry.vertex_count source) (fun vertex -> vertex = 0) in
  check (topology.vertex_points.(0) = 0) "distance test vertex fixture";
  let affected = point_group "affected" 5 (fun point -> point = 1 || point = 3) in
  let output = Ops.distance_along_geometry ~grain:1
      ~start:(Ops.Selected_vertices vertices)
      ~affected:(Ops.Selected_points affected)
      ~radius:(Ops.Distance_fixed 3.5) ~mask_attribute:"mask" source |> get_ok in
  let distance = float_attribute "distance" output
  and mask = float_attribute "mask" output in
  check (same_float_array distance [|90.; 1.; 92.; 3.; 94.|])
    "Distance Along Geometry affected raw preservation";
  check (close mask.(0) 80. && close mask.(1) (1. -. (1. /. 3.5))
      && close mask.(2) 82. && close mask.(3) (1. -. (3. /. 3.5))
      && close mask.(4) 84.)
    "Distance Along Geometry affected mask preservation";
  let isolated = Ops.points [|0., 0., 0.; 1., 0., 0.|] in
  let start = point_group "start" 2 (fun point -> point = 0) in
  let zero = Ops.distance_along_geometry ~grain:1
      ~start:(Ops.Selected_points start) ~distance_attribute:None
      ~mask_attribute:"mask" isolated |> get_ok in
  check (same_float_array (float_attribute "mask" zero) [|1.; 0.|])
    "Distance Along Geometry zero maximum and disconnected points";
  let empty = point_group "empty" 2 (fun _ -> false) in
  let empty_output = Ops.distance_along_geometry ~grain:1
      ~start:(Ops.Selected_points empty) ~mask_attribute:"mask" isolated
      |> get_ok in
  check (same_float_array (float_attribute "distance" empty_output) [|-1.; -1.|]
      && same_float_array (float_attribute "mask" empty_output) [|0.; 0.|])
    "Distance Along Geometry empty-start fast path";
  let all = point_group "all" 2 (fun _ -> true) in
  let all_output = Ops.distance_along_geometry ~grain:1
      ~start:(Ops.Selected_points all) ~mask_attribute:"mask" isolated |> get_ok in
  check (same_float_array (float_attribute "distance" all_output) [|0.; 0.|]
      && same_float_array (float_attribute "mask" all_output) [|1.; 1.|])
    "Distance Along Geometry complete-start fast path"

let expect_invalid work message = match work () with
  | Error error -> check (Error.code error = "invalid_distance") message
  | Ok _ -> fail (message ^ ": unexpectedly accepted")

let test_errors_cancellation_and_parallel () =
  let source = line_with_free_point () in
  let start = point_group "start" 5 (fun point -> point = 0) in
  let selected = Ops.Selected_points start in
  expect_invalid (fun () -> Ops.distance_along_geometry ~start:selected
      ~distance_attribute:None source) "Distance Along Geometry no outputs";
  expect_invalid (fun () -> Ops.distance_along_geometry ~start:selected
      ~distance_attribute:(Some "") source) "Distance Along Geometry blank output";
  expect_invalid (fun () -> Ops.distance_along_geometry ~start:selected
      ~distance_attribute:(Some " P ") source)
    "Distance Along Geometry reserved position output";
  expect_invalid (fun () -> Ops.distance_along_geometry ~start:selected
      ~distance_attribute:(Some "same") ~mask_attribute:"same" source)
    "Distance Along Geometry duplicate outputs";
  expect_invalid (fun () -> Ops.distance_along_geometry ~start:selected
      ~radius:(Ops.Distance_fixed 0.) source)
    "Distance Along Geometry zero radius";
  expect_invalid (fun () -> Ops.distance_along_geometry ~start:selected
      ~radius:(Ops.Distance_fixed Float.nan) source)
    "Distance Along Geometry non-finite radius";
  let wrong = Attribute.create_owned ~owner:Attribute.Point ~name:"distance"
      (Attribute.Int (Array.make 5 1)) |> Result.get_ok in
  let wrong = Geometry.with_attribute wrong source |> Result.get_ok in
  expect_invalid (fun () -> Ops.distance_along_geometry ~start:selected wrong)
    "Distance Along Geometry wrong existing storage";
  let malformed = point_group "malformed" 4 (fun point -> point = 0) in
  expect_invalid (fun () -> Ops.distance_along_geometry
      ~start:(Ops.Selected_points malformed) source)
    "Distance Along Geometry malformed selection";
  let nonfinite = Ops.points [|Float.nan, 0., 0.; 0., 0., 0.|] in
  let nonfinite_start = point_group "start" 2 (fun point -> point = 0) in
  expect_invalid (fun () -> Ops.distance_along_geometry
      ~start:(Ops.Selected_points nonfinite_start) nonfinite)
    "Distance Along Geometry non-finite positions";
  let cancelled = Cancel.create () in
  Cancel.cancel cancelled;
  (match Ops.distance_along_geometry ~cancel:cancelled ~start:selected source with
   | Error error -> check (Error.code error = "cancelled")
       "Distance Along Geometry cancellation code"
   | Ok _ -> fail "cancelled Distance Along Geometry published geometry");
  let dense = Ops.grid ~columns:400 ~rows:240 ~size:20. () |> get_ok in
  let width = 401 and count = Geometry.point_count dense in
  let dense_start = point_group "start" count (fun point ->
      point = (120 * width) + 200) in
  let affected = point_group "affected" count (fun point -> point mod 3 <> 0) in
  let run domains = Parallel.run ~domains (fun () ->
      Ops.distance_along_geometry ~grain:257
        ~start:(Ops.Selected_points dense_start)
        ~affected:(Ops.Selected_points affected)
        ~falloff:Ops.Soft_cubic ~radius:(Ops.Distance_fixed 4.)
        ~mask_attribute:"mask" dense |> get_ok) in
  let one = run 1 and four = run 4 in
  check (same_float_array (float_attribute "distance" one)
      (float_attribute "distance" four)
      && same_float_array (float_attribute "mask" one)
           (float_attribute "mask" four))
    "Distance Along Geometry one/four-domain exactness"

let () =
  test_distance_and_masks ();
  test_affected_and_promotion ();
  test_errors_cancellation_and_parallel ();
  print_endline "distance along geometry tests passed"
