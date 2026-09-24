open Prismel

type cut =
  | Extract_cut_constant of float
  | Extract_cut_primitive_attribute of string

type numeric = Float_values of float array | Int_values of int array

exception Extract_error of string
let fail message = raise (Extract_error message)
let finite = Float.is_finite

let numeric_attribute ~owner ~role name geometry =
  if String.trim name = "" || name = "P" then
    fail (role ^ " attribute name must be non-empty and cannot be P");
  match Geometry.find_attribute ~owner name geometry with
  | None -> fail (Printf.sprintf "%s attribute %S was not found" role name)
  | Some attribute -> match Attribute.Private.storage attribute with
      | Attribute.Float values -> Float_values values
      | Attribute.Int values -> Int_values values
      | _ -> fail (Printf.sprintf "%s attribute %S must use scalar float or integer storage"
          role name)

let[@inline always] value values index = match values with
  | Float_values values -> Array.unsafe_get values index
  | Int_values values -> Float.of_int (Array.unsafe_get values index)

let validate_selection primitives primitive_count = match primitives with
  | None -> ()
  | Some group ->
      if Group.owner group <> Group.Primitive then
        fail "primitive selection must be primitive-owned";
      if Group.length group <> primitive_count then
        fail "primitive selection length does not match primitive count"

let[@inline always] selected primitives primitive = match primitives with
  | None -> true | Some group -> Group.mem primitive group

let[@inline always] crossing_weight a b target =
  if a = target then 0.
  else begin
    let scale = Float.max (abs_float target)
        (Float.max (abs_float a) (abs_float b)) in
    if scale = 0. then 0.5
    else begin
      let left = abs_float ((target /. scale) -. (a /. scale))
      and right = abs_float ((b /. scale) -. (target /. scale)) in
      left /. (left +. right)
    end
  end

let[@inline always] interpolate left right weight =
  let delta = right -. left in
  if finite delta then left +. (delta *. weight)
  else (left *. (1. -. weight)) +. (right *. weight)

let valid_output_name label = function
  | None -> ()
  | Some name when String.trim name = "" || name = "P" ->
      fail (label ^ " must be non-empty and cannot be P")
  | Some _ -> ()

let with_owner_point attribute =
  Attribute.create_owned ~owner:Attribute.Point ~name:(Attribute.name attribute)
    (Attribute.Private.storage attribute) |> Result.get_ok

