open Prismel_math

let finite = Float.is_finite
let fuse = Fuse_grid.fuse

type deform_selection = Deform.selection =
  | Selected_points of Group.t
  | Selected_vertices of Group.t
  | Selected_primitives of Group.t
  | Selected_edges of Edge_group.t

let facet_point_selection ?cancel ~grain primitives geometry =
  let topology = Geometry.topology geometry in
  let index = Topology_index.create ?cancel topology in
  let view = Topology_index.Private.view index in
  Group.init ~grain ~owner:Group.Point ~name:"__facet_selected_points"
    (Topology.point_count topology) (fun point ->
      let found = ref false and at = ref view.point_offsets.(point) in
      let finish = view.point_offsets.(point + 1) in
      while not !found && !at < finish do
        found := Group.mem view.primitive_of_vertex.(view.point_vertices.(!at))
            primitives;
        incr at
      done;
      !found)

let facet_primitives_of_selection ?cancel ~grain selection geometry =
  let topology = Geometry.topology geometry in
  Cancel.check_opt cancel;
  Result.bind (Deform.validate_selection topology (Some selection)) (fun () ->
  match selection with
  | Selected_primitives group -> Ok group
  | Selected_points points ->
      let view = Topology.Private.view topology in
      Ok (Group.init ~grain ~owner:Group.Primitive
        ~name:"__facet_from_points" (Topology.primitive_count topology)
        (fun primitive ->
          if primitive land 4095 = 0 then Cancel.check_opt cancel;
          let found = ref false
          and vertex = ref view.primitive_offsets.(primitive) in
          let last = view.primitive_offsets.(primitive + 1) in
          while not !found && !vertex < last do
            found := Group.mem view.vertex_points.(!vertex) points;
            incr vertex
          done;
          !found))
  | Selected_vertices vertices ->
      let view = Topology.Private.view topology in
      Ok (Group.init ~grain ~owner:Group.Primitive
        ~name:"__facet_from_vertices" (Topology.primitive_count topology)
        (fun primitive ->
          if primitive land 4095 = 0 then Cancel.check_opt cancel;
          let found = ref false
          and vertex = ref view.primitive_offsets.(primitive) in
          let last = view.primitive_offsets.(primitive + 1) in
          while not !found && !vertex < last do
            found := Group.mem !vertex vertices;
            incr vertex
          done;
          !found))
  | Selected_edges edges ->
      let view = Topology.Private.view topology in
      let index = Topology_index.create ?cancel topology in
      let incidence = Topology_index.Private.view index in
      Ok (Group.init ~grain ~owner:Group.Primitive
        ~name:"__facet_from_edges" (Topology.primitive_count topology)
        (fun primitive ->
          if primitive land 4095 = 0 then Cancel.check_opt cancel;
          let found = ref false
          and vertex = ref view.primitive_offsets.(primitive) in
          let last = view.primitive_offsets.(primitive + 1) in
          while not !found && !vertex < last do
            let edge = incidence.edge_of_vertex.(!vertex) in
            found := edge >= 0 && Edge_group.mem edge edges;
            incr vertex
          done;
          !found)))

