open Prismel

let floor_width = 12.
let floor_height = 10.
let half_width = floor_width /. 2.
let half_height = floor_height /. 2.
let line_half_width = 0.035
let grid_lift = 0.

let floor_mesh = Mesh.plane ~width:floor_width ~height:floor_height ()

let grid_mesh =
  let vertical =
    List.init 13 (fun index ->
      let x = float_of_int (index - 6) in
      (Float.max (-.half_width) (x -. line_half_width), -.half_height,
       Float.min half_width (x +. line_half_width), half_height))
  and horizontal =
    List.init 11 (fun index ->
      let y = float_of_int (index - 5) in
      (-.half_width, Float.max (-.half_height) (y -. line_half_width),
       half_width, Float.min half_height (y +. line_half_width)))
  in
  let vertices, indices, _ =
    List.fold_left
      (fun (vertices, indices, first) (x0, y0, x1, y1) ->
        ( vertices @ [
            Vec3.create x0 y0 grid_lift; Vec3.create x1 y0 grid_lift;
            Vec3.create x1 y1 grid_lift; Vec3.create x0 y1 grid_lift;
          ],
          indices @ [first; first + 1; first + 2; first; first + 2; first + 3],
          first + 4 ))
      ([], [], 0) (vertical @ horizontal)
  in
  Mesh.create_exn ~indices
    ~normals:(List.init (List.length vertices) (fun _ -> Vec3.unit_z))
    vertices

let floor_color = Color.hex_exn "#0f172a"
let grid_color = Color.hex_exn "#46a6b9"

let shader =
  Shader3.create ~varying_count:2
    ~vertex:(fun (input : Shader3.vertex_input) ->
      let output = Shader3.default_vertex input in
      { output with
        varyings = [output.world_position.x; output.world_position.z];
      })
    ~fragment:(fun (input : Shader3.fragment_input) ->
      match input.varyings with
      | [world_x; world_z] ->
          let near coordinate =
            abs_float (coordinate -. Float.round coordinate) < line_half_width
          in
          Shader3.output
            (if near world_x || near world_z then grid_color else floor_color)
      | _ -> Shader3.discard)
    ()

let floor nodes =
  Scene3.create ~samples:4 [
    Scene3.translate (Vec3.create 0. (-1.5) 0.) [
      Scene3.rotate ~axis:Vec3.unit_x (-.Float.pi /. 2.) nodes;
    ];
  ]

let () =
  let camera =
    Camera.perspective ~at:(Vec3.create 0. 1.8 8.)
      ~target:(Vec3.create 0. 0.2 0.) ()
  in
  let reference =
    Framebuffer3.render ~width:400 ~height:250 ~camera
      (floor [
         Scene3.mesh ~cull:Scene3.Cull_none ~shader
           ~material:(Material.unlit Color.white) floor_mesh;
       ])
  and optimized =
    Framebuffer3.render ~width:400 ~height:250 ~camera
      (floor [
         Scene3.mesh ~cull:Scene3.Cull_none
           ~material:(Material.unlit floor_color) floor_mesh;
         Scene3.with_depth
           (Scene3.depth_state ~comparison:Scene3.Always ()) [
           Scene3.mesh ~cull:Scene3.Cull_none
             ~material:(Material.unlit grid_color) grid_mesh;
         ];
       ])
  in
  let changed = ref 0 and maximum = ref 0 and total = ref 0 in
  let examples = ref [] in
  for y = 0 to 249 do
    for x = 0 to 399 do
      let left = Option.get (Framebuffer3.color_pixel reference ~x ~y)
      and right = Option.get (Framebuffer3.color_pixel optimized ~x ~y) in
      let lr, lg, lb, la = Color.to_tuple left
      and rr, rg, rb, ra = Color.to_tuple right in
      let difference =
        abs (lr - rr) + abs (lg - rg) + abs (lb - rb) + abs (la - ra)
      in
      if difference > 0 then incr changed;
      if difference > 0 && List.length !examples < 12 then
        examples := (x, y, left, right, difference) :: !examples;
      maximum := max !maximum difference;
      total := !total + difference
    done
  done;
  Printf.printf "changed=%d/100000 maximum_rgba_delta=%d total_rgba_delta=%d\n"
    !changed !maximum !total;
  List.rev !examples |> List.iter (fun (x, y, left, right, difference) ->
    Printf.printf "%d,%d %s -> %s delta=%d\n" x y
      (Color.to_string left) (Color.to_string right) difference);
  if !changed <> 0 then
    failwith "optimized floor geometry changed programmable floor pixels"
