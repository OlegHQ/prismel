open Prismel

type operation =
  | Composite_mean
  | Composite_maximum
  | Composite_minimum
  | Composite_over
  | Composite_under

type input = { geometry : Geometry.t; weight : float }

type kind = Scalar | Vector2 | Vector3 | Vector4 | Position

type plan = {
  owner : Attribute.owner;
  name : string;
  kind : kind;
  sources : float array array option array;
  output : float array array;
}

type owner_plan = {
  owner : Attribute.owner;
  count : int;
  pattern : Attribute_pattern.t;
}

type denominator = Constant_denominator of float | Element_denominator of float array

exception Composite_error of string
let fail message = raise (Composite_error message)

let input ~weight geometry : input =
  if not (Float.is_finite weight) then
    invalid_arg "Pdk.Ops.attribute_composite_input: non-finite weight";
  { geometry; weight }

let owner_name = function
  | Attribute.Point -> "point"
  | Attribute.Vertex -> "vertex"
  | Attribute.Primitive -> "primitive"
  | Attribute.Detail -> "detail"

let owner_count geometry = function
  | Attribute.Point -> Geometry.point_count geometry
  | Attribute.Vertex -> Geometry.vertex_count geometry
  | Attribute.Primitive -> Geometry.primitive_count geometry
  | Attribute.Detail -> 1

let kind_name = function
  | Scalar -> "float"
  | Vector2 -> "float2"
  | Vector3 | Position -> "float3"
  | Vector4 -> "float4"

let kind_width = function
  | Scalar -> 1
  | Vector2 -> 2
  | Vector3 | Position -> 3
  | Vector4 -> 4

let kind_equal left right = match left, right with
  | Scalar, Scalar | Vector2, Vector2 | Vector3, Vector3
  | Vector4, Vector4 | Position, Position -> true
  | Scalar, (Vector2 | Vector3 | Vector4 | Position)
  | Vector2, (Scalar | Vector3 | Vector4 | Position)
  | Vector3, (Scalar | Vector2 | Vector4 | Position)
  | Vector4, (Scalar | Vector2 | Vector3 | Position)
  | Position, (Scalar | Vector2 | Vector3 | Vector4) -> false

let storage_kind = function
  | Attribute.Float _ -> Some Scalar
  | Attribute.Float2 _ -> Some Vector2
  | Attribute.Float3 _ -> Some Vector3
  | Attribute.Float4 _ -> Some Vector4
  | Attribute.Int _ | Attribute.Text _ | Attribute.Int_array _
  | Attribute.Float_array _ -> None

let planes_of_storage = function
  | Attribute.Float values -> Some [|values|]
  | Attribute.Float2 values ->
      let values = Packed.Float2.Private.view values in
      Some [|values.x; values.y|]
  | Attribute.Float3 values ->
      let values = Packed.Float3.Private.view values in
      Some [|values.x; values.y; values.z|]
  | Attribute.Float4 values ->
      let values = Packed.Float4.Private.view values in
      Some [|values.x; values.y; values.z; values.w|]
  | Attribute.Int _ | Attribute.Text _ | Attribute.Int_array _
  | Attribute.Float_array _ -> None

let position_planes geometry =
  let values = Packed.Float3.Private.view (Geometry.positions geometry) in
  [|values.x; values.y; values.z|]

let compile_pattern label source =
  match Attribute_pattern.compile source with
  | Ok pattern -> pattern
  | Error message -> fail ("Attribute Composite " ^ label ^ ": " ^ message)

let owner_plans ~detail_attributes ~primitive_attributes ~point_attributes
    ~vertex_attributes geometry =
  [| { owner = Attribute.Detail; count = 1;
       pattern = compile_pattern "detail pattern" detail_attributes };
     { owner = Attribute.Primitive;
       count = Geometry.primitive_count geometry;
       pattern = compile_pattern "primitive pattern" primitive_attributes };
     { owner = Attribute.Point; count = Geometry.point_count geometry;
       pattern = compile_pattern "point pattern" point_attributes };
     { owner = Attribute.Vertex; count = Geometry.vertex_count geometry;
       pattern = compile_pattern "vertex pattern" vertex_attributes } |]

let append_unique seen names name =
  if not (Hashtbl.mem seen name) then begin
    Hashtbl.add seen name ();
    names := name :: !names
  end

