open Prismel

type operation =
  | Combine_copy
  | Combine_add
  | Combine_subtract
  | Combine_multiply
  | Combine_divide
  | Combine_maximum
  | Combine_minimum

type process =
  | Combine_process_none
  | Combine_reciprocal
  | Combine_clamp_01
  | Combine_complement_clamp_01
  | Combine_threshold_half

type layer = {
  source : string option;
  source_input : int;
  operation : operation;
  scale : float;
  add : float;
  process : process;
  blend : float;
  blend_attribute : string option;
  blend_input : int;
}

type numeric =
  | Numeric_float of float array
  | Numeric_int of int array
  | Numeric_float2 of Packed.Float2.Private.view
  | Numeric_float3 of Packed.Float3.Private.view
  | Numeric_float4 of Packed.Float4.Private.view

type destination_kind =
  | Destination_float
  | Destination_int
  | Destination_float2
  | Destination_float3
  | Destination_float4

type correspondence = Direct of int | Mapped of int array
type source_binding = Implicit_zero | Source of numeric * correspondence | Self_source
type blend_binding = Constant_one | Blend of numeric * correspondence | Self_blend
type compiled_layer = {
  source_binding : source_binding;
  blend_binding : blend_binding;
  operation : operation;
  scale : float;
  add : float;
  process : process;
  blend : float;
}

let owner_count geometry = function
  | Attribute.Point -> Geometry.point_count geometry
  | Attribute.Vertex -> Geometry.vertex_count geometry
  | Attribute.Primitive -> Geometry.primitive_count geometry
  | Attribute.Detail -> 1

let owner_name = function
  | Attribute.Point -> "point"
  | Attribute.Vertex -> "vertex"
  | Attribute.Primitive -> "primitive"
  | Attribute.Detail -> "detail"

let group_owner = function
  | Attribute.Point -> Some Group.Point
  | Attribute.Vertex -> Some Group.Vertex
  | Attribute.Primitive -> Some Group.Primitive
  | Attribute.Detail -> None

let finite label value =
  if Float.is_finite value then Ok ()
  else Error ("Attribute Combine: " ^ label ^ " must be finite")

let nonblank = function
  | None -> None
  | Some value ->
      let value = String.trim value in
      if value = "" then None else Some value

let numeric_of_attribute attribute =
  match Attribute.Private.storage attribute with
  | Attribute.Float values -> Ok (Numeric_float values)
  | Attribute.Int values -> Ok (Numeric_int values)
  | Attribute.Float2 values ->
      Ok (Numeric_float2 (Packed.Float2.Private.view values))
  | Attribute.Float3 values ->
      Ok (Numeric_float3 (Packed.Float3.Private.view values))
  | Attribute.Float4 values ->
      Ok (Numeric_float4 (Packed.Float4.Private.view values))
  | Attribute.Text _ | Attribute.Int_array _ | Attribute.Float_array _ ->
      Error (Printf.sprintf
      "Attribute Combine: attribute %S uses non-scalar storage"
      (Attribute.name attribute))

let find_numeric ~owner name geometry =
  if owner = Attribute.Point && String.equal name "P" then
    Ok (Some (Numeric_float3
      (Packed.Float3.Private.view (Geometry.positions geometry))))
  else match Geometry.find_attribute ~owner name geometry with
    | None -> Ok None
    | Some attribute -> Result.map Option.some (numeric_of_attribute attribute)

let[@inline always] numeric_width = function
  | Numeric_float _ | Numeric_int _ -> 1
  | Numeric_float2 _ -> 2
  | Numeric_float3 _ -> 3
  | Numeric_float4 _ -> 4

let[@inline always] numeric_component numeric element component = match numeric with
  | Numeric_float values -> values.(element)
  | Numeric_int values -> float_of_int values.(element)
  | Numeric_float2 values -> if component = 0 then values.x.(element)
      else values.y.(element)
  | Numeric_float3 values -> if component = 0 then values.x.(element)
      else if component = 1 then values.y.(element) else values.z.(element)
  | Numeric_float4 values -> if component = 0 then values.x.(element)
      else if component = 1 then values.y.(element)
      else if component = 2 then values.z.(element) else values.w.(element)