let facet ?cancel ?(grain = 16_384) ?primitives
    ?(pre_compute_normals = false)
    ?(make_normals_unit_length = false) ?(unique_points = false)
    ?consolidate_distance ?consolidate_normals_distance
    ?(remove_inline_points = false)
    ?(inline_distance = 0.) ?(orient_polygons = false) ?cusp_angle
    ?(remove_degenerate = false) ?(make_planar = false)
    ?(post_compute_normals = false) ?(reverse_normals = false) geometry =
  if grain <= 0 then invalid_arg "Pdk.Ops.facet: grain must be positive";
  let primitive_count = Geometry.primitive_count geometry in
  if match primitives with
    | Some group -> Group.owner group <> Group.Primitive
        || Group.length group <> primitive_count
    | None -> false
  then Error "Facet selection must be a matching primitive group"
  else if match consolidate_distance with Some value ->
      not (finite value) || value < 0. | None -> false
  then Error "Facet consolidation distance must be finite and non-negative"
  else if match consolidate_normals_distance with Some value ->
      not (finite value) || value < 0. | None -> false
  then Error "Facet normal consolidation distance must be finite and non-negative"
  else if consolidate_distance <> None && consolidate_normals_distance <> None
  then Error "Facet point and normal consolidation modes are mutually exclusive"
  else if remove_inline_points
      && (not (finite inline_distance) || inline_distance < 0.)
  then Error "Facet inline distance must be finite and non-negative"
  else if match primitives with Some group -> Group.cardinality group = 0
      | None -> false then Ok geometry
  else
    let original_geometry = geometry in
    let selection_name, geometry = match primitives with
      | None -> None, geometry
      | Some group when Group.cardinality group = primitive_count ->
          None, geometry
      | Some group ->
          let rec available suffix =
            let name = Printf.sprintf "__pdk_facet_selection_%d"
                suffix in
            if Geometry.find_group ~owner:Group.Primitive name geometry = None
            then name else available (suffix + 1) in
          let name = available 0 in
          let private_group = Group.init ~grain ~owner:Group.Primitive ~name
              primitive_count (fun primitive -> Group.mem primitive group) in
          Some name, Geometry.with_group private_group geometry |> Result.get_ok in
    let selection_geometry = geometry in
    let current_selection geometry = match selection_name with
      | None -> None
      | Some name -> Geometry.find_group ~owner:Group.Primitive name geometry in
    let result = if pre_compute_normals then
        Deform.normals ?cancel ~grain
          ?primitives:(current_selection geometry) geometry
      else Ok geometry in
    let result = Result.bind result (fun geometry ->
      Facet.adjust_normals ?cancel ~grain
        ?primitives:(current_selection geometry)
        ~unit_length:(make_normals_unit_length && not pre_compute_normals)
        ~reverse:false geometry) in
    let result = Result.bind result (fun geometry ->
      if unique_points then Facet.unique_points ?cancel ~grain
        ?primitives:(current_selection geometry) geometry
      else Ok geometry) in
    let result = Result.bind result (fun geometry ->
      match consolidate_distance, consolidate_normals_distance with
      | None, None -> Ok geometry
      | Some tolerance, None ->
          let selection = Option.map (fun primitives ->
            facet_point_selection ?cancel ~grain primitives geometry)
              (current_selection geometry) in
          fuse ?cancel ~grain ?selection ~tolerance geometry
      | None, Some distance ->
          Facet.consolidate_normals ?cancel ~grain
            ?primitives:(current_selection geometry) ~distance geometry
      | Some _, Some _ -> assert false) in
    let result = Result.bind result (fun geometry ->
      if remove_inline_points then
        Facet.remove_inline_points ?cancel ~grain
          ?primitives:(current_selection geometry) ~distance:inline_distance geometry
      else Ok geometry) in
    let result = Result.bind result (fun geometry ->
      if orient_polygons then Facet.orient_polygons ?cancel ~grain
          ?primitives:(current_selection geometry) geometry
      else Ok geometry) in
    let result = Result.bind result (fun geometry -> match cusp_angle with
      | None -> Ok geometry
      | Some angle -> Facet.cusp_polygons ?cancel ~grain
          ?primitives:(current_selection geometry) ~angle geometry) in
    let result = Result.bind result (fun geometry ->
      if remove_degenerate then
        Clean.delete_degenerate ?cancel ~grain
          ?primitives:(current_selection geometry) ~epsilon:1e-12 geometry
      else Ok geometry) in
    let result = Result.bind result (fun geometry ->
      if make_planar then Facet.make_planar ?cancel ~grain
          ?primitives:(current_selection geometry) geometry
      else Ok geometry) in
    let result = Result.bind result (fun geometry ->
      if post_compute_normals then Deform.normals ?cancel ~grain
          ?primitives:(current_selection geometry) geometry
      else Ok geometry) in
    let result = Result.bind result (fun geometry ->
      Facet.adjust_normals ?cancel ~grain ~unit_length:false
        ?primitives:(current_selection geometry)
        ~reverse:reverse_normals geometry) in
    Result.map (fun geometry -> match selection_name with
      | None -> geometry
      | Some _ when geometry == selection_geometry -> original_geometry
      | Some name -> Geometry.without_group ~owner:Group.Primitive name geometry)
      result

let run_checked ?cancel ?grain ?selection ?primitives ?pre_compute_normals
    ?make_normals_unit_length ?unique_points ?consolidate_distance
    ?consolidate_normals_distance ?remove_inline_points ?inline_distance
    ?orient_polygons ?cusp_angle ?remove_degenerate ?make_planar
    ?post_compute_normals ?reverse_normals geometry =
  Error.guard ~operation:"facet" ~code:"invalid_geometry" (fun () ->
    let resolved = match selection, primitives with
      | Some _, Some _ -> Error
          "Facet selection and primitive selection are mutually exclusive"
      | None, primitives -> Ok primitives
      | Some selection, None -> Result.map Option.some
          (facet_primitives_of_selection ?cancel
            ~grain:(Option.value ~default:16_384 grain) selection geometry) in
    Result.bind resolved (fun primitives ->
      facet ?cancel ?grain ?primitives ?pre_compute_normals
        ?make_normals_unit_length ?unique_points ?consolidate_distance
        ?consolidate_normals_distance ?remove_inline_points ?inline_distance
        ?orient_polygons ?remove_degenerate ?make_planar ?cusp_angle
        ?post_compute_normals ?reverse_normals geometry))