let selected_names ~allow_position owner_plan geometries =
  let seen = Hashtbl.create 16 and names = ref [] in
  if allow_position && owner_plan.owner = Attribute.Point
      && Attribute_pattern.matches owner_plan.pattern "P" then
    append_unique seen names "P";
  Array.iter (fun geometry ->
    List.iter (fun attribute ->
      let name = Attribute.name attribute in
      if Attribute.owner attribute = owner_plan.owner
          && Attribute_pattern.matches owner_plan.pattern name
          && Option.is_some (storage_kind (Attribute.Private.storage attribute))
      then append_unique seen names name)
      (Geometry.attributes geometry)) geometries;
  List.rev !names

let source_for ~input_index ~owner ~count ~name ~kind geometry =
  if owner = Attribute.Point && String.equal name "P" then begin
    if owner_count geometry owner <> count then fail (Printf.sprintf
        "Attribute Composite input %d point count differs from the first input"
        input_index);
    Some (position_planes geometry)
  end else
    match Geometry.find_attribute ~owner name geometry with
    | None -> None
    | Some attribute ->
        if Attribute.length attribute <> count then fail (Printf.sprintf
            "Attribute Composite input %d %s attribute %S has incompatible cardinality"
            input_index (owner_name owner) name);
        let storage = Attribute.Private.storage attribute in
        (match storage_kind storage, planes_of_storage storage with
         | Some actual, Some planes when kind_equal kind actual -> Some planes
         | Some actual, Some _ -> fail (Printf.sprintf
             "Attribute Composite input %d %s attribute %S is %s, expected %s"
             input_index (owner_name owner) name (kind_name actual)
             (kind_name kind))
         | None, None -> fail (Printf.sprintf
             "Attribute Composite input %d %s attribute %S is not a fixed-width floating attribute"
             input_index (owner_name owner) name)
         | _ -> assert false)

let first_kind owner name geometries =
  if owner = Attribute.Point && String.equal name "P" then Position
  else
    let found = ref None and index = ref 0 in
    while !index < Array.length geometries && !found = None do
      match Geometry.find_attribute ~owner name geometries.(!index) with
      | None -> incr index
      | Some attribute ->
          (match storage_kind (Attribute.Private.storage attribute) with
           | Some kind -> found := Some kind
           | None -> incr index)
    done;
    match !found with Some kind -> kind | None -> assert false

let make_plans ~allow_position owner_plans geometries =
  let plans = ref [] in
  Array.iter (fun owner_plan ->
    List.iter (fun name ->
      let kind = first_kind owner_plan.owner name geometries in
      let sources = Array.mapi (fun input_index geometry ->
        source_for ~input_index ~owner:owner_plan.owner ~count:owner_plan.count
          ~name ~kind geometry) geometries in
      plans := { owner = owner_plan.owner; name; kind; sources;
        output = Array.init (kind_width kind)
          (fun _ -> Array.make owner_plan.count 0.) } :: !plans)
      (selected_names ~allow_position owner_plan geometries)) owner_plans;
  Array.of_list (List.rev !plans)

let alpha_planes ~used ~alpha_attribute owner_plans geometries =
  Array.mapi (fun owner_index owner_plan ->
    if not used.(owner_index) then Array.make (Array.length geometries) None
    else Array.mapi (fun input_index geometry ->
      match alpha_attribute with
      | None -> None
      | Some name ->
          (match Geometry.find_attribute ~owner:owner_plan.owner name geometry with
           | None -> None
           | Some attribute ->
               if Attribute.length attribute <> owner_plan.count then
                 fail (Printf.sprintf
                   "Attribute Composite input %d %s alpha %S has incompatible cardinality"
                   input_index (owner_name owner_plan.owner) name);
               match Attribute.Private.storage attribute with
               | Attribute.Float values -> Some values
               | _ -> fail (Printf.sprintf
                   "Attribute Composite input %d %s alpha %S must be a scalar float attribute"
                   input_index (owner_name owner_plan.owner) name))) geometries)
    owner_plans

let owner_slot = function
  | Attribute.Detail -> 0
  | Attribute.Primitive -> 1
  | Attribute.Point -> 2
  | Attribute.Vertex -> 3

let parallel_for ?cancel ~grain count work =
  if count > 0 then
    Parallel.for_ ~chunk_size:grain ~start:0 ~finish:(count - 1)
      (fun element ->
        if element land 4095 = 0 then Cancel.check_opt cancel;
        work element)

