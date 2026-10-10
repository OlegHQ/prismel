open Rays
open Rdk

let fail message = failwith message
let get_ok = function Ok value -> value | Error error ->
  fail (Error.to_string error)
let get_string_ok = function Ok value -> value | Error message -> fail message
let near ?(epsilon = 1e-11) left right = abs_float (left -. right) <= epsilon

let add attribute geometry = Geometry.with_attribute attribute geometry |> get_string_ok
let add_group group geometry = Geometry.with_group group geometry |> get_string_ok

let float_attribute ~owner name values =
  Attribute.create_owned ~name ~owner (Attribute.Float values) |> get_string_ok

let text_attribute ~owner name values =
  Attribute.create_owned ~name ~owner (Attribute.Text values) |> get_string_ok

let float2_attribute ~owner name x y =
  let values = Packed.Float2.of_owned ~x ~y |> get_string_ok in
  Attribute.create_owned ~name ~owner (Attribute.Float2 values) |> get_string_ok

let float4_attribute ~owner name x y z w =
  let values = Packed.Float4.of_owned ~x ~y ~z ~w |> get_string_ok in
  Attribute.create_owned ~name ~owner (Attribute.Float4 values) |> get_string_ok

let attribute geometry owner name =
  match Geometry.find_attribute ~owner name geometry with
  | Some attribute -> attribute
  | None -> fail ("missing attribute " ^ name)

let point_float geometry name = match Attribute.Private.storage
    (attribute geometry Attribute.Point name) with
  | Attribute.Float values -> values
  | _ -> fail (name ^ " is not point float")

let point_int geometry name = match Attribute.Private.storage
    (attribute geometry Attribute.Point name) with
  | Attribute.Int values -> values
  | _ -> fail (name ^ " is not point int")

let point_text geometry name = match Attribute.Private.storage
    (attribute geometry Attribute.Point name) with
  | Attribute.Text values -> values
  | _ -> fail (name ^ " is not point text")

let point_float2 geometry name = match Attribute.Private.storage
    (attribute geometry Attribute.Point name) with
  | Attribute.Float2 values -> Packed.Float2.Private.view values
  | _ -> fail (name ^ " is not point float2")

let point_float3 geometry name = match Attribute.Private.storage
    (attribute geometry Attribute.Point name) with
  | Attribute.Float3 values -> Packed.Float3.Private.view values
  | _ -> fail (name ^ " is not point float3")

let point_float4 geometry name = match Attribute.Private.storage
    (attribute geometry Attribute.Point name) with
  | Attribute.Float4 values -> Packed.Float4.Private.view values
  | _ -> fail (name ^ " is not point float4")

let point_int_array geometry name = match Attribute.Private.storage
    (attribute geometry Attribute.Point name) with
  | Attribute.Int_array values -> Packed.Int_array.Private.view values
  | _ -> fail (name ^ " is not point int array")

let point_float_array geometry name = match Attribute.Private.storage
    (attribute geometry Attribute.Point name) with
  | Attribute.Float_array values -> Packed.Float_array.Private.view values
  | _ -> fail (name ^ " is not point float array")

let expect_code code = function
  | Error error when String.equal (Error.code error) code -> ()
  | Error error -> fail (Printf.sprintf "expected %s, received %s" code
      (Error.to_string error))
  | Ok _ -> fail ("expected " ^ code)

let check_parallel_scale () =
  let source = Plane_generators.grid ~columns:300 ~rows:200 ~size:20. () |> get_ok in
  let count = Geometry.point_count source in
  let density = float_attribute ~owner:Attribute.Point "density"
      (Array.init count (fun point -> 0.1 +. float_of_int (point mod 97) /. 97.)) in
  let source = add density source in
  let scatter domains = Parallel.run ~domains (fun () ->
    Scatter.run ~grain:1_009 ~count:100_000 ~seed:1_337
      ~density:(Scatter.density ~owner:Attribute.Point "density")
      ~point_pattern:"N" ~source_primitive_attribute:"primitive"
      ~source_vertex_numbers_attribute:"vertices"
      ~source_vertex_weights_attribute:"weights" source |> get_ok) in
  let one = scatter 1 and many = scatter 4 in
  let one_positions = Packed.Float3.Private.view (Geometry.positions one)
  and many_positions = Packed.Float3.Private.view (Geometry.positions many) in
  if one_positions.x <> many_positions.x || one_positions.y <> many_positions.y
      || one_positions.z <> many_positions.z
      || point_int one "id" <> point_int many "id"
      || point_int one "primitive" <> point_int many "primitive"
      || (point_int_array one "vertices").values
         <> (point_int_array many "vertices").values
      || (point_float_array one "weights").values
         <> (point_float_array many "weights").values
      || (point_float3 one "N").x <> (point_float3 many "N").x then
    fail "Scatter differs between one and four domains"

let run () =
  check_parallel_scale ();
  print_endline "scatter tests passed"