let[@inline always] numeric_length numeric element = match numeric with
  | Numeric_float values -> Float.abs values.(element)
  | Numeric_int values -> Float.abs (float_of_int values.(element))
  | Numeric_float2 values -> Float.hypot values.x.(element) values.y.(element)
  | Numeric_float3 values -> Float.hypot
      (Float.hypot values.x.(element) values.y.(element)) values.z.(element)
  | Numeric_float4 values -> Float.hypot
      (Float.hypot values.x.(element) values.y.(element))
      (Float.hypot values.z.(element) values.w.(element))

let destination_kind_of_numeric = function
  | Numeric_float _ -> Destination_float
  | Numeric_int _ -> Destination_int
  | Numeric_float2 _ -> Destination_float2
  | Numeric_float3 _ -> Destination_float3
  | Numeric_float4 _ -> Destination_float4

let destination_width = function
  | Destination_float | Destination_int -> 1
  | Destination_float2 -> 2
  | Destination_float3 -> 3
  | Destination_float4 -> 4

let selected_elements owner selection geometry =
  let count = owner_count geometry owner in
  match selection with
  | None -> Ok (count, fun rank -> rank)
  | Some group ->
      (match group_owner owner with
       | None -> Error "Attribute Combine: detail attributes do not accept a group"
       | Some expected when Group.owner group <> expected
           || Group.length group <> count ->
           Error (Printf.sprintf
             "Attribute Combine: selection must be a matching %s group"
             (owner_name owner))
       | Some _ ->
           let elements = Array.make (Group.cardinality group) 0
           and next = ref 0 in
           Group.iter_ordered (fun element ->
             elements.(!next) <- element; incr next) group;
           Ok (Array.length elements, fun rank -> elements.(rank)))

let[@inline always] mapping_element correspondence destination = match correspondence with
  | Direct source_count -> if destination < source_count then destination else -1
  | Mapped mapping -> mapping.(destination)

let find_text_match ~owner name geometry =
  match Geometry.find_attribute ~owner name geometry with
  | Some attribute ->
      (match Attribute.Private.storage attribute with
       | Attribute.Text values -> Some values
       | _ -> None)
  | None -> None

let hash_capacity length =
  if length < 0 || length > (Sys.max_array_length - 1) / 3 * 2 then
    Error "Attribute Combine: match table exceeds array limits"
  else
    let wanted = max 16 (length + (length / 2) + 1) in
    let capacity = ref 16 in
    while !capacity < wanted && !capacity <= Sys.max_array_length / 2 do
      capacity := !capacity lsl 1
    done;
    if !capacity < wanted then
      Error "Attribute Combine: match table exceeds array limits"
    else Ok !capacity

let[@inline always] integer_hash value mask =
  let value = if Sys.word_size > 32 then value lxor (value lsr 32) else value in
  let value = value lxor (value lsr 16) in
  (value * 0x45d9f3b) land mask

let integer_highest_map ?cancel values =
  Result.map (fun capacity ->
    let indices = Array.make capacity (-1) and mask = capacity - 1 in
    Array.iteri (fun index key ->
      if index land 4095 = 0 then Cancel.check_opt cancel;
      let slot = ref (integer_hash key mask) in
      while indices.(!slot) >= 0 && values.(indices.(!slot)) <> key do
        slot := (!slot + 1) land mask
      done;
      indices.(!slot) <- index) values;
    fun key ->
      let slot = ref (integer_hash key mask) and searching = ref true
      and result = ref (-1) in
      while !searching do
        let index = indices.(!slot) in
        if index < 0 then searching := false
        else if values.(index) = key then begin
          result := index; searching := false
        end else slot := (!slot + 1) land mask
      done;
      !result) (hash_capacity (Array.length values))

let string_highest_map ?cancel values =
  Result.map (fun capacity ->
    let indices = Array.make capacity (-1) and mask = capacity - 1 in
    Array.iteri (fun index key ->
      if index land 4095 = 0 then Cancel.check_opt cancel;
      let slot = ref (Hashtbl.hash key land mask) in
      while indices.(!slot) >= 0
          && not (String.equal values.(indices.(!slot)) key) do
        slot := (!slot + 1) land mask
      done;
      indices.(!slot) <- index) values;
    fun key ->
      let slot = ref (Hashtbl.hash key land mask) and searching = ref true
      and result = ref (-1) in
      while !searching do
        let index = indices.(!slot) in
        if index < 0 then searching := false
        else if String.equal values.(index) key then begin
          result := index; searching := false
        end else slot := (!slot + 1) land mask
      done;
      !result) (hash_capacity (Array.length values))

