
open Editor_document
module Settings = Settings
module Source = Source_file
module Workspace_doc = Workspace_doc

let workspace_catalog ?(factories = Sop_catalog.Editor.factories) () =
  Contexts.catalog ~version:Flow_sop.Manifest.version factories

type window = Contexts.window =
  { title : string; width : int; height : int; fps : int; seed : int }
let workspace_window = Contexts.window

type layout = Pxui_shell.Layout.t

let default_layout = Pxui_shell.Layout.default

module Renderer = Renderer

module Editor3 = struct
  include Environment.Make (Viewport3)

  type render_settings = Objects.Root.render = { width : int; height : int; max_spp : int }
  let render_camera value = (extra value).Viewport3.document_camera
  let view_camera value = view_camera value
  let render_settings value = Objects.Root.render (extra value).Viewport3.root
  let film value frame = film value frame

  type slot = { film : int * int; step : int; samples : int; max_spp : int; viewports : int }
  let slot value key =
    Option.map (fun (info : Renderer.info) ->
      { film = info.size; step = info.step; samples = info.samples; max_spp = info.cap;
        viewports = info.viewports })
      (Renderer.info (extra value).Viewport3.renderer ~key)
  let take_export value = take_export value
  let set_render_status value status = set_render_status value status
  let flying value = (extra value).Viewport3.fly <> None
  let look_through value = (extra value).Viewport3.look_through
  let renderer value = (extra value).Viewport3.renderer.mode
  let set_renderer value mode =
    {value with extra = {value.extra with Viewport3.renderer_request = Some mode}}

  let create ?layout ?name ?presets ?timeline_frames ?factories ?settings ?commands ?lights ?world ?camera ?lens
      ?background ?seed ?grain ?domains ?max_entries ?max_payload_bytes ?await ?carry_budget ~workspace ?source ~prepare ~scene3
      ?overlay ?status () =
    create ?layout ?name ?presets ?timeline_frames ?factories ?settings ?commands ?lights ?world ?camera ?lens
      ?background ?seed ?grain ?domains ?max_entries ?max_payload_bytes ?await ?carry_budget ~workspace ?source ~prepare
      ~draw:scene3 ?overlay ?status ()

  let run ?layout ?name ?presets ?timeline_frames ?factories ?settings ?commands ?lights ?world ?camera ?lens
      ?background ?seed ?grain ?domains ?max_entries ?max_payload_bytes ~config ~workspace ?source ~prepare
      ~scene3 ?overlay ?status () =
    run ?layout ?name ?presets ?timeline_frames ?factories ?settings ?commands ?lights ?world ?camera ?lens
      ?background ?seed ?grain ?domains ?max_entries ?max_payload_bytes ~config ~workspace ?source ~prepare
      ~draw:scene3 ?overlay ?status ()
end

module Editor2 = struct
  include Environment.Make (Viewport2)

  let create ?layout ?name ?presets ?timeline_frames ?factories ?settings ?commands ?lights ?world ?camera ?background
      ?seed ?grain ?domains ?max_entries ?max_payload_bytes ?await ?carry_budget ~workspace ~prepare ~scene2
      ?overlay ?status () =
    create ?layout ?name ?presets ?timeline_frames ?factories ?settings ?commands ?lights ?world ?camera ?background
      ?seed ?grain ?domains ?max_entries ?max_payload_bytes ?await ?carry_budget ~workspace ~prepare
      ~draw:scene2 ?overlay ?status ()

  let run ?layout ?name ?presets ?timeline_frames ?factories ?settings ?commands ?lights ?world ?camera ?background
      ?seed ?grain ?domains ?max_entries ?max_payload_bytes ~config ~workspace ~prepare
      ~scene2 ?overlay ?status () =
    run ?layout ?name ?presets ?timeline_frames ?factories ?settings ?commands ?lights ?world ?camera ?background
      ?seed ?grain ?domains ?max_entries ?max_payload_bytes ~config ~workspace ~prepare
      ~draw:scene2 ?overlay ?status ()
end

