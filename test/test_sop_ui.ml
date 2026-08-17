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

let () =
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
  let inspector = Sop_ui.Node_inspector.create ~prefix:"selected" graph in
  let ui = Pxui.create ~x:0 ~y:0 ~width:260 ()
      |> Sop_ui.Node_inspector.append
           ~expanded:["Geometry"; "Look/Noise"] inspector ~graph in
  if Pxui.int_slider_value ui "selected.count" <> Some 2
     || Pxui.choice_value ui "selected.mode" <> Some "Cube"
     || Pxui.accordion_expanded ui "selected.folder.Geometry" <> Some true
     || Pxui.accordion_expanded ui "selected.folder.Look" <> Some false
  then fail "selected-node inspector did not render PPX fields and folders";
  let node_id = Node.id graph in
  let graph, ui, effects = match Sop_ui.Node_inspector.update inspector
      ~graph ~ui [Pxui.Int_slid ("selected.count", 99);
        Pxui.Toggled ("selected.enabled", false);
        Pxui.Slid ("selected.amount", 2.5);
        Pxui.Text_changed ("selected.title", "Export me");
        Pxui.Selected ("selected.mode", "Sphere");
        Pxui.Slid ("camera.fov", 90.)] with
    | Ok value -> value | Error message -> fail message in
  let selected = Graph.find graph ~node_id |> Option.get in
  let field name = Node.parameter_fields selected
      |> List.find (fun field -> field.Parameter.name = name) in
  if not effects.cook || not effects.view || not effects.export
     || Node.id selected <> node_id
     || (field "count").current <> Parameter.Int_value 10
     || (field "amount").current <> Parameter.Float_value 2.5
     || (field "title").current <> Parameter.Text_value "Export me"
     || (field "mode").current <> Parameter.Choice_value "Sphere"
     || Pxui.int_slider_value ui "selected.count" <> Some 10
  then fail "selected-node batch edit lost effects, identity, or normalization";
  let graph, ui, effects = match Sop_ui.Node_inspector.reset inspector
      ~graph ~ui with
    | Ok value -> value | Error message -> fail message in
  let selected = Graph.find graph ~node_id |> Option.get in
  if not effects.cook || not effects.view || not effects.export
     || (Node.parameter_fields selected
         |> List.find (fun field -> field.Parameter.name = "count")).current
        <> Parameter.Int_value 2
     || Pxui.choice_value ui "selected.mode" <> Some "Cube"
  then fail "selected-node reset did not restore PPX defaults";
  print_endline "SOP UI tests passed"