let record_first_bad bad element =
  let current = ref (Atomic.get bad) in
  while element < !current
      && not (Atomic.compare_and_set bad !current element) do
    current := Atomic.get bad
  done

let validate_plane ?cancel ~grain ~label values =
  let bad = Atomic.make max_int in
  parallel_for ?cancel ~grain (Array.length values) (fun element ->
    if not (Float.is_finite values.(element)) then record_first_bad bad element);
  let element = Atomic.get bad in
  if element <> max_int then fail (Printf.sprintf
      "Attribute Composite %s is non-finite at element %d" label element)

let validate_alpha ?cancel ~grain alpha =
  Array.iteri (fun owner_index inputs ->
    Array.iteri (fun input_index values -> match values with
      | None -> ()
      | Some values -> validate_plane ?cancel ~grain
          ~label:(Printf.sprintf "input %d %s alpha"
            input_index (owner_name [|Attribute.Detail; Attribute.Primitive;
              Attribute.Point; Attribute.Vertex|].(owner_index))) values) inputs)
    alpha

let finish_plan (plan : plan) bad_source bad_output =
  let source = Atomic.get bad_source and output = Atomic.get bad_output in
  if source <> max_int then fail (Printf.sprintf
      "Attribute Composite input %s attribute %S is non-finite at element %d"
      (owner_name plan.owner) plan.name source);
  if output <> max_int then fail (Printf.sprintf
      "Attribute Composite output %s attribute %S is non-finite at element %d"
      (owner_name plan.owner) plan.name output)

let denominator_for_owner ?cancel ~grain ~owner ~count weights alpha =
  if Array.for_all Option.is_none alpha then begin
    let denominator = Array.fold_left ( +. ) 0. weights in
    if not (Float.is_finite denominator) then fail
        ("Attribute Composite mean denominator is non-finite for "
          ^ owner_name owner ^ " attributes");
    Constant_denominator denominator
  end
  else begin
    let values = Array.make count 0. in
    Array.iteri (fun input_index weight -> match alpha.(input_index) with
      | None -> parallel_for ?cancel ~grain count (fun element ->
          values.(element) <- values.(element) +. weight)
      | Some mask -> parallel_for ?cancel ~grain count (fun element ->
          values.(element) <- values.(element) +. (weight *. mask.(element))))
      weights;
    validate_plane ?cancel ~grain
      ~label:("mean denominator for " ^ owner_name owner ^ " attributes") values;
    Element_denominator values
  end

let compute_mean ?cancel ~grain weights alpha denominators (plan : plan) =
  let count = Array.length plan.output.(0)
  and masks = alpha.(owner_slot plan.owner)
  and bad_source = Atomic.make max_int and bad_output = Atomic.make max_int in
  Array.iteri (fun input_index source -> match source with
    | None -> ()
    | Some source ->
        let weight = weights.(input_index) and mask = masks.(input_index) in
        Array.iteri (fun component values ->
          let output = plan.output.(component) in
          match mask with
          | None -> parallel_for ?cancel ~grain count (fun element ->
              let value = values.(element) in
              if not (Float.is_finite value) then record_first_bad bad_source element
              else
                let value = output.(element) +. (value *. weight) in
                if Float.is_finite value then output.(element) <- value
                else record_first_bad bad_output element)
          | Some mask -> parallel_for ?cancel ~grain count (fun element ->
              let value = values.(element) in
              if not (Float.is_finite value) then record_first_bad bad_source element
              else
                let value = output.(element) +.
                    (value *. weight *. mask.(element)) in
                if Float.is_finite value then output.(element) <- value
                else record_first_bad bad_output element))
          source) plan.sources;
  let denominator = Option.get denominators.(owner_slot plan.owner) in
  Array.iter (fun output -> parallel_for ?cancel ~grain count (fun element ->
    let divisor = match denominator with
      | Constant_denominator value -> value
      | Element_denominator values -> values.(element) in
    let value = if divisor = 0. then 0. else output.(element) /. divisor in
    if Float.is_finite value then output.(element) <- value
    else record_first_bad bad_output element)) plan.output;
  finish_plan plan bad_source bad_output

