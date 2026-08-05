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

let primitive_group name length predicate =
  Group.init ~grain:1 ~owner:Group.Primitive ~name length predicate

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

let test_point_distance () =
  let source = Ops.points [|0., 0., 0.; 1., 0., 0.; 3., 0., 0.|]
  and reference = Ops.points [|0., 1., 0.|] in
  let fixed = Ops.distance_from_geometry ~grain:1
      ~reference_kind:Ops.Distance_reference_points
      ~radius:(Ops.Distance_fixed 2.) ~mask_attribute:"mask"
      ~reference source |> get_ok in
  let distance = float_attribute "distance" fixed
  and mask = float_attribute "mask" fixed in
  check (close distance.(0) 1. && close distance.(1) (sqrt 2.)
      && close distance.(2) (sqrt 10.))
    "Distance From Geometry point distances";
  check (close mask.(0) 0.5 && close mask.(1) (1. -. sqrt 2. /. 2.)
      && close mask.(2) 0.)
    "Distance From Geometry point fixed mask";
  let maximum = Ops.distance_from_geometry ~grain:1
      ~reference_kind:Ops.Distance_reference_points
      ~falloff:Ops.Soft_quadratic ~mask_attribute:"mask"
      ~reference source |> get_ok in
  let mask = float_attribute "mask" maximum in
  check (close mask.(0) 0.9 && close mask.(1) 0.8 && close mask.(2) 0.)
    "Distance From Geometry point maximum mask";
  let mask_only = Ops.distance_from_geometry ~grain:1
      ~reference_kind:Ops.Distance_reference_points
      ~distance_attribute:None ~radius:(Ops.Distance_fixed 2.)
      ~mask_attribute:"mask" ~reference source |> get_ok in
  check (Geometry.find_attribute ~owner:Attribute.Point "distance" mask_only = None
      && same_float_array (float_attribute "mask" fixed)
           (float_attribute "mask" mask_only))
    "Distance From Geometry bounded point mask-only query"

let test_surface_and_affected () =
  let source = Ops.points [|0., 1., 0.; 1., 2., 1.; -1., 3., -1.|]
      |> with_float "distance" [|90.; 91.; 92.|]
      |> with_float "mask" [|80.; 81.; 82.|] in
  let reference = Ops.grid ~columns:2 ~rows:2 ~size:10. () |> get_ok in
  let affected = point_group "affected" 3 (fun point -> point <> 1) in
  let output = Ops.distance_from_geometry ~grain:1
      ~affected:(Ops.Selected_points affected)
      ~reference_kind:Ops.Distance_reference_primitives
      ~radius:Ops.Distance_maximum ~mask_attribute:"mask"
      ~reference source |> get_ok in
  check (same_float_array (float_attribute "distance" output) [|1.; 91.; 3.|])
    "Distance From Geometry affected surface distance preservation";
  let mask = float_attribute "mask" output in
  check (close mask.(0) (2. /. 3.) && mask.(1) = 81. && close mask.(2) 0.)
    "Distance From Geometry affected maximum mask preservation";
  let all_primitives = primitive_group "surface"
      (Geometry.primitive_count reference) (fun _ -> true) in
  let selected = Ops.distance_from_geometry ~grain:1
      ~reference_selection:(Ops.Selected_primitives all_primitives)
      ~reference_kind:Ops.Distance_reference_primitives
      ~reference source |> get_ok in
  check (same_float_array (float_attribute "distance" selected) [|1.; 2.; 3.|])
    "Distance From Geometry primitive reference selection";
  let empty = point_group "empty" (Geometry.point_count reference) (fun _ -> false) in
  let missed = Ops.distance_from_geometry ~grain:1
      ~reference_selection:(Ops.Selected_points empty)
      ~reference_kind:Ops.Distance_reference_points ~mask_attribute:"mask"
      ~reference source |> get_ok in
  check (same_float_array (float_attribute "distance" missed) [|-1.; -1.; -1.|]
      && same_float_array (float_attribute "mask" missed) [|0.; 0.; 0.|])
    "Distance From Geometry empty reference"

