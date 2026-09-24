open Prismel

type mode = Blend_normalized | Blend_differencing
type masking = Blend_no_mask | Blend_set_from_attribute
  | Blend_scale_from_attribute
type mask_source = Blend_mask_first_input | Blend_mask_shape

type shape = {
  geometry : Geometry.t;
  weight : float;
  mask_attribute : string option;
  mask_source : mask_source;
}

type mapping = Direct | Mapped of int array

type resolved_shape = {
  positions : Packed.Float3.Private.view;
  point_count : int;
  mapping : mapping;
  weight : float;
  mask : float array option;
  mask_from_shape : bool;
  geometry : Geometry.t;
}

type attribute_plan =
  | Scalar of string * float array * float array * float array option array
  | Vec2 of string * Packed.Float2.Private.view
      * Packed.Float2.Private.view
      * float array option array * float array option array
  | Vec3 of string * Packed.Float3.Private.view
      * Packed.Float3.Private.view
      * float array option array * float array option array
      * float array option array
  | Vec4 of string * Packed.Float4.Private.view
      * Packed.Float4.Private.view
      * float array option array * float array option array
      * float array option array * float array option array

exception Blend_error of string
let fail message = raise (Blend_error message)

let shape ?mask_attribute ?(mask_source = Blend_mask_shape) ~weight geometry =
  Option.iter (fun name -> if String.trim name = "" then
    invalid_arg "Pdk.Ops.blend_shape: empty mask attribute") mask_attribute;
  if not (Float.is_finite weight) then
    invalid_arg "Pdk.Ops.blend_shape: non-finite weight";
  { geometry; weight; mask_attribute; mask_source }

let[@inline always] mapped_point mapping point = match mapping with
  | Direct -> point
  | Mapped points -> points.(point)

let validate_unique_int label values =
  let seen = Hashtbl.create (max 16 (Array.length values * 2)) in
  Array.iteri (fun point value ->
    if Hashtbl.mem seen value then fail (Printf.sprintf
        "Blend Shapes %s integer ID %d is ambiguous at point %d"
        label value point);
    Hashtbl.add seen value point) values;
  seen

let validate_unique_text label values =
  let seen = Hashtbl.create (max 16 (Array.length values * 2)) in
  Array.iteri (fun point value ->
    if Hashtbl.mem seen value then fail (Printf.sprintf
        "Blend Shapes %s text ID %S is ambiguous at point %d"
        label value point);
    Hashtbl.add seen value point) values;
  seen

type source_ids = Integer_ids of int array | Text_ids of string array

let source_ids name point_count geometry =
  match Geometry.find_attribute ~owner:Attribute.Point name geometry with
  | None -> fail (Printf.sprintf
      "Blend Shapes could not find point ID attribute %S on the first input" name)
  | Some attribute ->
      (match Attribute.Private.storage attribute with
       | Attribute.Int values when Array.length values = point_count ->
           ignore (validate_unique_int "first-input" values);
           Integer_ids values
       | Attribute.Text values when Array.length values = point_count ->
           ignore (validate_unique_text "first-input" values);
           Text_ids values
       | Attribute.Int _ | Attribute.Text _ ->
           fail "Blend Shapes first-input point ID cardinality mismatch"
       | _ -> fail "Blend Shapes point IDs must be integer or text attributes")

let mapping_for_ids name ids target_index geometry =
  let target_count = Geometry.point_count geometry in
  match Geometry.find_attribute ~owner:Attribute.Point name geometry, ids with
  | None, _ -> fail (Printf.sprintf
      "Blend Shapes target %d is missing point ID attribute %S"
      target_index name)
  | Some attribute, Integer_ids source ->
      (match Attribute.Private.storage attribute with
       | Attribute.Int target when Array.length target = target_count ->
           let lookup = validate_unique_int
               (Printf.sprintf "target-%d" target_index) target in
           Mapped (Array.map (fun id ->
             match Hashtbl.find_opt lookup id with Some point -> point | None -> -1)
             source)
       | Attribute.Int _ -> fail (Printf.sprintf
           "Blend Shapes target %d point ID cardinality mismatch" target_index)
       | _ -> fail (Printf.sprintf
           "Blend Shapes target %d point ID storage differs from the first input"
           target_index))
  | Some attribute, Text_ids source ->
      (match Attribute.Private.storage attribute with
       | Attribute.Text target when Array.length target = target_count ->
           let lookup = validate_unique_text
               (Printf.sprintf "target-%d" target_index) target in
           Mapped (Array.map (fun id ->
             match Hashtbl.find_opt lookup id with Some point -> point | None -> -1)
             source)
       | Attribute.Text _ -> fail (Printf.sprintf
           "Blend Shapes target %d point ID cardinality mismatch" target_index)
       | _ -> fail (Printf.sprintf
           "Blend Shapes target %d point ID storage differs from the first input"
           target_index))