let initialize_weighted ?cancel ~grain ~bad_source ~bad_output weights masks
    (plan : plan) =
  let count = Array.length plan.output.(0) in
  match plan.sources.(0) with
  | None -> ()
  | Some source ->
      let weight = weights.(0) and mask = masks.(0) in
      Array.iteri (fun component values ->
        let output = plan.output.(component) in
        match mask with
        | None -> parallel_for ?cancel ~grain count (fun element ->
            let source = values.(element) in
            if not (Float.is_finite source) then record_first_bad bad_source element
            else
              let value = source *. weight in
              if Float.is_finite value then output.(element) <- value
              else record_first_bad bad_output element)
        | Some mask -> parallel_for ?cancel ~grain count (fun element ->
            let source = values.(element) in
            if not (Float.is_finite source) then record_first_bad bad_source element
            else
              let value = source *. weight *. mask.(element) in
              if Float.is_finite value then output.(element) <- value
              else record_first_bad bad_output element))
        source

let compute_extreme ?cancel ~grain ~maximum weights alpha (plan : plan) =
  let count = Array.length plan.output.(0)
  and masks = alpha.(owner_slot plan.owner)
  and bad_source = Atomic.make max_int and bad_output = Atomic.make max_int in
  initialize_weighted ?cancel ~grain ~bad_source ~bad_output weights masks plan;
  for input_index = 1 to Array.length weights - 1 do
    let source = plan.sources.(input_index)
    and weight = weights.(input_index) and mask = masks.(input_index) in
    for component = 0 to Array.length plan.output - 1 do
      let output = plan.output.(component) in
      match source with
      | None -> parallel_for ?cancel ~grain count (fun element ->
          let candidate = 0. in
          if (maximum && candidate > output.(element))
              || ((not maximum) && candidate < output.(element)) then
            output.(element) <- candidate)
      | Some planes ->
          let values = planes.(component) in
          (match mask with
           | None -> parallel_for ?cancel ~grain count (fun element ->
               let candidate = values.(element) *. weight in
               if not (Float.is_finite values.(element)) then
                 record_first_bad bad_source element
               else if not (Float.is_finite candidate) then
                 record_first_bad bad_output element
               else if (maximum && candidate > output.(element))
                   || ((not maximum) && candidate < output.(element)) then
                 output.(element) <- candidate)
           | Some mask -> parallel_for ?cancel ~grain count (fun element ->
               let candidate = values.(element) *. weight *. mask.(element) in
               if not (Float.is_finite values.(element)) then
                 record_first_bad bad_source element
               else if not (Float.is_finite candidate) then
                 record_first_bad bad_output element
               else if (maximum && candidate > output.(element))
                   || ((not maximum) && candidate < output.(element)) then
                 output.(element) <- candidate))
    done
  done;
  finish_plan plan bad_source bad_output

let compute_alpha_fold ?cancel ~grain ~over weights alpha (plan : plan) =
  let count = Array.length plan.output.(0)
  and masks = alpha.(owner_slot plan.owner)
  and bad_source = Atomic.make max_int and bad_output = Atomic.make max_int in
  initialize_weighted ?cancel ~grain ~bad_source ~bad_output weights
    (Array.make (Array.length masks) None) plan;
  for input_index = 1 to Array.length weights - 1 do
    let source = plan.sources.(input_index)
    and weight = weights.(input_index) and mask = masks.(input_index) in
    for component = 0 to Array.length plan.output - 1 do
      let output = plan.output.(component) in
      match source with
      | None -> parallel_for ?cancel ~grain count (fun element ->
          let alpha = match mask with None -> 1. | Some mask -> mask.(element) in
          let value = if over then output.(element) *. (1. -. alpha)
            else output.(element) *. alpha in
          if Float.is_finite value then output.(element) <- value
          else record_first_bad bad_output element)
      | Some planes ->
          let values = planes.(component) in
          parallel_for ?cancel ~grain count (fun element ->
            let alpha = match mask with None -> 1. | Some mask -> mask.(element) in
            let source = values.(element) in
            if not (Float.is_finite source) then record_first_bad bad_source element
            else
              let source = source *. weight in
              let value = if over
                then (source *. alpha) +. (output.(element) *. (1. -. alpha))
                else (source *. (1. -. alpha)) +. (output.(element) *. alpha) in
              if Float.is_finite value then output.(element) <- value
              else record_first_bad bad_output element)
    done
  done;
  finish_plan plan bad_source bad_output

