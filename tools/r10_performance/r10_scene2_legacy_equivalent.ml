type scenario = Basic | Pxui | Canvas

type t = {
  draws : Scene_execution.draw list;
  workload_signature : string;
  work_units : int;
}

let put_float bytes offset value =
  Bytes.set_int64_le bytes offset (Int64.bits_of_float value)

let vertices points =
  let result = Bytes.make (List.length points * 16) '\000' in
  List.iteri
    (fun index (x, y) ->
      put_float result (index * 16) x;
      put_float result ((index * 16) + 8) y)
    points;
  result

let indices values =
  let result = Bytes.make (List.length values * 4) '\000' in
  List.iteri
    (fun index value ->
      Bytes.set_int32_le result (index * 4) (Int32.of_int value))
    values;
  result

let state width height : Scene_execution.state =
  {
    viewport = (0, 0, width, height);
    scissor = (0, 0, width, height);
    cull = Ogpu.Render_pass.Cull_none;
    depth_compare = Ogpu.Render_pass.Always;
    depth_write = false;
    depth_load = Ogpu.Render_pass.Clear;
    depth_clear = 1.;
    transform_uniforms = None;
    stencil_state = None;
    stencil_load = Ogpu.Render_pass.Clear;
    stencil_clear = 0;
  }

let create scenario ~width ~height =
  if width <= 0 || height <= 0 then invalid_arg "non-positive artifact extent";
  let width = float width and height = float height in
  let name, points, index_values =
    match scenario with
    | Basic ->
        "basic", [ 0., 0.; width, 0.; 0., height ], [ 0; 1; 2 ]
    | Pxui ->
        ( "pxui",
          [ 0., 0.; width, 0.; width, height; 0., height ],
          [ 0; 1; 2; 0; 2; 3 ] )
    | Canvas ->
        ( "canvas",
          [ 0., 0.; width /. 2., 0.; 0., height /. 2. ],
          [ 0; 1; 2 ] )
  in
  let vertex_count = List.length points in
  let index_count = List.length index_values in
  let work_units = index_count / 3 in
  let mesh : Scene_execution.mesh =
    {
      key = "phase5-b0-" ^ name;
      vertices = vertices points;
      vertex_count;
      indices = indices index_values;
      index_count;
    }
  in
  let width_i = int_of_float width and height_i = int_of_float height in
  {
    draws = [ { Scene_execution.mesh; state = state width_i height_i } ];
    workload_signature =
      Printf.sprintf "phase5-b0:%s:v1:%dx%d:vertices:%d:indices:%d:triangles:%d"
        name width_i height_i vertex_count index_count work_units;
    work_units;
  }
