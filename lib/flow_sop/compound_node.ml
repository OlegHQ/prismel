let geometry_names ports = List.filter_map (fun (port : Network.interface_port) ->
  if port.ty = Flow.Port_type.Geometry then Some port.name else None) ports

let value_fields ports =
  let one (port : Network.interface_port) =
    let field ?vec3 name label kind default : Param.field_view = {
      name; label; description = None; folder = []; impact = Param.Cook;
      primary = true; vec3; kind; default; current = default} in
    match port.ty with
    | Flow.Port_type.Geometry -> []
    | Float ->
        let low, high = Option.value ~default:(-1., 1.) port.soft in
        let range : Param.float_range = Param.{soft_min = low; soft_max = high;
          hard_min = None; hard_max = None} in
        let default = match port.default with
          | Some (Port.Scalar (Param.Float_value _ as value)) ->
          value | _ -> Param.Float_value 0. in
        [field port.name port.label (Param.Floating_view range) default]
    | Int ->
        let low, high = Option.value ~default:(-10., 10.) port.soft in
        let range : Param.int_range = Param.{soft_min = int_of_float low; soft_max = int_of_float high;
          hard_min = None; hard_max = None} in
        let default = match port.default with
          | Some (Port.Scalar (Param.Int_value _ as value)) ->
          value | _ -> Param.Int_value 0 in
        [field port.name port.label (Param.Integer_view range) default]
    | Bool ->
        let default = match port.default with
          | Some (Port.Scalar (Param.Bool_value _ as value)) ->
          value | _ -> Param.Bool_value false in
        [field port.name port.label Param.Toggle_view default]
    | Vec3 ->
        let low, high = Option.value ~default:(-1., 1.) port.soft in
        let range : Param.float_range = Param.{soft_min = low; soft_max = high;
          hard_min = None; hard_max = None} in
        let defaults = match port.default with
          | Some (Port.Vector (x,y,z)) -> [x;y;z]
          | Some (Port.Scalar (Param.Float_value number)) ->
              [number; number; number]
          | Some (Port.Scalar (Param.Int_value number)) ->
              let number = float_of_int number in [number; number; number]
          | Some (Port.Scalar (Param.Bool_value value)) ->
              let number = if value then 1. else 0. in
              [number; number; number]
          | _ -> [0.; 0.; 0.] in
        List.map2 (fun index axis ->
          field ~vec3:(port.name, index) (port.name ^ "_" ^ axis)
            (port.label ^ " " ^ String.uppercase_ascii axis)
            (Param.Floating_view range)
            (Param.Float_value (List.nth defaults index)))
          [0;1;2] ["x"; "y"; "z"] in
  List.concat_map one ports

let key ~name = function
  | `Inputs -> "flow.inputs:" ^ name
  | `Outputs -> "flow.outputs:" ^ name
  | `Instance -> "flow.instance:" ^ name

let factory ~name ~role ~operation ~label ~fields ~output_fields slots =
  let key = key ~name role in
  let build inputs = Procedural.Node.Private.make ~label ~operation
    ~version:1 ~parameters:name ~cook_mode:Procedural.Node.Generic
    ~dependencies:Procedural.Context.Dependencies.static
    ~inputs:(List.filter_map Fun.id inputs |> Array.of_list)
    (fun ~node_id:_ _ _ -> Error (Procedural.Diagnostic.error
      ~code:"E_INTERFACE" "Compound interfaces must be flattened before cooking")) in
  match slots with
  | [] -> Procedural.Edit_graph.factory ~key ~operation ~label
      ~fields ~output_fields
      ~category:["Flow"] ~arity:0 (fun _ -> build [])
  | slots -> Procedural.Edit_graph.factory_slots ~key ~operation ~label
      ~fields ~output_fields
      ~category:["Flow"] ~slots
      ~inputs:(List.map (fun _ -> Procedural.Edit_graph.Optional) slots) build

let factories ~name ~inputs ~outputs = [
  factory ~name ~role:`Inputs ~operation:"flow_inputs" ~label:"Inputs"
    ~fields:[] ~output_fields:(value_fields inputs) [];
  factory ~name ~role:`Outputs ~operation:"flow_outputs" ~label:"Outputs"
    ~fields:(value_fields outputs) ~output_fields:[]
    (geometry_names outputs);
  factory ~name ~role:`Instance ~operation:"flow_compound" ~label:name
    ~fields:(value_fields inputs) ~output_fields:(value_fields outputs)
    (geometry_names inputs);
]
