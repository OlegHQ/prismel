open Procedural

type mode = Cube | Sphere

type parameters = {
  count : int
    [@sop.default 2] [@sop.label "Count"] [@sop.folder "Geometry"]
    [@sop.min 1] [@sop.max 5] [@sop.hard_min 1] [@sop.hard_max 10];
  enabled : bool
    [@sop.default true] [@sop.folder "Geometry"];
  amount : float
    [@sop.default 0.5] [@sop.folder "Look/Noise"]
    [@sop.min 0.] [@sop.max 1.] [@sop.impact "view"];
  title : string
    [@sop.default "Node SOP"] [@sop.folder "Look"]
    [@sop.impact "export"];
  mode : mode
    [@sop.default Cube] [@sop.folder "Geometry"]
    [@sop.kind Procedural.Parameter.choice ~equal:( = )
      ["Cube", Cube; "Sphere", Sphere]];
  internal : int [@sop.default 17] [@sop.ignore];
} [@@deriving sop_params]

let inspectable_node values =
  Custom.node ~label:"Selected shape" ~operation:"selected-shape"
    ~schema:parameters_schema ~values []
    (fun ~label ~inputs:_ ~parameters -> match parameters.mode with
      | Cube -> Sop.box ~label ~x_divisions:parameters.count ()
      | Sphere -> Sop.uv_sphere ~label ~segments:(max 3 parameters.count)
          ~radius:1. ())

let fail message = raise (Failure message)

let run () =
  if Sop_params_fixture.t_default.value <> 3
     || List.length (Parameter.fields Sop_params_fixture.t_schema) <> 1
  then fail "sop_params interface generation did not match implementation";
  if parameters_default <> {
      count = 2; enabled = true; amount = 0.5; title = "Node SOP";
      mode = Cube; internal = 17 }
     || parameters_default.internal <> 17
     || List.length (Parameter.fields parameters_schema) <> 5
  then fail "sop_params defaults or ignored-field policy is incorrect";
  let graph = inspectable_node parameters_default in
  let node_id = Node.id graph in
  let inspector = Sop_ui.Node_inspector.create ~prefix:"selected" graph in
  let ui = Pxui.Ui.create () in
  let frame time events : Prismel.Frame.t = { width = 320; height = 240;
    size = 320, 240; drawable_width = 320; drawable_height = 240;
    drawable_size = 320, 240; pixel_scale = 1., 1.; time; dt = 0.; fps = 0.;
    count = 0; mouse = 0, 0; mouse_delta = 0, 0; keys = []; mouse_buttons = [];
    events } in
  let step graph time events =
    Pxui.Ui.frame ui (frame time events) (fun ui ->
      Pxui.Ui.panel ui ~x:0. ~y:0. ~width:260. "inspector" (fun () ->
        match Sop_ui.Node_inspector.graph_widgets ~expanded:["Geometry"]
            inspector ui ~graph with
        | Ok value -> value | Error message -> fail message)) in
  let unchanged, effects = step graph 0. [] in
  if unchanged != graph || effects.cook then
    fail "an idle inspector frame changed the graph";
  (* Rows: node label, Geometry, count, enabled, mode, Look. The Enabled
     toggle occupies x in [217, 257) on row 3. *)
  let row index = 3 + (index * 24) + 12 in
  let click x y = [Prismel.Event.MousePressed (Prismel.Input.LeftButton, (x, y));
    Prismel.Event.MouseReleased (Prismel.Input.LeftButton, (x, y))] in
  let graph, effects = step graph 0.5 (click 230 (row 3)) in
  let field graph name = Graph.find graph ~node_id |> Option.get
    |> Node.parameter_fields |> List.find (fun field -> field.Parameter.name = name) in
  if not effects.cook || (field graph "enabled").current <> Parameter.Bool_value false
  then fail "inspector toggle did not apply through the node schema";
  let graph, _ = step graph 1. (click 200 (row 4)) in
  if (field graph "mode").current <> Parameter.Choice_value "Sphere"
  then fail "inspector choice did not apply";
  let graph, _ = step graph 1.5
      [Prismel.Event.MousePressed (Prismel.Input.LeftButton, (140, row 2));
       Prismel.Event.MouseMoved (400, row 2);
       Prismel.Event.MouseReleased (Prismel.Input.LeftButton, (400, row 2))] in
  if (field graph "count").current <> Parameter.Int_value 5
  then fail "inspector integer drag did not clamp to the soft range";
  let graph, effects = match Sop_ui.Node_inspector.reset inspector ~graph with
    | Ok value -> value | Error message -> fail message in
  if not effects.cook
     || (field graph "count").current <> Parameter.Int_value 2
     || (field graph "mode").current <> Parameter.Choice_value "Cube"
  then fail "selected-node reset did not restore PPX defaults";
  let normalized = match Node.apply_parameters (inspectable_node parameters_default)
      ["count", Parameter.Int_value 99] with
    | Ok (node, _) -> node | Error message -> fail message in
  if (Node.parameter_fields normalized |> List.find (fun field ->
      field.Parameter.name = "count")).current <> Parameter.Int_value 10
  then fail "hard range normalization changed";
  Pxui.Ui.destroy ui;
  print_endline "SOP UI tests passed"