let attribute_of_plan (plan : plan) =
  let storage = match plan.kind with
    | Scalar -> Attribute.Float plan.output.(0)
    | Vector2 -> Attribute.Float2 (Packed.Float2.of_owned
        ~x:plan.output.(0) ~y:plan.output.(1) |> Result.get_ok)
    | Vector3 -> Attribute.Float3 (Packed.Float3.Private.of_owned_exn
        ~x:plan.output.(0) ~y:plan.output.(1) ~z:plan.output.(2))
    | Vector4 -> Attribute.Float4 (Packed.Float4.of_owned
        ~x:plan.output.(0) ~y:plan.output.(1) ~z:plan.output.(2)
        ~w:plan.output.(3) |> Result.get_ok)
    | Position -> assert false in
  Attribute.create_owned ~owner:plan.owner ~name:plan.name storage
  |> function Ok attribute -> attribute | Error message -> fail message

let run ?cancel ?(grain = 16_384) ?(operation = Composite_mean)
    ?(weight = 1.) ?(detail_attributes = "*")
    ?(primitive_attributes = "*") ?(point_attributes = "*")
    ?(vertex_attributes = "*") ?(allow_position = false) ?alpha_attribute
    ~inputs geometry =
  try
    if grain <= 0 then fail "Attribute Composite grain must be positive";
    if not (Float.is_finite weight) then
      fail "Attribute Composite first-input weight must be finite";
    Option.iter (fun name -> if String.trim name = "" then
      fail "Attribute Composite alpha attribute must be non-empty") alpha_attribute;
    Cancel.check_opt cancel;
    let inputs = Array.of_list inputs in
    Array.iteri (fun index input -> if not (Float.is_finite input.weight) then
      fail (Printf.sprintf
        "Attribute Composite input %d weight must be finite" (index + 1))) inputs;
    let resolved = Array.make (Array.length inputs + 1)
        { geometry; weight } in
    Array.iteri (fun index input -> resolved.(index + 1) <-
      { geometry = input.geometry; weight = input.weight }) inputs;
    let geometries = Array.map (fun input -> input.geometry) resolved
    and weights = Array.map (fun input -> input.weight) resolved in
    let owner_plans = owner_plans ~detail_attributes ~primitive_attributes
        ~point_attributes ~vertex_attributes geometry in
    let plans = make_plans ~allow_position owner_plans geometries in
    if Array.length plans = 0 then Ok geometry
    else begin
      let used = Array.make 4 false in
      Array.iter (fun (plan : plan) -> used.(owner_slot plan.owner) <- true)
        plans;
      let alpha = alpha_planes ~used ~alpha_attribute owner_plans geometries in
      validate_alpha ?cancel ~grain alpha;
      let denominators = if operation = Composite_mean then begin
          Array.mapi (fun index owner_plan ->
            if not used.(index) then None else Some
              (denominator_for_owner ?cancel ~grain ~owner:owner_plan.owner
                ~count:owner_plan.count weights alpha.(index))) owner_plans
        end else [||] in
      Array.iter (fun (plan : plan) ->
        (match operation with
         | Composite_mean ->
             compute_mean ?cancel ~grain weights alpha denominators plan
         | Composite_maximum ->
             compute_extreme ?cancel ~grain ~maximum:true weights alpha plan
         | Composite_minimum ->
             compute_extreme ?cancel ~grain ~maximum:false weights alpha plan
         | Composite_over ->
             compute_alpha_fold ?cancel ~grain ~over:true weights alpha plan
         | Composite_under ->
             compute_alpha_fold ?cancel ~grain ~over:false weights alpha plan))
        plans;
      let positions = Array.find_opt (fun (plan : plan) -> plan.kind = Position) plans
        |> Option.map (fun plan -> Packed.Float3.Private.of_owned_exn
          ~x:plan.output.(0) ~y:plan.output.(1) ~z:plan.output.(2)) in
      let attributes = plans |> Array.to_list
        |> List.filter_map (fun (plan : plan) -> if plan.kind = Position then None
          else Some (attribute_of_plan plan)) |> Array.of_list in
      let output = Geometry.Private.with_merged_attributes_and_groups_owned
          ?positions ~attributes ~groups:[||] geometry
        |> function Ok output -> output | Error message -> fail message in
      let has owner name = Array.exists (fun (plan : plan) -> plan.owner = owner
          && String.equal plan.name name) plans in
      let output = match positions with
        | None -> output
        | Some _ ->
            let output = if has Attribute.Point "N" then output else
                Geometry.without_attribute ~owner:Attribute.Point "N" output in
            if has Attribute.Vertex "N" then output else
              Geometry.without_attribute ~owner:Attribute.Vertex "N" output in
      Ok output
    end
  with Composite_error message -> Error message