let point_mask label point_count name geometry =
  match Geometry.find_attribute ~owner:Attribute.Point name geometry with
  | None -> None
  | Some attribute ->
      (match Attribute.Private.storage attribute with
       | Attribute.Float values when Array.length values = point_count ->
           let point = ref 0 in
           while !point < point_count do
             if not (Float.is_finite values.(!point)) then fail (Printf.sprintf
                 "Blend Shapes %s mask %S is non-finite at point %d"
                 label name !point);
             incr point
           done;
           Some values
       | Attribute.Float _ -> fail (Printf.sprintf
           "Blend Shapes %s mask %S cardinality mismatch" label name)
       | _ -> fail (Printf.sprintf
           "Blend Shapes %s mask %S must be a scalar float point attribute"
           label name))

let target_float_storage name expected point_count geometry =
  match Geometry.find_attribute ~owner:Attribute.Point name geometry with
  | None -> None
  | Some attribute ->
      if Attribute.length attribute <> point_count then fail (Printf.sprintf
          "Blend Shapes target attribute %S cardinality mismatch" name);
      let storage = Attribute.Private.storage attribute in
      match expected, storage with
      | `Float, Attribute.Float values -> Some (`Float values)
      | `Float2, Attribute.Float2 values ->
          Some (`Float2 (Packed.Float2.Private.view values))
      | `Float3, Attribute.Float3 values ->
          Some (`Float3 (Packed.Float3.Private.view values))
      | `Float4, Attribute.Float4 values ->
          Some (`Float4 (Packed.Float4.Private.view values))
      | _ -> fail (Printf.sprintf
          "Blend Shapes target attribute %S storage differs from the first input"
          name)

let make_attribute_plans pattern point_count shapes geometry =
  Geometry.attributes geometry |> List.filter_map (fun attribute ->
    let name = Attribute.name attribute in
    if Attribute.owner attribute <> Attribute.Point
        || not (Attribute_pattern.matches pattern name) then None
    else match Attribute.Private.storage attribute with
      | Attribute.Float source when Array.length source = point_count ->
          let output = Array.copy source in
          let targets = Array.map (fun shape ->
            match target_float_storage name `Float shape.point_count
                shape.geometry with
            | None -> None | Some (`Float values) -> Some values
            | Some _ -> assert false) shapes in
          Some (Scalar (name, source, output, targets))
      | Attribute.Float2 source when Packed.Float2.length source = point_count ->
          let source = Packed.Float2.Private.view source in
          let output = { Packed.Float2.Private.x = Array.copy source.x;
            y = Array.copy source.y } in
          let targets = Array.map (fun shape ->
            match target_float_storage name `Float2 shape.point_count
                shape.geometry with
            | None -> None | Some (`Float2 values) -> Some values
            | Some _ -> assert false) shapes in
          Some (Vec2 (name, source, output,
            Array.map (Option.map (fun value -> value.Packed.Float2.Private.x))
              targets,
            Array.map (Option.map (fun value -> value.Packed.Float2.Private.y))
              targets))
      | Attribute.Float3 source when Packed.Float3.length source = point_count ->
          let source = Packed.Float3.Private.view source in
          let output = { Packed.Float3.Private.x = Array.copy source.x;
            y = Array.copy source.y; z = Array.copy source.z } in
          let targets = Array.map (fun shape ->
            match target_float_storage name `Float3 shape.point_count
                shape.geometry with
            | None -> None | Some (`Float3 values) -> Some values
            | Some _ -> assert false) shapes in
          Some (Vec3 (name, source, output,
            Array.map (Option.map (fun value -> value.Packed.Float3.Private.x))
              targets,
            Array.map (Option.map (fun value -> value.Packed.Float3.Private.y))
              targets,
            Array.map (Option.map (fun value -> value.Packed.Float3.Private.z))
              targets))
      | Attribute.Float4 source when Packed.Float4.length source = point_count ->
          let source = Packed.Float4.Private.view source in
          let output = { Packed.Float4.Private.x = Array.copy source.x;
            y = Array.copy source.y; z = Array.copy source.z;
            w = Array.copy source.w } in
          let targets = Array.map (fun shape ->
            match target_float_storage name `Float4 shape.point_count
                shape.geometry with
            | None -> None | Some (`Float4 values) -> Some values
            | Some _ -> assert false) shapes in
          Some (Vec4 (name, source, output,
            Array.map (Option.map (fun value -> value.Packed.Float4.Private.x))
              targets,
            Array.map (Option.map (fun value -> value.Packed.Float4.Private.y))
              targets,
            Array.map (Option.map (fun value -> value.Packed.Float4.Private.z))
              targets,
            Array.map (Option.map (fun value -> value.Packed.Float4.Private.w))
              targets))
      | Attribute.Float _ | Attribute.Float2 _ | Attribute.Float3 _
      | Attribute.Float4 _ -> fail (Printf.sprintf
          "Blend Shapes first-input attribute %S cardinality mismatch" name)
      | Attribute.Int _ | Attribute.Text _ | Attribute.Int_array _
      | Attribute.Float_array _ -> None)