let fill_mapping ?cancel ~grain target_count target_values lookup =
  let mapping = Array.make target_count (-1) in
  if target_count > 0 then
    Parallel.for_ ~chunk_size:grain ~start:0 ~finish:(target_count - 1)
      (fun destination ->
        if destination land 4095 = 0 then Cancel.check_opt cancel;
        mapping.(destination) <- lookup target_values.(destination));
  Mapped mapping

let create_correspondence ?cancel ~grain ~owner ~match_attribute
    ~primary ~source () =
  let target_count = owner_count primary owner
  and source_count = owner_count source owner in
  if source == primary then Ok (Direct source_count)
  else match match_attribute with
  | None -> Ok (Direct source_count)
  | Some name ->
      (match find_text_match ~owner name primary,
          find_text_match ~owner name source with
       | Some target_values, Some source_values ->
           Result.map (fill_mapping ?cancel ~grain target_count target_values)
             (string_highest_map ?cancel source_values)
       | None, None ->
           Result.bind (find_numeric ~owner name primary) (function
             | Some (Numeric_int target_values) ->
                 Result.bind (find_numeric ~owner name source) (function
                   | Some (Numeric_int source_values) ->
                       Result.map
                         (fill_mapping ?cancel ~grain target_count target_values)
                         (integer_highest_map ?cancel source_values)
                   | Some _ -> Error
                       "Attribute Combine: match attributes must have identical integer or text storage"
                   | None -> Error (Printf.sprintf
                       "Attribute Combine: source input is missing match attribute %S" name))
             | Some _ -> Error
                 "Attribute Combine: match attributes must have identical integer or text storage"
             | None -> Error (Printf.sprintf
                 "Attribute Combine: primary input is missing match attribute %S" name))
       | Some _, None -> Error (Printf.sprintf
           "Attribute Combine: source input is missing text match attribute %S" name)
       | None, Some _ -> Error (Printf.sprintf
           "Attribute Combine: primary input is missing text match attribute %S" name))

let[@inline always] source_value numeric source_element destination_width component =
  if destination_width = 1 then numeric_length numeric source_element
  else if numeric_width numeric = 1 then
    numeric_component numeric source_element 0
  else if component < numeric_width numeric then
    numeric_component numeric source_element component
  else 0.

let[@inline always] blend_value numeric source_element =
  if numeric_width numeric = 1 then numeric_component numeric source_element 0
  else numeric_length numeric source_element

let[@inline always] clamp_01 value =
  if value < 0. then 0. else if value > 1. then 1. else value

let[@inline always] process_value process value = match process with
  | Combine_process_none -> value
  | Combine_reciprocal -> if value = 0. then 0. else 1. /. value
  | Combine_clamp_01 -> clamp_01 value
  | Combine_complement_clamp_01 -> clamp_01 (1. -. value)
  | Combine_threshold_half -> if value > 0.5 then 1. else 0.

let[@inline always] combine_value operation destination source = match operation with
  | Combine_copy -> source
  | Combine_add -> destination +. source
  | Combine_subtract -> destination -. source
  | Combine_multiply -> destination *. source
  | Combine_divide -> if source = 0. then 0. else destination /. source
  | Combine_maximum -> Float.max destination source
  | Combine_minimum -> Float.min destination source

let post_identity ~overall_scale ~threshold ~minimum ~maximum =
  overall_scale = 1. && threshold = None && minimum = None && maximum = None

let validate_layer input_count layer =
  if layer.source_input < 0 || layer.source_input >= input_count then
    Error "Attribute Combine: source input index is out of range"
  else if layer.blend_input < 0 || layer.blend_input >= input_count then
    Error "Attribute Combine: blend input index is out of range"
  else Result.bind (finite "source scale" layer.scale) (fun () ->
    Result.bind (finite "source add" layer.add) (fun () ->
    finite "blend" layer.blend))

let destination_numeric ~owner ~destination primary =
  find_numeric ~owner destination primary

