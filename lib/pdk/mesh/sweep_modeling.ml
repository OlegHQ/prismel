type grid_connectivity = Plane_generators.grid_connectivity =
  | Grid_points | Grid_rows | Grid_columns | Grid_rows_and_columns
  | Grid_quads | Grid_triangles | Grid_alternating_triangles
  | Grid_reverse_triangles

type revolve_type = Revolve.revolve_type = Revolve_closed | Revolve_open_arc

type sweep_tangent =
  | Sweep_average_edges
  | Sweep_central_difference
  | Sweep_previous_edge
  | Sweep_next_edge
  | Sweep_z_axis

let protected operation code work = Error.guard ~operation ~code work

let revolve_raw = Revolve.run
let revolve ?cancel ?grain ?primitives ?revolve_type ?connectivity ?start_angle
    ?end_angle ?reverse_cross_sections ?caps ?cap_group ?uv_attribute ~divisions
    ~origin ~axis geometry =
  protected "revolve" "invalid_geometry" (fun () ->
    revolve_raw ?cancel ?grain ?primitives ?revolve_type ?connectivity
      ?start_angle ?end_angle ?reverse_cross_sections ?caps ?cap_group
      ?uv_attribute ~divisions ~origin ~axis geometry)

let sweep ?cancel ?(grain = 16_384) ?backbones ?cross_sections
    ?(connectivity = Grid_quads) ?(tangent = Sweep_average_edges)
    ?(continuous_closed = true) ?(transform_attributes = true)
    ?(reverse_cross_sections = false) ?(scale = 1.) ?(roll = 0.) ?(twist = 0.)
    ?(caps = false) ?cap_group ?(uv_attribute = Some "uv")
    ?(cross_section_prefix = "cross_section_") ~backbone ~cross_section () =
  let connectivity = match connectivity with
    | Grid_points -> Sweep.Points
    | Grid_rows -> Sweep.Rows
    | Grid_columns -> Sweep.Columns
    | Grid_rows_and_columns -> Sweep.Rows_and_columns
    | Grid_quads -> Sweep.Quads
    | Grid_triangles -> Sweep.Triangles
    | Grid_alternating_triangles -> Sweep.Alternating_triangles
    | Grid_reverse_triangles -> Sweep.Reverse_triangles in
  let tangent = match tangent with
    | Sweep_average_edges -> Sweep.Average_edges
    | Sweep_central_difference -> Sweep.Central_difference
    | Sweep_previous_edge -> Sweep.Previous_edge
    | Sweep_next_edge -> Sweep.Next_edge
    | Sweep_z_axis -> Sweep.Z_axis in
  protected "sweep" "invalid_geometry" (fun () ->
    Sweep.run ?cancel ~grain ?backbones ?cross_sections ~connectivity ~tangent
      ~continuous_closed ~transform_attributes ~reverse_cross_sections ~scale
      ~roll ~twist ~caps ?cap_group ~uv_attribute ~cross_section_prefix
      ~backbone ~cross_section ())