let run ?cancel ?(grain = 16_384) ?points ?(mode = Blend_normalized)
    ?(masking = Blend_no_mask) ?mask_attribute ?point_id_attribute
    ?(attributes = "*") ~shapes geometry =
  try
    if grain <= 0 then fail "Blend Shapes grain must be positive";
    Option.iter (fun name -> if String.trim name = "" then
      fail "Blend Shapes mask attribute must be non-empty") mask_attribute;
    Option.iter (fun name -> if String.trim name = "" then
      fail "Blend Shapes point ID attribute must be non-empty") point_id_attribute;
    let pattern = match Attribute_pattern.compile attributes with
      | Ok pattern -> pattern | Error message -> fail message in
    let point_count = Geometry.point_count geometry in
    (match points with
     | Some group when Group.owner group <> Group.Point ->
         fail "Blend Shapes selection must own points"
     | Some group when Group.length group <> point_count ->
         fail "Blend Shapes selection length does not match the first input"
     | None | Some _ -> ());
    let shapes = Array.of_list shapes in
    let zero_effect = match masking, mode with
      | Blend_set_from_attribute, _ -> false
      | Blend_no_mask, Blend_normalized ->
          Array.for_all (fun (shape : shape) -> shape.weight <= 0.) shapes
      | Blend_no_mask, Blend_differencing
      | Blend_scale_from_attribute, _ ->
          Array.for_all (fun (shape : shape) -> shape.weight = 0.) shapes in
    if Array.length shapes = 0 || zero_effect then Ok geometry
    else begin
      Cancel.check_opt cancel;
      let ids = Option.map (fun name -> source_ids name point_count geometry)
          point_id_attribute in
      let first_mask name = point_mask "first-input" point_count name geometry in
      let resolved = Array.mapi (fun index (shape : shape) ->
        if not (Float.is_finite shape.weight) then fail (Printf.sprintf
            "Blend Shapes target %d has a non-finite weight" index);
        let target_count = Geometry.point_count shape.geometry in
        let mapping = match point_id_attribute, ids with
          | None, _ ->
              if target_count <> point_count then fail (Printf.sprintf
                  "Blend Shapes target %d point count differs from the first input"
                  index);
              Direct
          | Some name, Some ids -> mapping_for_ids name ids index shape.geometry
          | Some _, None -> assert false in
        let chosen_mask = match shape.mask_attribute, mask_attribute with
          | Some name, _ -> Some name | None, fallback -> fallback in
        let mask, mask_from_shape = match masking, chosen_mask with
          | Blend_no_mask, _ | _, None -> None, false
          | _, Some name ->
              (match shape.mask_source with
               | Blend_mask_first_input -> first_mask name, false
               | Blend_mask_shape ->
                   point_mask (Printf.sprintf "target-%d" index) target_count
                     name shape.geometry, true) in
        { positions = Packed.Float3.Private.view
            (Geometry.positions shape.geometry);
          point_count = target_count; mapping; weight = shape.weight;
          mask; mask_from_shape; geometry = shape.geometry }) shapes in
      let plans = Array.of_list
          (make_attribute_plans pattern point_count resolved geometry) in
      let source = Packed.Float3.Private.view (Geometry.positions geometry) in
      let output = { Packed.Float3.Private.x = Array.copy source.x;
        y = Array.copy source.y; z = Array.copy source.z } in
      let selected point = match points with
        | None -> true | Some group -> Group.mem point group in
      let direct_constant_weights = masking = Blend_no_mask
          && Array.for_all (fun shape -> shape.mapping = Direct) resolved in
      let constant_sum = if mode = Blend_normalized && direct_constant_weights
          then Some (Array.fold_left (fun sum shape ->
            sum +. (if shape.weight > 0. then shape.weight else 0.)) 0. resolved)
        else None in
      let weight_sums = if mode = Blend_normalized
          && Option.is_none constant_sum then begin
          let sums = Array.make point_count 0. in
          for shape_index = 0 to Array.length resolved - 1 do
            let shape = resolved.(shape_index) in
            Parallel.for_ ~chunk_size:grain ~start:0 ~finish:(point_count - 1)
              (fun point ->
                if point land 4095 = 0 then Cancel.check_opt cancel;
                if selected point then begin
                  let mapped = mapped_point shape.mapping point in
                  if mapped >= 0 then begin
                    let weight = match masking, shape.mask with
                      | Blend_no_mask, _ | _, None -> shape.weight
                      | Blend_set_from_attribute, Some mask ->
                          mask.(if shape.mask_from_shape then mapped else point)
                      | Blend_scale_from_attribute, Some mask -> shape.weight *.
                          mask.(if shape.mask_from_shape then mapped else point) in
                    if weight > 0. then sums.(point) <- sums.(point) +. weight
                  end
                end)
          done;
          Some sums
        end else None in
      if mode = Blend_normalized then
        Parallel.for_ ~chunk_size:grain ~start:0 ~finish:(point_count - 1)
          (fun point ->
            if point land 4095 = 0 then Cancel.check_opt cancel;
            if selected point then begin
              let factor = match constant_sum, weight_sums with
                | Some sum, _ -> if sum < 1. then 1. -. sum else 0.
                | None, Some sums -> let sum = sums.(point) in
                    if sum < 1. then 1. -. sum else 0.
                | None, None -> 1. in
              output.x.(point) <- factor *. source.x.(point);
              output.y.(point) <- factor *. source.y.(point);
              output.z.(point) <- factor *. source.z.(point);
              for plan_index = 0 to Array.length plans - 1 do
                match plans.(plan_index) with
                | Scalar (_, source, output, _) ->
                    output.(point) <- factor *. source.(point)
                | Vec2 (_, source, output, _, _) ->
                    output.x.(point) <- factor *. source.x.(point);
                    output.y.(point) <- factor *. source.y.(point)
                | Vec3 (_, source, output, _, _, _) ->
                    output.x.(point) <- factor *. source.x.(point);
                    output.y.(point) <- factor *. source.y.(point);
                    output.z.(point) <- factor *. source.z.(point)
                | Vec4 (_, source, output, _, _, _, _) ->
                    output.x.(point) <- factor *. source.x.(point);
                    output.y.(point) <- factor *. source.y.(point);
                    output.z.(point) <- factor *. source.z.(point);
                    output.w.(point) <- factor *. source.w.(point)
              done
            end);
      for shape_index = 0 to Array.length resolved - 1 do
        let shape = resolved.(shape_index) in
        Parallel.for_ ~chunk_size:grain ~start:0 ~finish:(point_count - 1)
          (fun point ->
            if point land 4095 = 0 then Cancel.check_opt cancel;
            if selected point then begin
              let mapped = mapped_point shape.mapping point in
              if mapped >= 0 then begin
                let raw_weight = match masking, shape.mask with
                  | Blend_no_mask, _ | _, None -> shape.weight
                  | Blend_set_from_attribute, Some mask ->
                      mask.(if shape.mask_from_shape then mapped else point)
                  | Blend_scale_from_attribute, Some mask -> shape.weight *.
                      mask.(if shape.mask_from_shape then mapped else point) in
                let coefficient = match mode with
                  | Blend_differencing -> raw_weight
                  | Blend_normalized ->
                      let weight = if raw_weight > 0. then raw_weight else 0. in
                      let sum = match constant_sum, weight_sums with
                        | Some sum, _ -> sum
                        | None, Some sums -> sums.(point)
                        | None, None -> assert false in
                      weight /. (if sum < 1. then 1. else sum) in
                (match mode with
                 | Blend_differencing ->
                     output.x.(point) <- output.x.(point) +. coefficient
                       *. (shape.positions.x.(mapped) -. source.x.(point));
                     output.y.(point) <- output.y.(point) +. coefficient
                       *. (shape.positions.y.(mapped) -. source.y.(point));
                     output.z.(point) <- output.z.(point) +. coefficient
                       *. (shape.positions.z.(mapped) -. source.z.(point))
                 | Blend_normalized ->
                     output.x.(point) <- output.x.(point)
                       +. coefficient *. shape.positions.x.(mapped);
                     output.y.(point) <- output.y.(point)
                       +. coefficient *. shape.positions.y.(mapped);
                     output.z.(point) <- output.z.(point)
                       +. coefficient *. shape.positions.z.(mapped));
                for plan_index = 0 to Array.length plans - 1 do
                  match plans.(plan_index) with
                  | Scalar (_, source, output, targets) ->
                      let target = match targets.(shape_index) with
                        | Some values -> values.(mapped) | None -> source.(point) in
                      output.(point) <- output.(point) +. coefficient *.
                        (match mode with Blend_normalized -> target
                         | Blend_differencing -> target -. source.(point))
                  | Vec2 (_, source, output, x, y) ->
                      let tx = match x.(shape_index) with Some values -> values.(mapped)
                        | None -> source.x.(point)
                      and ty = match y.(shape_index) with Some values -> values.(mapped)
                        | None -> source.y.(point) in
                      output.x.(point) <- output.x.(point) +. coefficient *.
                        (match mode with Blend_normalized -> tx
                         | Blend_differencing -> tx -. source.x.(point));
                      output.y.(point) <- output.y.(point) +. coefficient *.
                        (match mode with Blend_normalized -> ty
                         | Blend_differencing -> ty -. source.y.(point))
                  | Vec3 (_, source, output, x, y, z) ->
                      let tx = match x.(shape_index) with Some values -> values.(mapped)
                        | None -> source.x.(point)
                      and ty = match y.(shape_index) with Some values -> values.(mapped)
                        | None -> source.y.(point)
                      and tz = match z.(shape_index) with Some values -> values.(mapped)
                        | None -> source.z.(point) in
                      output.x.(point) <- output.x.(point) +. coefficient *.
                        (match mode with Blend_normalized -> tx
                         | Blend_differencing -> tx -. source.x.(point));
                      output.y.(point) <- output.y.(point) +. coefficient *.
                        (match mode with Blend_normalized -> ty
                         | Blend_differencing -> ty -. source.y.(point));
                      output.z.(point) <- output.z.(point) +. coefficient *.
                        (match mode with Blend_normalized -> tz
                         | Blend_differencing -> tz -. source.z.(point))
                  | Vec4 (_, source, output, x, y, z, w) ->
                      let tx = match x.(shape_index) with Some values -> values.(mapped)
                        | None -> source.x.(point)
                      and ty = match y.(shape_index) with Some values -> values.(mapped)
                        | None -> source.y.(point)
                      and tz = match z.(shape_index) with Some values -> values.(mapped)
                        | None -> source.z.(point)
                      and tw = match w.(shape_index) with Some values -> values.(mapped)
                        | None -> source.w.(point) in
                      output.x.(point) <- output.x.(point) +. coefficient *.
                        (match mode with Blend_normalized -> tx
                         | Blend_differencing -> tx -. source.x.(point));
                      output.y.(point) <- output.y.(point) +. coefficient *.
                        (match mode with Blend_normalized -> ty
                         | Blend_differencing -> ty -. source.y.(point));
                      output.z.(point) <- output.z.(point) +. coefficient *.
                        (match mode with Blend_normalized -> tz
                         | Blend_differencing -> tz -. source.z.(point));
                      output.w.(point) <- output.w.(point) +. coefficient *.
                        (match mode with Blend_normalized -> tw
                         | Blend_differencing -> tw -. source.w.(point))
                done
              end
            end)
      done;
      let bad = Atomic.make max_int in
      let record_bad point =
        let rec loop () =
          let known = Atomic.get bad in
          if point < known && not (Atomic.compare_and_set bad known point) then
            loop () in loop () in
      Parallel.for_ ~chunk_size:grain ~start:0 ~finish:(point_count - 1)
        (fun point ->
          if point land 4095 = 0 then Cancel.check_opt cancel;
          if selected point && not (Float.is_finite output.x.(point)
              && Float.is_finite output.y.(point)
              && Float.is_finite output.z.(point)) then record_bad point);
      Array.iter (fun plan ->
        Parallel.for_ ~chunk_size:grain ~start:0 ~finish:(point_count - 1)
          (fun point ->
            if point land 4095 = 0 then Cancel.check_opt cancel;
            if selected point then begin
              let finite = match plan with
                | Scalar (_, _, output, _) -> Float.is_finite output.(point)
                | Vec2 (_, _, output, _, _) -> Float.is_finite output.x.(point)
                    && Float.is_finite output.y.(point)
                | Vec3 (_, _, output, _, _, _) -> Float.is_finite output.x.(point)
                    && Float.is_finite output.y.(point)
                    && Float.is_finite output.z.(point)
                | Vec4 (_, _, output, _, _, _, _) -> Float.is_finite output.x.(point)
                    && Float.is_finite output.y.(point)
                    && Float.is_finite output.z.(point)
                    && Float.is_finite output.w.(point) in
              if not finite then record_bad point
            end)) plans;
      if Atomic.get bad <> max_int then fail (Printf.sprintf
          "Blend Shapes produced a non-finite output at point %d"
          (Atomic.get bad));
      let attributes = Array.map (function
        | Scalar (name, _, output, _) ->
            Attribute.create_owned ~owner:Attribute.Point ~name
              (Attribute.Float output)
        | Vec2 (name, _, output, _, _) ->
            Result.map (fun values -> Attribute.create_owned
                ~owner:Attribute.Point ~name (Attribute.Float2 values))
              (Packed.Float2.of_owned ~x:output.x ~y:output.y)
            |> Result.join
        | Vec3 (name, _, output, _, _, _) ->
            Attribute.create_owned ~owner:Attribute.Point ~name
              (Attribute.Float3 (Packed.Float3.Private.of_owned_exn
                ~x:output.x ~y:output.y ~z:output.z))
        | Vec4 (name, _, output, _, _, _, _) ->
            Result.map (fun values -> Attribute.create_owned
                ~owner:Attribute.Point ~name (Attribute.Float4 values))
              (Packed.Float4.of_owned ~x:output.x ~y:output.y ~z:output.z
                ~w:output.w)
            |> Result.join) plans
        |> Array.map (function Ok value -> value | Error message -> fail message) in
      let positions = Packed.Float3.Private.of_owned_exn
          ~x:output.x ~y:output.y ~z:output.z in
      let result = Geometry.Private.with_merged_attributes_and_groups_owned
          ~positions ~attributes ~groups:[||] geometry
        |> function Ok value -> value | Error message -> fail message in
      let blended_point_normal = Array.exists (function
        | Vec3 ("N", _, _, x, _, _) -> Array.exists Option.is_some x
        | _ -> false) plans in
      let result = Geometry.without_attribute ~owner:Attribute.Vertex "N" result in
      Ok (if blended_point_normal then result
        else Geometry.without_attribute ~owner:Attribute.Point "N" result)
    end
  with Blend_error message -> Error message
