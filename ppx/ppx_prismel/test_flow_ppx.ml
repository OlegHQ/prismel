module Rings = struct
  let mode_kind = Procedural.Parameter.choice ~equal:String.equal
    ["solid", "solid"; "wire", "wire"]
  type parameters = {
    radius : float [@sop.default 1.] [@sop.min 0.] [@sop.max 3.];
    active : bool [@sop.default true];
    steps : int [@sop.default 2] [@sop.min 1] [@sop.max 8];
    center_x : float [@sop.default 0.] [@sop.min (-3.)] [@sop.max 3.]
      [@sop.vec3 "center"];
    center_y : float [@sop.default 0.] [@sop.min (-3.)] [@sop.max 3.]
      [@sop.vec3 "center"];
    center_z : float [@sop.default 0.] [@sop.min (-3.)] [@sop.max 3.]
      [@sop.vec3 "center"];
    mode : string [@sop.default "solid"] [@sop.kind mode_kind];
  } [@@sop.node_key "rings"] [@@sop.node_label "Rings"]
    [@@sop.node_category "Test"] [@@sop.node_inputs 0]
    [@@deriving sop_params, sop_node]

  let build = parameters_build (fun ~label parameters ->
    Procedural.Sop.box ~label
      ~size:(Prismel.Vec3.create parameters.radius parameters.radius
        parameters.radius)
      ~center:(Prismel.Vec3.create parameters.center_x parameters.center_y
        parameters.center_z) ())
  let factory = parameters_factory build
end [@@sop.register]

let program = [%flow {|(graph demo :context sop
  (let* [cube (sop/box :size [1 2 3])
         moved (sop/transform cube)]
    moved))|}]

let local_program = [%flow {|(graph local :context sop
  (let* [rings (user/rings :radius 2 :active true :steps 3
           :center [1 2 3] :mode "wire")] rings))|}]

let expression_program = [%flow {|(graph expression :context sop
  (sop/box :size [1 (sin t) 1]))|}]

let invalid_custom = lazy [%flow {|(graph local :context sop
  (user/rings :mode "missing"))|}]

let () =
  assert (program.Flow_sop.Program.name = "demo");
  assert (program.display = Some 2);
  assert (List.length (Procedural.Edit_graph.inspect program.network.geometry) = 2);
  assert (local_program.display = Some 1);
  assert (expression_program.display = Some 1);
  assert (List.length (Procedural.Edit_graph.inspect
    local_program.network.geometry) = 1);
  (try ignore (Lazy.force invalid_custom); assert false
   with Invalid_argument _ -> ())