let run ?cancel ?(grain = 16_384) ?primitives ?(cut = Extract_cut_constant 0.)
    ?(point_attributes = "P") ?(copy_primitive_attributes = false)
    ?(primitive_attributes = "*") ?curve_u_attribute ?number_cuts_attribute
    ?curve_number_attribute ~distance_attribute geometry =
  try
    if grain <= 0 then fail "grain must be positive";
    List.iter (fun (label, name) -> valid_output_name label name) [
      "curve U attribute", curve_u_attribute;
      "number of cuts attribute", number_cuts_attribute;
      "curve number attribute", curve_number_attribute];
    let generated_names = List.filter_map Fun.id
        [curve_u_attribute; number_cuts_attribute; curve_number_attribute] in
    if List.length generated_names <> List.length (List.sort_uniq String.compare generated_names)
    then fail "generated output attribute names must be distinct";
    let point_pattern = match Attribute_pattern.compile point_attributes with
      | Ok value -> value | Error message -> fail message in
    let primitive_pattern = match Attribute_pattern.compile primitive_attributes with
      | Ok value -> value | Error message -> fail message in
    Cancel.check_opt cancel;
    let topology_value = Geometry.topology geometry in
    let topology = Topology.Private.view topology_value
    and positions = Packed.Float3.Private.view (Geometry.positions geometry) in
    let primitive_count = Geometry.primitive_count geometry in
    validate_selection primitives primitive_count;
    let distance = numeric_attribute ~owner:Attribute.Point ~role:"distance"
        distance_attribute geometry in
    let targets = match cut with
      | Extract_cut_constant target ->
          if not (finite target) then fail "constant cut value must be finite";
          `Constant target
      | Extract_cut_primitive_attribute name ->
          `Varying (numeric_attribute ~owner:Attribute.Primitive ~role:"cut value"
            name geometry) in
    let target primitive = match targets with
      | `Constant value -> value | `Varying values -> value values primitive in
    let selected_edges = ref 0 and selected_primitives = ref 0 in
    for primitive = 0 to primitive_count - 1 do
      if primitive land 1023 = 0 then Cancel.check_opt cancel;
      if selected primitives primitive then begin
        incr selected_primitives;
        let kind = Topology.primitive_kind topology_value primitive in
        if kind = Topology.Polygon then fail (Printf.sprintf
            "primitive %d is a polygon face, not a polygon curve" primitive);
        let first = topology.primitive_offsets.(primitive)
        and last = topology.primitive_offsets.(primitive + 1) in
        let corners = last - first in
        let edges = corners - 1
            + if kind = Topology.Closed_polyline then 1 else 0 in
        let cut_value = target primitive in
        if not (finite cut_value) then fail (Printf.sprintf
            "cut value for primitive %d is not finite" primitive);
        if !selected_edges > max_int - edges then
          fail "selected curve edge cardinality exceeds integer limits";
        selected_edges := !selected_edges + edges
      end
    done;
    (* A primitive-major pass is leanest for ordinary curve sets. If average
       selected curve size exceeds the requested grain, stable edge blocks
       also expose a single very long curve to the process-wide domain pool. *)
    let split_long_curves = !selected_edges > grain
        && !selected_primitives <= !selected_edges / grain in
    let block_plan = if not split_long_curves then None else begin
      let block_count = ref 0 in
      for primitive = 0 to primitive_count - 1 do
        if selected primitives primitive then begin
          let kind = Topology.primitive_kind topology_value primitive in
          let first = topology.primitive_offsets.(primitive)
          and last = topology.primitive_offsets.(primitive + 1) in
          let corners = last - first in
          let edges = corners - 1
              + if kind = Topology.Closed_polyline then 1 else 0 in
          let blocks = 1 + ((edges - 1) / grain) in
          if !block_count > Sys.max_array_length - blocks then
            fail "curve work-block cardinality exceeds array limits";
          block_count := !block_count + blocks
        end
      done;
      let block_primitive = Array.make !block_count 0
      and block_first = Array.make !block_count 0
      and block_last = Array.make !block_count 0
      and block_counts = Array.make !block_count 0 in
      let block = ref 0 in
      for primitive = 0 to primitive_count - 1 do
        if selected primitives primitive then begin
          let kind = Topology.primitive_kind topology_value primitive in
          let first = topology.primitive_offsets.(primitive)
          and last = topology.primitive_offsets.(primitive + 1) in
          let corners = last - first in
          let edges = corners - 1
              + if kind = Topology.Closed_polyline then 1 else 0 in
          let edge = ref 0 in
          while !edge < edges do
            let remaining = edges - !edge in
            let stop = if remaining <= grain then edges else !edge + grain in
            block_primitive.(!block) <- primitive;
            block_first.(!block) <- !edge;
            block_last.(!block) <- stop;
            incr block;
            edge := stop
          done
        end
      done;
      Some (block_primitive, block_first, block_last, block_counts)
    end in
    let classify_edges primitive edge_first edge_last include_endpoint =
      Cancel.check_opt cancel;
      let kind = Topology.primitive_kind topology_value primitive
      and first = topology.primitive_offsets.(primitive)
      and last = topology.primitive_offsets.(primitive + 1)
      and cut_value = target primitive in
      let corners = last - first in
      let count = ref 0 in
      for edge = edge_first to edge_last - 1 do
        if edge land 16_383 = 0 then Cancel.check_opt cancel;
        let left = topology.vertex_points.(first + edge mod corners)
        and right = topology.vertex_points.(first + (edge + 1) mod corners) in
        let a = value distance left and b = value distance right in
        if not (finite a && finite b) then fail (Printf.sprintf
            "distance attribute is non-finite on primitive %d edge %d"
            primitive edge);
        let crosses = a = cut_value || (a < cut_value && cut_value < b)
            || (b < cut_value && cut_value < a) in
        if crosses then incr count
      done;
      if include_endpoint && kind = Topology.Open_polyline then begin
        let last_point = topology.vertex_points.(last - 1) in
        if value distance last_point = cut_value then incr count
      end;
      !count in
    let counts = Array.make primitive_count 0 in
    let block_offsets = match block_plan with
      | None ->
          let classify primitive =
            if primitive land 1023 = 0 then Cancel.check_opt cancel;
            if selected primitives primitive then begin
              let kind = Topology.primitive_kind topology_value primitive in
              let first = topology.primitive_offsets.(primitive)
              and last = topology.primitive_offsets.(primitive + 1) in
              let corners = last - first in
              let edges = corners - 1
                  + if kind = Topology.Closed_polyline then 1 else 0 in
              counts.(primitive) <- classify_edges primitive 0 edges
                  (kind = Topology.Open_polyline)
            end in
          if primitive_count > 0 then Parallel.for_
              ~chunk_size:(max 1 (grain / 32)) ~start:0
              ~finish:(primitive_count - 1) classify;
          None
      | Some (block_primitive, block_first, block_last, block_counts) ->
          let block_count = Array.length block_primitive in
          if block_count > 0 then Parallel.for_ ~chunk_size:1 ~start:0
              ~finish:(block_count - 1) (fun block ->
                let primitive = block_primitive.(block) in
                let kind = Topology.primitive_kind topology_value primitive in
                let first = topology.primitive_offsets.(primitive)
                and last = topology.primitive_offsets.(primitive + 1) in
                let corners = last - first in
                let edges = corners - 1
                    + if kind = Topology.Closed_polyline then 1 else 0 in
                block_counts.(block) <- classify_edges primitive
                    block_first.(block) block_last.(block)
                    (block_last.(block) = edges));
          let offsets = Array.make (block_count + 1) 0 in
          for block = 0 to block_count - 1 do
            let count = block_counts.(block) in
            if offsets.(block) > Sys.max_array_length - count then
              fail "extracted point cardinality exceeds array limits";
            offsets.(block + 1) <- offsets.(block) + count;
            let primitive = block_primitive.(block) in
            if counts.(primitive) > Sys.max_array_length - count then
              fail "per-curve cut cardinality exceeds array limits";
            counts.(primitive) <- counts.(primitive) + count
          done;
          Some offsets in
    let offsets = Array.make (primitive_count + 1) 0 in
    for primitive = 0 to primitive_count - 1 do
      if offsets.(primitive) > Sys.max_array_length - counts.(primitive) then
        fail "extracted point cardinality exceeds array limits";
      offsets.(primitive + 1) <- offsets.(primitive) + counts.(primitive)
    done;
    let output_count = offsets.(primitive_count) in
    let x = Array.make output_count 0. and y = Array.make output_count 0.
    and z = Array.make output_count 0.
    and point_left = Array.make output_count 0
    and point_right = Array.make output_count 0
    and point_weight = Array.make output_count 0.
    and source_primitive = Array.make output_count 0
    and curve_u = Option.map (fun _ -> Array.make output_count 0.) curve_u_attribute in
    let fill_edges primitive edge_first edge_last include_endpoint output_first
        output_last =
      if output_first < output_last then begin
        Cancel.check_opt cancel;
        let kind = Topology.primitive_kind topology_value primitive
        and first = topology.primitive_offsets.(primitive)
        and last = topology.primitive_offsets.(primitive + 1)
        and cut_value = target primitive in
        let corners = last - first in
        let edges = corners - 1
            + if kind = Topology.Closed_polyline then 1 else 0 in
        let output = ref output_first in
        for edge = edge_first to edge_last - 1 do
          if edge land 16_383 = 0 then Cancel.check_opt cancel;
          let left = topology.vertex_points.(first + edge mod corners)
          and right = topology.vertex_points.(first + (edge + 1) mod corners) in
          let a = value distance left and b = value distance right in
          let crosses = a = cut_value || (a < cut_value && cut_value < b)
              || (b < cut_value && cut_value < a) in
          if crosses then begin
            let weight = crossing_weight a b cut_value in
            let output_index = !output in
            point_left.(output_index) <- left;
            point_right.(output_index) <- right;
            point_weight.(output_index) <- weight;
            source_primitive.(output_index) <- primitive;
            let px = interpolate positions.x.(left) positions.x.(right) weight
            and py = interpolate positions.y.(left) positions.y.(right) weight
            and pz = interpolate positions.z.(left) positions.z.(right) weight in
            if not (finite px && finite py && finite pz) then fail (Printf.sprintf
                "extracted position for primitive %d is not representable"
                primitive);
            x.(output_index) <- px;
            y.(output_index) <- py;
            z.(output_index) <- pz;
            (match curve_u with
             | None -> ()
             | Some values -> values.(output_index) <-
                 (Float.of_int edge +. weight) /. Float.of_int edges);
            incr output
          end
        done;
        if include_endpoint && kind = Topology.Open_polyline then begin
          let last_point = topology.vertex_points.(last - 1) in
          if value distance last_point = cut_value then begin
            let output_index = !output in
            point_left.(output_index) <- last_point;
            point_right.(output_index) <- last_point;
            point_weight.(output_index) <- 0.;
            source_primitive.(output_index) <- primitive;
            let px = positions.x.(last_point)
            and py = positions.y.(last_point)
            and pz = positions.z.(last_point) in
            if not (finite px && finite py && finite pz) then fail (Printf.sprintf
                "extracted position for primitive %d is not representable"
                primitive);
            x.(output_index) <- px;
            y.(output_index) <- py;
            z.(output_index) <- pz;
            (match curve_u with
             | None -> ()
             | Some values -> values.(output_index) <- 1.);
            incr output
          end
        end;
        if !output <> output_last then
          fail "internal extracted point cardinality mismatch"
      end in
    (match block_plan, block_offsets with
     | None, None ->
         let fill primitive =
           if counts.(primitive) > 0 then begin
             let kind = Topology.primitive_kind topology_value primitive in
             let first = topology.primitive_offsets.(primitive)
             and last = topology.primitive_offsets.(primitive + 1) in
             let corners = last - first in
             let edges = corners - 1
                 + if kind = Topology.Closed_polyline then 1 else 0 in
             fill_edges primitive 0 edges (kind = Topology.Open_polyline)
               offsets.(primitive) offsets.(primitive + 1)
           end in
         if primitive_count > 0 then Parallel.for_
             ~chunk_size:(max 1 (grain / 32)) ~start:0
             ~finish:(primitive_count - 1) fill
     | Some (block_primitive, block_first, block_last, block_counts),
         Some block_offsets ->
         let block_count = Array.length block_primitive in
         if block_count > 0 then Parallel.for_ ~chunk_size:1 ~start:0
             ~finish:(block_count - 1) (fun block ->
               if block_counts.(block) > 0 then begin
                 let primitive = block_primitive.(block) in
                 let kind = Topology.primitive_kind topology_value primitive in
                 let first = topology.primitive_offsets.(primitive)
                 and last = topology.primitive_offsets.(primitive + 1) in
                 let corners = last - first in
                 let edges = corners - 1
                     + if kind = Topology.Closed_polyline then 1 else 0 in
                 fill_edges primitive block_first.(block) block_last.(block)
                   (block_last.(block) = edges) block_offsets.(block)
                   block_offsets.(block + 1)
               end)
     | None, Some _ | Some _, None ->
         fail "internal curve work-block plan mismatch");
    let selected_point_attributes = List.filter (fun attribute ->
      Attribute.owner attribute = Attribute.Point
      && Attribute_pattern.matches point_pattern (Attribute.name attribute))
        (Geometry.attributes geometry) in
    let selected_primitive_attributes = if copy_primitive_attributes then
        List.filter (fun attribute -> Attribute.owner attribute = Attribute.Primitive
          && Attribute_pattern.matches primitive_pattern (Attribute.name attribute))
          (Geometry.attributes geometry)
      else [] in
    let occupied = Hashtbl.create 16 in
    let reserve role name =
      if name = "P" then fail (role ^ " cannot replace canonical P");
      match Hashtbl.find_opt occupied name with
      | None -> Hashtbl.add occupied name role
      | Some previous -> fail (Printf.sprintf
          "output attribute %S is requested by both %s and %s" name previous role) in
    List.iter (fun attribute -> reserve "point interpolation" (Attribute.name attribute))
      selected_point_attributes;
    List.iter (fun attribute -> reserve "primitive copy" (Attribute.name attribute))
      selected_primitive_attributes;
    List.iter (reserve "generated diagnostic") generated_names;
    let attributes = ref [] in
    List.iter (fun attribute ->
      attributes := Curve_ops.interpolate_attribute ?cancel ~grain
          point_left point_right point_weight [||] [||] [||] attribute
          :: !attributes) selected_point_attributes;
    List.iter (fun attribute ->
      let mapped = Topology_remap.attribute ?cancel ~grain source_primitive attribute in
      attributes := with_owner_point mapped :: !attributes)
      selected_primitive_attributes;
    let add name storage = attributes :=
      (Attribute.create_owned ~owner:Attribute.Point ~name storage |> Result.get_ok)
      :: !attributes in
    Option.iter (fun name -> add name (Attribute.Float (Option.get curve_u)))
      curve_u_attribute;
    Option.iter (fun name -> add name (Attribute.Int (Array.init output_count
      (fun output -> counts.(source_primitive.(output)))))) number_cuts_attribute;
    Option.iter (fun name -> add name (Attribute.Int source_primitive))
      curve_number_attribute;
    let detail = List.filter (fun attribute -> Attribute.owner attribute = Attribute.Detail)
        (Geometry.attributes geometry) in
    Geometry.create ~positions:(Packed.Float3.Private.of_owned_exn ~x ~y ~z)
      ~topology:(Topology.empty ~point_count:output_count)
      ~attributes:(detail @ List.rev !attributes) ()
  with
  | Extract_error message | Invalid_argument message -> Error message
