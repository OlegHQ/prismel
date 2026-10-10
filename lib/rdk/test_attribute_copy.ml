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

let text_values ~owner name geometry =
  match Geometry.find_attribute ~owner name geometry with
  | Some attribute ->
      (match Attribute.Private.storage attribute with
       | Attribute.Text values -> values
       | _ -> fail ("wrong text storage for " ^ name))
  | None -> fail ("missing " ^ name)

let float2_values ~owner name geometry =
  match Geometry.find_attribute ~owner name geometry with
  | Some attribute ->
      (match Attribute.Private.storage attribute with
       | Attribute.Float2 values -> Packed.Float2.Private.view values
       | _ -> fail ("wrong float2 storage for " ^ name))
  | None -> fail ("missing " ^ name)

let float4_values ~owner name geometry =
  match Geometry.find_attribute ~owner name geometry with
  | Some attribute ->
      (match Attribute.Private.storage attribute with
       | Attribute.Float4 values -> Packed.Float4.Private.view values
       | _ -> fail ("wrong float4 storage for " ^ name))
  | None -> fail ("missing " ^ name)

let run () =
  print_endline "attribute copy tests passed"
