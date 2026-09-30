
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

  type render_settings = Objects.Camera.render = { width : int; height : int; max_spp : int }
  let render_camera value = (extra value).Viewport3.render_camera
  let view_camera value = view_camera value
  let render_settings value = (extra value).Viewport3.render
  let film value frame = film value frame
  let take_export value = take_export value
  let set_render_status value status = set_render_status value status
  let flying value = (extra value).Viewport3.fly <> None
  let look_through value = (extra value).Viewport3.look_through

  let create ?layout ?name ?presets ?timeline_frames ?factories ?settings ?commands ?lights ?world ?camera ?lens
      ?background ?seed ?grain ?domains ?max_entries ?max_payload_bytes ?await ~workspace ?source ~prepare ~scene3
      ?overlay ?status () =
    create ?layout ?name ?presets ?timeline_frames ?factories ?settings ?commands ?lights ?world ?camera ?lens
      ?background ?seed ?grain ?domains ?max_entries ?max_payload_bytes ?await ~workspace ?source ~prepare
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
      ?seed ?grain ?domains ?max_entries ?max_payload_bytes ?await ~workspace ~prepare ~scene2
      ?overlay ?status () =
    create ?layout ?name ?presets ?timeline_frames ?factories ?settings ?commands ?lights ?world ?camera ?background
      ?seed ?grain ?domains ?max_entries ?max_payload_bytes ?await ~workspace ~prepare
      ~draw:scene2 ?overlay ?status ()

  let run ?layout ?name ?presets ?timeline_frames ?factories ?settings ?commands ?lights ?world ?camera ?background
      ?seed ?grain ?domains ?max_entries ?max_payload_bytes ~config ~workspace ~prepare
      ~scene2 ?overlay ?status () =
    run ?layout ?name ?presets ?timeline_frames ?factories ?settings ?commands ?lights ?world ?camera ?background
      ?seed ?grain ?domains ?max_entries ?max_payload_bytes ~config ~workspace ~prepare
      ~draw:scene2 ?overlay ?status ()
end

module Private = struct
  module Leader = Leader module Schedule = Schedule
  module Document = Document module Preset = Preset
  module Pick = Pick
  module Cook = Cook
  module Text_pane = Text_pane
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
     light below is a default that a scene declaring a light replaces (Contexts.of_workspace).
     ponytail: the geometry is drawn as one mesh. *)
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

  let declared_camera doc base =
    match Contexts.of_workspace ~factories:Sop_catalog.Editor.factories doc with
    | Error _ -> base
    | Ok document ->
        let scene = document.Document.scene.graph.Flow_sop.Network.geometry in
        (match Option.bind (List.nth_opt (Objects.ids "camera" scene) 0) (fun node_id ->
            Option.bind (Procedural.Edit_graph.find scene ~node_id) Objects.Camera.of_node) with
         | Some (view, _) -> Prismel.Easy_camera.of_view ~eye:(Prismel.Camera.position view)
             ~target:(Prismel.Camera.target view) base
         | None -> base)

  let run ?source doc =
    let source = Option.bind source (fun { path; digest } -> Source.find ~path ~digest) in
    let window = match workspace_window doc with
      | Ok w -> w | Error d -> failwith (Flow.Diagnostic.to_string d) in
    let config = { Prismel.Sketch.default_config with width = window.width; height = window.height;
                   title = window.title; fps = Some window.fps } in
    let prepare _ output = Pdk_prismel.Prismel_mesh.to_mesh output.Procedural.Session.geometry
      |> Result.map_error Pdk.Error.to_string in
    let scene3 _ mesh = Prismel.Scene3.create [ Prismel.Scene3.mesh ~cull:Prismel.Scene3.Cull_none mesh ] in
    let lights = [ Prismel.Light.directional ~direction:(Prismel.Vec3.create (-1.) (-1.4) (-0.8))
                     ~diffuse:Prismel.Color.white () ] in
    let camera = declared_camera doc (Prismel.Easy_camera.create ~target:Prismel.Vec3.zero ~distance:3.6
        ~azimuth:0.4 ~elevation:0.6 ()) in
    Editor3.run ~config ~lights ~camera ~seed:(Int64.of_int window.seed) ~workspace:doc ?source ~prepare ~scene3 ()

  let main ~path ~digest ~catalog text =
    if catalog <> Contexts.catalog_digest Sop_catalog.Editor.factories then
      prerr_endline (path ^ ": built against another catalog; checking the source again");
    match load text with
    | Error ds ->
        List.iter (fun d -> prerr_endline (Flow.Diagnostic.report ~file:path ~source:text d)) ds;
        exit 1
    | Ok doc -> run ~source:{ path; digest } doc
end
