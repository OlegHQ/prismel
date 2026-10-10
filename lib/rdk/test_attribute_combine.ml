open Rdk
open Rdk_test_support

let add storage ~owner ~name geometry =
  let attribute = Attribute.create_owned ~owner ~name storage |> Result.get_ok in
  Geometry.with_attribute attribute geometry |> Result.get_ok

let float_values ~owner name geometry =
  match Geometry.find_attribute ~owner name geometry with
  | Some attribute ->
      (match Attribute.Private.storage attribute with
       | Attribute.Float values -> values
       | _ -> fail ("wrong float storage for " ^ name))
  | None -> fail ("missing " ^ name)

let int_values ~owner name geometry =
  match Geometry.find_attribute ~owner name geometry with
  | Some attribute ->
      (match Attribute.Private.storage attribute with
       | Attribute.Int values -> values
       | _ -> fail ("wrong int storage for " ^ name))
  | None -> fail ("missing " ^ name)

let float3_values ~owner name geometry =
  match Geometry.find_attribute ~owner name geometry with
  | Some attribute ->
      (match Attribute.Private.storage attribute with
       | Attribute.Float3 values -> Packed.Float3.Private.view values
       | _ -> fail ("wrong float3 storage for " ^ name))
  | None -> fail ("missing " ^ name)

let float4_values ~owner name geometry =
  match Geometry.find_attribute ~owner name geometry with
  | Some attribute ->
      (match Attribute.Private.storage attribute with
       | Attribute.Float4 values -> Packed.Float4.Private.view values
       | _ -> fail ("wrong float4 storage for " ^ name))
  | None -> fail ("missing " ^ name)

let base_scalar () =
  Line_geometry.points [|(0.,0.,0.); (1.,0.,0.); (2.,0.,0.)|]
  |> add (Attribute.Float [|4.;4.;4.|]) ~owner:Attribute.Point ~name:"dest"
  |> add (Attribute.Float [|2.;2.;0.|]) ~owner:Attribute.Point ~name:"src"

let run () =
  print_endline "attribute combine tests passed"