let infer_destination_kind ~owner ~destination ~create_missing
    ~create_missing_as_scalar ~layers geometries =
  Result.bind (destination_numeric ~owner ~destination geometries.(0)) (function
    | Some numeric -> Ok (destination_kind_of_numeric numeric, Some numeric)
    | None when not create_missing -> Error (Printf.sprintf
        "Attribute Combine: missing destination attribute %S" destination)
    | None when create_missing_as_scalar -> Ok (Destination_float, None)
    | None ->
        let result = ref None and failure = ref None in
        List.iter (fun layer -> if !result = None && !failure = None then
          match nonblank layer.source with
          | None -> ()
          | Some name when layer.source_input = 0
              && String.equal name destination -> ()
          | Some name ->
              match find_numeric ~owner name geometries.(layer.source_input) with
              | Error message -> failure := Some message
              | Ok None -> ()
              | Ok (Some numeric) ->
                  result := Some (destination_kind_of_numeric numeric, None)) layers;
        (match !failure, !result with
         | Some message, _ -> Error message
         | None, Some result -> Ok result
         | None, None -> Ok (Destination_float, None)))

let initialize_output kind existing count =
  let width = destination_width kind in
  let output = Array.init width (fun _ -> Array.make count 0.) in
  (match existing with
   | None -> ()
   | Some numeric ->
       for component = 0 to width - 1 do
         for element = 0 to count - 1 do
           output.(component).(element) <-
             numeric_component numeric element component
         done
       done);
  output

let compile_layers ?cancel ~grain ~owner ~destination ~error_on_missing
    ~match_attribute geometries layers =
  let primary = geometries.(0)
  and mappings = Array.make (Array.length geometries) None in
  let correspondence input =
    match mappings.(input) with
    | Some result -> result
    | None ->
        let result = create_correspondence ?cancel ~grain ~owner ~match_attribute
            ~primary ~source:geometries.(input) () in
        mappings.(input) <- Some result;
        result in
  let compile layer =
    let source = match nonblank layer.source with
      | None -> Ok (Some Implicit_zero)
      | Some name when layer.source_input = 0
          && String.equal name destination -> Ok (Some Self_source)
      | Some name ->
          Result.bind (find_numeric ~owner name geometries.(layer.source_input))
            (function
              | None when error_on_missing -> Error (Printf.sprintf
                  "Attribute Combine: source input %d is missing %s attribute %S"
                  layer.source_input (owner_name owner) name)
              | None -> Ok None
              | Some numeric -> Result.map (fun mapping ->
                  Some (Source (numeric, mapping)))
                  (correspondence layer.source_input)) in
    Result.bind source (function
      | None -> Ok None
      | Some source_binding ->
          let blend = match nonblank layer.blend_attribute with
            | None -> Ok Constant_one
            | Some name when layer.blend_input = 0
                && String.equal name destination -> Ok Self_blend
            | Some name ->
                Result.bind
                  (find_numeric ~owner name geometries.(layer.blend_input))
                  (function
                    | None when error_on_missing -> Error (Printf.sprintf
                        "Attribute Combine: blend input %d is missing %s attribute %S"
                        layer.blend_input (owner_name owner) name)
                    | None -> Ok Constant_one
                    | Some numeric -> Result.map (fun mapping ->
                        Blend (numeric, mapping))
                        (correspondence layer.blend_input)) in
          Result.map (fun blend_binding -> Some {
            source_binding; blend_binding; operation = layer.operation;
            scale = layer.scale; add = layer.add; process = layer.process;
            blend = layer.blend }) blend) in
  List.fold_left (fun result layer -> Result.bind result (fun output ->
    Result.map (function None -> output | Some layer -> layer :: output)
      (compile layer))) (Ok []) layers
  |> Result.map (fun layers -> Array.of_list (List.rev layers))

let[@inline always] source_at binding ~destination ~width ~component output = match binding with
  | Implicit_zero -> 0.
  | Self_source ->
      if width = 1 then Float.abs output.(0).(destination)
      else output.(component).(destination)
  | Source (numeric, correspondence) ->
      let source = mapping_element correspondence destination in
      if source < 0 then 0.
      else source_value numeric source width component