module Private = struct
  module Render_budget = struct let film = Renderer.film let next_turn = Renderer.next_turn end
  module Leader = Leader module Schedule = Schedule
  module Document = Document module Preset = Preset
  module Pick = Pick
  module Cook = Cook
  module Text_pane = Text_pane
  module Lisp_text = Lisp_text
  module Navigator = Navigator
  module Bars = Bars
end

module Workspace = struct
  type source = { path : string; digest : string }

  let load ?factories text =
    match workspace_catalog ?factories () with
    | Error d -> Error [ d ]
    | Ok catalog -> Workspace_doc.of_text catalog text

  (* A hand-written host: the checked document and its file, or the diagnostics and exit 1. *)
  let open_text ?factories ~path ~digest text =
    match load ?factories text with
    | Error ds ->
        List.iter (fun d -> prerr_endline (Flow.Diagnostic.report ~file:path ~source:text d)) ds;
        exit 1
    | Ok doc -> doc, Source.find ~path ~digest

  (* The viewport starts where the scene's first camera is (else the default orbit); the host's
     light below is a default of a workspace with no scene graph (Contexts.of_workspace).
     Piece preparation is shared with the hand-written shattered-cube host. *)
  (* Every [sop] graph of the document, lowered and compiled, for headless cooking. *)
  let sop_graphs ?(factories = Sop_catalog.Editor.factories) (doc : Workspace_doc.t) =
    let ( let* ) = Result.bind in
    let* lowered = Result.map_error Flow.Diagnostic.to_string
        (Flow_sop.Lower.workspace ~extra:Contexts.descriptors ~factories doc.source) in
    List.fold_right (fun (g : Flow_sop.Lower.graph) rest ->
      let* rest = rest in
      match g.root with
      | None -> Ok rest
      | Some node_id ->
          let* graph = Procedural.Edit_graph.compile_node g.network.geometry ~node_id in
          Ok ((g.name, graph) :: rest)) lowered.graphs (Ok [])

  let declared_camera ?(factories = Sop_catalog.Editor.factories) doc base =
    match Contexts.of_workspace ~factories doc with
    | Error _ -> base
    | Ok document ->
        let scene = document.Document.scene.graph.Flow_sop.Network.geometry in
        (match Option.bind (List.nth_opt (Objects.ids "camera" scene) 0) (fun node_id ->
            Option.bind (Procedural.Edit_graph.find scene ~node_id) Objects.Camera.of_node) with
         | Some (view, _) -> Prismel.Easy_camera.of_view ~eye:(Prismel.Camera.position view)
             ~target:(Prismel.Camera.target view) base
         | None -> base)

  let run ?factories ?source doc =
    let source = Option.bind source (fun { path; digest } -> Source.find ~path ~digest) in
    let window = match workspace_window doc with
      | Ok w -> w | Error d -> failwith (Flow.Diagnostic.to_string d) in
    let config = { Prismel.Sketch.default_config with width = window.width; height = window.height;
                   title = window.title; fps = Some window.fps } in
    let prepare _ = Sketch_support.Surface.of_output in
    let scene3 = Sketch_support.Surface.scene3 in
    let lights = [ Prismel.Light.directional ~direction:(Prismel.Vec3.create (-1.) (-1.4) (-0.8))
                     ~diffuse:Prismel.Color.white () ] in
    let camera = declared_camera ?factories doc (Prismel.Easy_camera.create ~target:Prismel.Vec3.zero ~distance:3.6
        ~azimuth:0.4 ~elevation:0.6 ()) in
    Editor3.run ~config ~lights ~camera ?factories ~seed:(Int64.of_int window.seed) ~workspace:doc ?source ~prepare ~scene3 ()

  let main ?factories ~path ~digest ~catalog text =
    let expected = Contexts.catalog_digest (Option.value ~default:Sop_catalog.Editor.factories factories) in
    if catalog <> expected then
      prerr_endline (path ^ ": built against another catalog; checking the source again");
    match load ?factories text with
    | Error ds ->
        List.iter (fun d -> prerr_endline (Flow.Diagnostic.report ~file:path ~source:text d)) ds;
        exit 1
    | Ok doc -> run ?factories ~source:{ path; digest } doc
end
