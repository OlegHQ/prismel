open Pdk
open Prismel_math

let get = function Ok value -> value | Error error -> failwith (Error.to_string error)
let check condition message = if not condition then failwith message

let snapshot geometry =
  let positions = Geometry.positions geometry in
  let topology = Geometry.topology geometry in
  let normals = match Geometry.find_attribute ~owner:Attribute.Point "N" geometry with
    | Some value -> (match Attribute.storage value with
        | Attribute.Float3 values -> values
        | _ -> failwith "isosurface normals have wrong storage")
    | None -> failwith "isosurface normals missing" in
  (Array.init (Geometry.point_count geometry) (Packed.Float3.get positions),
   Array.init (Geometry.vertex_count geometry)
     (Topology.point_of_vertex topology),
   Array.init (Geometry.point_count geometry) (Packed.Float3.get normals))

let run () =
  let minimum = Vec3.create (-1.) (-1.) (-1.)
  and maximum = Vec3.create 1. 1. 1. in
  let sample domains = Parallel.run ~domains (fun () ->
    Iso_surface.extract ~resolution:(1, 1, 1) ~min:minimum ~max:maximum
      ~iso:0. ~field:(fun point -> point.Vec3.z) () |> get |> snapshot) in
  let one = sample 1 and four = sample 4 in
  check (one = four) "isosurface changed across one/four domains";
  let points, indices, normals = one in
  let p x y = x, y, 0. in
  let expected = [|p 0. 0.; p 1. 1.; p 1. 0.;
    p 0. 0.; p 0. 1.; p 1. 1.;
    p (-1.) 0.; p 0. 1.; p 0. 0.;
    p (-1.) 0.; p (-1.) 1.; p 0. 1.;
    p (-1.) 0.; p 0. 0.; p (-1.) (-1.);
    p (-1.) (-1.); p 0. 0.; p 0. (-1.);
    p 0. (-1.); p 0. 0.; p 1. 0.;
    p 0. (-1.); p 1. 0.; p 1. (-1.)|] in
  check (points = expected
    && indices = Array.init 24 Fun.id
    && normals = Array.make 24 (0., 0., -1.))
    "single-cell isosurface ordered baseline changed";
  let dense = Iso_surface.extract_dense ~resolution:(1, 1, 1)
      ~min:minimum ~max:maximum ~iso:0.
      ~field:(Iso_surface.Field.custom (fun xyz -> xyz.(2))) ()
      |> get |> snapshot in
  check (one = dense) "dense and boxed isosurfaces differ";
  (match Iso_surface.extract ~resolution:(0, 1, 1) ~min:minimum ~max:maximum
      ~iso:0. ~field:(fun _ -> 0.) () with
   | Error _ -> () | Ok _ -> failwith "zero resolution accepted");
  (match Iso_surface.extract ~resolution:(1, 1, 1) ~min:minimum ~max:maximum
      ~iso:0. ~field:(fun _ -> Float.nan) () with
   | Error _ -> () | Ok _ -> failwith "non-finite field accepted");
  let cancel = Cancel.create () in
  Cancel.cancel cancel;
  (match Iso_surface.extract ~cancel ~resolution:(1, 1, 1)
      ~min:minimum ~max:maximum ~iso:0. ~field:(fun _ -> 0.) () with
   | Error error when Error.code error = "cancelled" -> ()
   | _ -> failwith "cancelled isosurface succeeded");
  print_endline "PDK isosurface fixtures passed"