let[@inline always] blend_at binding ~destination output = match binding with
  | Constant_one -> 1.
  | Self_blend ->
      if Array.length output = 1 then output.(0).(destination)
      else begin
        let sum = ref 0. in
        for component = 0 to Array.length output - 1 do
          let value = output.(component).(destination) in
          sum := !sum +. (value *. value)
        done;
        sqrt !sum
      end
  | Blend (numeric, correspondence) ->
      let source = mapping_element correspondence destination in
      if source < 0 then 0. else blend_value numeric source

let storage_of_output ?cancel ~grain ~selected_count ~selected_element
    ~existing kind output = match kind with
  | Destination_float -> Ok (Attribute.Float output.(0))
  | Destination_float2 -> Result.map (fun values -> Attribute.Float2 values)
      (Packed.Float2.of_owned ~x:output.(0) ~y:output.(1))
  | Destination_float3 -> Ok (Attribute.Float3
      (Packed.Float3.Private.of_owned_exn
        ~x:output.(0) ~y:output.(1) ~z:output.(2)))
  | Destination_float4 -> Result.map (fun values -> Attribute.Float4 values)
      (Packed.Float4.of_owned ~x:output.(0) ~y:output.(1)
        ~z:output.(2) ~w:output.(3))
  | Destination_int ->
      let count = Array.length output.(0) and invalid = Atomic.make false in
      let values = match existing with
        | Some (Numeric_int values) -> Array.copy values
        | None | Some _ -> Array.make count 0 in
      let limit = Float.ldexp 1. (Sys.word_size - 2) in
      if selected_count > 0 then Parallel.for_ ~chunk_size:grain ~start:0
          ~finish:(selected_count - 1) (fun rank ->
            if rank land 4095 = 0 then Cancel.check_opt cancel;
            let element = selected_element rank in
            let value = output.(0).(element) in
            if Float.is_finite value && value >= -.limit && value < limit then
              values.(element) <- int_of_float value
            else Atomic.set invalid true);
      if Atomic.get invalid then Error
          "Attribute Combine: integer destination result is out of range or non-finite"
      else Ok (Attribute.Int values)

let install_result ~owner ~destination ~delete_sources ~layers storage primary =
  let destination_is_position = owner = Attribute.Point
      && String.equal destination "P" in
  let delete_names = Hashtbl.create (List.length layers) in
  if delete_sources then List.iter (fun layer ->
    match nonblank layer.source with
    | Some name when layer.source_input = 0
        && not (String.equal name destination) && not (String.equal name "P") ->
        Hashtbl.replace delete_names name ()
    | None | Some _ -> ()) layers;
  let output_attribute = if destination_is_position then Ok None
    else Result.map Option.some
      (Attribute.create_owned ~owner ~name:destination storage) in
  Result.bind output_attribute (fun output_attribute ->
    let attributes = Geometry.Private.attributes primary in
    let destination_exists = ref false and kept = ref 0 in
    Array.iter (fun attribute ->
      let name = Attribute.name attribute in
      if Attribute.owner attribute = owner && String.equal name destination then begin
        destination_exists := true;
        incr kept
      end else if Attribute.owner attribute = owner
          && Hashtbl.mem delete_names name then ()
      else incr kept) attributes;
    let append = match output_attribute with
      | Some _ when not !destination_exists -> 1
      | None | Some _ -> 0 in
    let output = Array.make (!kept + append)
        (match output_attribute with Some attribute -> attribute
         | None when Array.length attributes > 0 -> attributes.(0)
         | None ->
             Attribute.create_owned ~owner:Attribute.Detail ~name:"__unused"
               (Attribute.Float [|0.|]) |> Result.get_ok) in
    let next = ref 0 in
    Array.iter (fun attribute ->
      let name = Attribute.name attribute in
      if Attribute.owner attribute = owner && String.equal name destination then
        match output_attribute with
        | None -> output.(!next) <- attribute; incr next
        | Some replacement -> output.(!next) <- replacement; incr next
      else if not (Attribute.owner attribute = owner
          && Hashtbl.mem delete_names name) then begin
        output.(!next) <- attribute; incr next
      end) attributes;
    (match output_attribute with
     | Some attribute when not !destination_exists -> output.(!next) <- attribute
     | None | Some _ -> ());
    if not destination_is_position then
      Geometry.Private.with_attributes_owned output primary
    else match storage with
      | Attribute.Float3 positions ->
          Geometry.Private.with_positions_and_attributes_owned
            positions output primary
      | _ -> Error "Attribute Combine: canonical P requires float3 storage")

