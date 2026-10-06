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

open Test_support

let run () =
  let wire = Rays_editor.Renderer.wire_color in
  assert (wire (Rays.Color.rgb 250 250 250) = Rays.Color.hex_exn "#285f77");
  assert (wire (Rays.Color.rgb 8 8 10) = Rays.Color.hex_exn "#bed7e1");
  (match Sop_params_fixture.Editor.factories with
   | [factory] ->
       assert (Edit_graph.factory_key factory = "vector_fixture");
       assert (Edit_graph.factory_slot_names factory = ["input"; "target"]);
       let node = Edit_graph.instantiate_optional factory [None; None] |> Result.get_ok in
       let fields = Node.parameter_fields node in
       assert (List.map (fun field -> field.Parameter.vec3) fields
           = [Some ("center", 0); Some ("center", 1); Some ("center", 2)]);
       assert (List.map (fun field -> field.Parameter.primary) fields = [true; false; false])
   | _ -> fail "PPX module alias did not produce the single registry entry");
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
  let ui = Pxui.Ui.create ~font_size:11 () in
  let frame time events : Rays.Frame.t = { width = 320; height = 240;
    size = 320, 240; drawable_width = 320; drawable_height = 240;
    drawable_size = 320, 240; pixel_scale = 1., 1.; time; dt = 0.; fps = 0.;
    count = 0; mouse = 0., 0.; mouse_delta = 0., 0.; keys = []; mouse_buttons = [];
    events } in
  let step graph time events =
    Pxui.Ui.frame ui (frame time events) (fun ui ->
      Pxui.Ui.panel ui ~x:0. ~y:0. ~width:260. "inspector" (fun () ->
        match Pxui.Ui.scope ui "selected" (fun () ->
          Pxui.Ui.label ui (Node.label graph);
          match Pxui_shell.Inspector.fields ui ~expanded:["Geometry"]
              (Node.parameter_fields graph) with
          | [] -> Ok (graph, Parameter.no_effects)
          | changes -> Node.apply_parameters graph changes) with
        | Ok value -> value | Error message -> fail message)) in
  let unchanged, effects = step graph 0. [] in
  if unchanged != graph || effects.cook then
    fail "an idle inspector frame changed the graph";
  (* The shared inspector rows are 24 points, below the label and the folder's section header
     (24 under 16 points of space). *)
  let row index = 24 + 40 + (index - 2) * 24 + 12 in
  let click x y = [Rays.Event.MousePressed (Rays.Input.LeftButton, (float x, float y));
    Rays.Event.MouseReleased (Rays.Input.LeftButton, (float x, float y))] in
  let graph, effects = step graph 0.5 (click 110 (row 3)) in
  let field graph name = Node.parameter_fields graph
    |> List.find (fun field -> field.Parameter.name = name) in
  if not effects.cook || (field graph "enabled").current <> Parameter.Bool_value false
  then fail "inspector toggle did not apply through the node schema";
  let graph, _ = step graph 1. (click 170 (row 4)) in
  let graph, _ = step graph 1.05 [] in
  let graph, _ = step graph 1.1 (click 170 (row 4 + 54)) in
  if (field graph "mode").current <> Parameter.Choice_value "Sphere"
  then fail "inspector choice did not apply";
  let graph, _ = step graph 1.5
      [Rays.Event.MousePressed (Rays.Input.LeftButton, (140., float (row 2)));
       Rays.Event.MouseMoved (400., float (row 2));
       Rays.Event.MouseReleased (Rays.Input.LeftButton, (400., float (row 2)))] in
  if (field graph "count").current <> Parameter.Int_value 5
  then fail "inspector integer drag did not clamp to the soft range";
  let changes = Node.parameter_fields graph
    |> List.map (fun field -> field.Parameter.name, field.default) in
  let graph, effects = match Node.apply_parameters graph changes with
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
  let flow_ui = Pxui.Ui.create ~font_size:11 () in
  let count = { (field graph "count") with Parameter.folder = [] } in
  let flow_row ?drive ?(locked = false) () : Pxui_shell.Inspector.flow_row = {
    path = "count"; fields = [count]; shown = true; locked;
    drive; live = Some "3" } in
  let flow_step ?(expanded = []) row events =
    let settle = frame 2. [] in
    ignore (Pxui.Ui.frame flow_ui settle (fun ui ->
      Pxui_shell.Inspector.flow_fields ui ~expanded ~pin_click:true [row]));
    Pxui.Ui.frame flow_ui (frame 2. events) (fun ui ->
      Pxui_shell.Inspector.flow_fields ui ~expanded ~pin_click:true [row]) in
  if flow_step (flow_row ()) (click 14 12)
      <> [Pxui_shell.Inspector.Pinned ("count", false)] then
    fail "Flow inspector pin did not emit the card-row request";
  (* the cross shows on the hovered row: hover first *)
  ignore (flow_step (flow_row ~drive:"← Clock.t" ~locked:true ()) [Rays.Event.MouseMoved (258., 12.)]);
  if flow_step (flow_row ~drive:"← Clock.t" ~locked:true ()) (click 258 12)
      <> [Pxui_shell.Inspector.Reset "count"] then
    fail "Flow inspector reset did not clear the drive";
  let expression_row = flow_row ~drive:"=t" ~locked:true () in
  ignore (flow_step expression_row (click 170 12));
  let edits = Pxui.Ui.frame flow_ui (frame 2. [Rays.Event.KeyPressed Rays.Input.End;
      Rays.Event.TextInput "*2";
      Rays.Event.KeyPressed Rays.Input.Enter]) (fun ui ->
        Pxui_shell.Inspector.flow_fields ui [expression_row]) in
  if edits <> [Pxui_shell.Inspector.Expression ("count", "=t*2")] then
    fail "Flow inspector expression field did not commit an edit";
  let box = Sop_catalog.Box.create () in
  let vector = Flow_sop.Port.parameters (Node.parameter_fields box)
    |> Result.get_ok |> List.find (fun (parameter : Flow_sop.Port.parameter) ->
      parameter.path = "size") in
  let vector_row : Pxui_shell.Inspector.flow_row = {
    path = vector.path;
    fields = List.map (fun field -> {field with Parameter.folder = []}) vector.fields;
    shown = true; locked = false; drive = None; live = None;
  } in
  if flow_step vector_row (click 258 12) <> [] then
    fail "a click beside a vector's cells changed the row";
  let color_f name current = {
    Parameter.name; label = String.capitalize_ascii name; description = None;
    folder = []; impact = Parameter.Cook; primary = false; unit = None; vec3 = Some ("color", 0);
    kind = Parameter.Floating_view { soft_min = 0.; soft_max = 1.; hard_min = Some 0.; hard_max = Some 1. };
    default = Parameter.Float_value 1.; current = Parameter.Float_value current;
  } in
  let color_row : Pxui_shell.Inspector.flow_row = {
    path = "color"; fields = [ color_f "color_r" 1.; color_f "color_g" 0.5; color_f "color_b" 0. ];
    shown = true; locked = false; drive = None; live = None;
  } in
  (* the hex field starts after the 20-point swatch and 8 points, at 12 + 6 + 8 + 68 + 8 + 28 in 280 *)
  ignore (flow_step color_row (click 170 12));
  let hex_edits = Pxui.Ui.frame flow_ui (frame 2. [
      Rays.Event.KeyPressed Rays.Input.End;
      Rays.Event.KeyPressed Rays.Input.Backspace;
      Rays.Event.KeyPressed Rays.Input.Backspace;
      Rays.Event.KeyPressed Rays.Input.Backspace;
      Rays.Event.KeyPressed Rays.Input.Backspace;
      Rays.Event.KeyPressed Rays.Input.Backspace;
      Rays.Event.KeyPressed Rays.Input.Backspace;
      Rays.Event.KeyPressed Rays.Input.Backspace;
      Rays.Event.KeyPressed Rays.Input.Backspace;
      Rays.Event.TextInput "#00ff00";
      Rays.Event.KeyPressed Rays.Input.Enter ]) (fun ui ->
        Pxui_shell.Inspector.flow_fields ui [ color_row ]) in
  if not (List.mem (Pxui_shell.Inspector.Edited ("color_g", Param.Float_value 1.)) hex_edits) then
    fail "Flow inspector color row hex edit did not update color channels";
  let folder_row = { (flow_row ()) with
    fields = [{count with Parameter.folder = ["Geometry"]}] } in
  if flow_step ~expanded:["Geometry"] folder_row (click 14 40)
      <> [Pxui_shell.Inspector.Pinned ("count", false)] then
    fail "Flow inspector did not show an initially expanded folder";
  ignore (flow_step ~expanded:["Geometry"] folder_row (click 10 16));
  if flow_step ~expanded:["Geometry"] folder_row (click 14 40) <> [] then
    fail "Flow inspector collapsed folder kept its field interactive";
  ignore (flow_step ~expanded:["Geometry"] folder_row (click 10 16));
  if flow_step ~expanded:["Geometry"] folder_row (click 14 40)
      <> [Pxui_shell.Inspector.Pinned ("count", false)] then
    fail "Flow inspector folder did not reopen";
  (match Sys.getenv_opt "RAYS_UI_PREVIEW" with
   | None -> ()
   | Some directory ->
       Rays.Sketch.export ~directory ~prefix:"flow-inspector" ~frames:1
         ~config:{Rays.Sketch.default_config with width=320; height=240}
         (fun _ -> Rays.Scene.clear (Rays.Color.hex_exn "#eef2ee")
           :: Pxui.Ui.scene flow_ui));
  Pxui.Ui.destroy flow_ui;
  Pxui.Ui.destroy ui;
  print_endline "SOP UI tests passed"