let test_distance_only_indexes () =
  let queries = Ops.points [|0., 0., 0.; 1., 2., 0.; 4., 0., 0.|]
      |> Geometry.positions in
  let points = Packed.Float3.Private.of_owned_exn ~x:[|0.; 3.|]
      ~y:[|1.; 0.|] ~z:[|0.; 0.|] in
  let point_index = Spatial_index.create ~grain:1 points |> get_ok in
  let indices = Array.make 3 (-1) and generic = Array.make 3 Float.infinity
  and counts = Array.make 3 0 and specialized = Array.make 3 Float.infinity in
  Spatial_index.Private.nearest_k_many_into ~grain:1 point_index ~queries
    ~max_distance_squared:Float.infinity ~capacity:1 ~indices
    ~distances_squared:generic ~counts;
  Spatial_index.Private.nearest_distances_many_into ~grain:1 point_index ~queries
    ~max_distance_squared:Float.infinity ~distances_squared:specialized;
  check (same_float_array generic specialized)
    "distance-only point index matches provenance query";
  let bounded = Array.make 3 0. in
  Spatial_index.Private.nearest_distances_many_into ~grain:1 point_index ~queries
    ~max_distance_squared:0.01 ~distances_squared:bounded;
  check (Array.for_all (fun value -> value = Float.infinity) bounded)
    "distance-only point index bounded miss sentinel";
  let surface = Ops.grid ~columns:2 ~rows:2 ~size:10. () |> get_ok in
  let surface_index = Surface_index.create ~grain:1 surface |> get_ok in
  let primitives = Array.make 3 (-1) and triangles = Array.make 3 (-1)
  and a = Array.make 3 0. and b = Array.make 3 0. and c = Array.make 3 0.
  and generic = Array.make 3 Float.infinity
  and specialized = Array.make 3 Float.infinity in
  Surface_index.Private.closest_many_into ~grain:1 surface_index ~queries
    ~max_distance_squared:Float.infinity ~primitives ~triangles
    ~barycentric_a:a ~barycentric_b:b ~barycentric_c:c
    ~distances_squared:generic;
  Surface_index.Private.closest_distances_many_into ~grain:1 surface_index
    ~queries ~max_distance_squared:Float.infinity
    ~distances_squared:specialized;
  check (same_float_array generic specialized)
    "distance-only surface index matches provenance query";
  let bounded = Array.make 3 0. in
  Surface_index.Private.closest_distances_many_into ~grain:1 surface_index
    ~queries ~max_distance_squared:0.01 ~distances_squared:bounded;
  check (bounded.(1) = Float.infinity)
    "distance-only surface index bounded miss sentinel"

let expect_invalid work message = match work () with
  | Error error -> check (Error.code error = "invalid_distance") message
  | Ok _ -> fail (message ^ ": unexpectedly accepted")

let test_errors_cancellation_and_parallel () =
  let source = Ops.points [|0., 0., 0.; 1., 0., 0.|]
  and reference = Ops.points [|0., 1., 0.|] in
  expect_invalid (fun () -> Ops.distance_from_geometry
      ~distance_attribute:None ~reference source)
    "Distance From Geometry no outputs";
  expect_invalid (fun () -> Ops.distance_from_geometry
      ~distance_attribute:(Some " P ") ~reference source)
    "Distance From Geometry reserved output";
  expect_invalid (fun () -> Ops.distance_from_geometry
      ~distance_attribute:(Some "same") ~mask_attribute:"same"
      ~reference source) "Distance From Geometry duplicate outputs";
  expect_invalid (fun () -> Ops.distance_from_geometry
      ~radius:(Ops.Distance_fixed 0.) ~reference source)
    "Distance From Geometry zero radius";
  let wrong = Attribute.create_owned ~owner:Attribute.Point ~name:"distance"
      (Attribute.Int [|1; 2|]) |> Result.get_ok in
  let wrong = Geometry.with_attribute wrong source |> Result.get_ok in
  expect_invalid (fun () -> Ops.distance_from_geometry ~reference wrong)
    "Distance From Geometry wrong output storage";
  let malformed = point_group "malformed" 3 (fun point -> point = 0) in
  expect_invalid (fun () -> Ops.distance_from_geometry
      ~affected:(Ops.Selected_points malformed) ~reference source)
    "Distance From Geometry malformed source selection";
  let nonfinite = Ops.points [|Float.nan, 0., 0.|] in
  expect_invalid (fun () -> Ops.distance_from_geometry ~reference nonfinite)
    "Distance From Geometry non-finite source position";
  let curve = Ops.polyline [|0., 0., 0.; 1., 0., 0.|] |> get_ok in
  expect_invalid (fun () -> Ops.distance_from_geometry
      ~reference_kind:Ops.Distance_reference_primitives ~reference:curve source)
    "Distance From Geometry curve surface reference";
  let cancelled = Cancel.create () in
  Cancel.cancel cancelled;
  (match Ops.distance_from_geometry ~cancel:cancelled ~reference source with
   | Error error -> check (Error.code error = "cancelled")
       "Distance From Geometry cancellation code"
   | Ok _ -> fail "cancelled Distance From Geometry published geometry");
  let dense = Ops.grid ~columns:320 ~rows:200 ~size:20. () |> get_ok
      |> Ops.transform (Mat4.translation (Vec3.create 0. 1.5 0.)) in
  let surface = Ops.uv_sphere ~rings:80 ~segments:120 ~radius:5. () |> get_ok in
  let count = Geometry.point_count dense in
  let affected = point_group "affected" count (fun point -> point mod 3 <> 0) in
  let run kind domains = Parallel.run ~domains (fun () ->
      Ops.distance_from_geometry ~grain:257
        ~affected:(Ops.Selected_points affected) ~reference_kind:kind
        ~falloff:Ops.Soft_cubic ~radius:(Ops.Distance_fixed 4.)
        ~mask_attribute:"mask" ~reference:surface dense |> get_ok) in
  List.iter (fun kind ->
    let one = run kind 1 and four = run kind 4 in
    check (same_float_array (float_attribute "distance" one)
        (float_attribute "distance" four)
        && same_float_array (float_attribute "mask" one)
             (float_attribute "mask" four))
      "Distance From Geometry one/four-domain exactness")
    [Ops.Distance_reference_points; Ops.Distance_reference_primitives]

let () =
  test_point_distance ();
  test_surface_and_affected ();
  test_distance_only_indexes ();
  test_errors_cancellation_and_parallel ();
  print_endline "distance from geometry tests passed"