let combine ?cancel ?(grain = 16_384) ?selection ?match_attribute
    ?(create_missing = true) ?(create_missing_as_scalar = false)
    ?(delete_sources = false) ?(error_on_missing = true)
    ?(overall_scale = 1.) ?threshold ?minimum ?maximum
    ~owner ~destination ~layers ~geometries () =
  if grain <= 0 then invalid_arg "Attribute Combine: grain must be positive";
  Cancel.check_opt cancel;
  if Array.length geometries = 0 then Error
      "Attribute Combine: at least one input geometry is required"
  else if String.trim destination = "" then Error
      "Attribute Combine: destination name must not be empty"
  else if String.equal destination "P" && owner <> Attribute.Point then Error
      "Attribute Combine: canonical P must be point owned"
  else Result.bind (finite "overall scale" overall_scale) (fun () ->
    Result.bind (match threshold with None -> Ok () | Some value ->
      finite "threshold" value) (fun () ->
    Result.bind (match minimum with None -> Ok () | Some value ->
      finite "minimum" value) (fun () ->
    Result.bind (match maximum with None -> Ok () | Some value ->
      finite "maximum" value) (fun () ->
    Result.bind (match minimum, maximum with
      | Some minimum, Some maximum when minimum > maximum ->
          Error "Attribute Combine: minimum must not exceed maximum"
      | None, None | None, Some _ | Some _, None | Some _, Some _ -> Ok ())
      (fun () ->
    let input_count = Array.length geometries in
    Result.bind (List.fold_left (fun result layer ->
      Result.bind result (fun () -> validate_layer input_count layer))
      (Ok ()) layers) (fun () ->
    let match_attribute = nonblank match_attribute in
    Result.bind (infer_destination_kind ~owner ~destination ~create_missing
        ~create_missing_as_scalar ~layers geometries)
      (fun (kind, existing) ->
    if String.equal destination "P" && kind <> Destination_float3 then Error
        "Attribute Combine: canonical P requires a float3 destination"
    else Result.bind (selected_elements owner selection geometries.(0))
      (fun (selected_count, selected_element) ->
    Result.bind (compile_layers ?cancel ~grain ~owner ~destination
        ~error_on_missing ~match_attribute geometries layers) (fun compiled ->
    let count = owner_count geometries.(0) owner
    and width = destination_width kind in
    if selected_count = 0 && not delete_sources then Ok geometries.(0)
    else if Array.length compiled = 0
        && post_identity ~overall_scale ~threshold ~minimum ~maximum
        && not delete_sources && Option.is_some existing then Ok geometries.(0)
    else begin
      let output = initialize_output kind existing count in
      if selected_count > 0 then Parallel.for_ ~chunk_size:grain ~start:0
          ~finish:(selected_count - 1) (fun rank ->
            if rank land 4095 = 0 then Cancel.check_opt cancel;
            let destination = selected_element rank in
            for layer_index = 0 to Array.length compiled - 1 do
              let layer = compiled.(layer_index) in
              let alpha = clamp_01
                  (layer.blend *. blend_at layer.blend_binding
                    ~destination output) in
              if alpha <> 0. then
                for component = 0 to width - 1 do
                  let current = output.(component).(destination) in
                  let source = source_at layer.source_binding ~destination
                      ~width ~component output in
                  let source = process_value layer.process
                      ((source *. layer.scale) +. layer.add) in
                  let candidate = combine_value layer.operation current source in
                  output.(component).(destination) <-
                    current +. (alpha *. (candidate -. current))
                done
            done;
            for component = 0 to width - 1 do
              let value = output.(component).(destination) *. overall_scale in
              let value = match threshold with
                | None -> value
                | Some threshold -> if value > threshold
                    then Option.value maximum ~default:1.
                    else Option.value minimum ~default:0. in
              let value = match minimum with
                | Some minimum -> Float.max minimum value | None -> value in
              output.(component).(destination) <- match maximum with
                | Some maximum -> Float.min maximum value | None -> value
            done);
      Result.bind (storage_of_output ?cancel ~grain ~selected_count
          ~selected_element ~existing kind output) (fun storage ->
        install_result ~owner ~destination ~delete_sources ~layers
          storage geometries.(0))
    end)))))))))
