
module Preset = Preset
module Settings = Settings

type layout = Pxui_shell.Layout.config = {
  view_ratio : float;
  graph_ratio : float;
  inspector_ratio : float;
  splitter_width : int;
  collapsed_width : int;
  header_height : int;
  status_height : int;
  min_view_width : int;
  min_graph_width : int;
  min_inspector_width : int;
}

let default_layout = Pxui_shell.Layout.default

module Editor3 = struct
  include Environment.Make (Viewport3)

  let render_camera value = (extra value).Viewport3.render_camera
  let flying value = (extra value).Viewport3.fly <> None
  let look_through value = (extra value).Viewport3.look_through

  let create ?layout ?name ?presets ?timeline_frames ?factories ?settings ?commands ?camera ?background
      ?seed ?grain ?domains ?max_entries ?max_payload_bytes ~graph ~prepare ~scene3
      ?overlay ?status () =
    create ?layout ?name ?presets ?timeline_frames ?factories ?settings ?commands ?camera ?background
      ?seed ?grain ?domains ?max_entries ?max_payload_bytes ~graph ~prepare
      ~draw:scene3 ?overlay ?status ()

  let run ?layout ?name ?presets ?timeline_frames ?factories ?settings ?commands ?camera ?background
      ?seed ?grain ?domains ?max_entries ?max_payload_bytes ~config ~graph ~prepare
      ~scene3 ?overlay ?status () =
    run ?layout ?name ?presets ?timeline_frames ?factories ?settings ?commands ?camera ?background
      ?seed ?grain ?domains ?max_entries ?max_payload_bytes ~config ~graph ~prepare
      ~draw:scene3 ?overlay ?status ()
end

module Editor2 = struct
  include Environment.Make (Viewport2)

  let create ?layout ?name ?presets ?timeline_frames ?factories ?settings ?commands ?camera ?background
      ?seed ?grain ?domains ?max_entries ?max_payload_bytes ~graph ~prepare ~scene2
      ?overlay ?status () =
    create ?layout ?name ?presets ?timeline_frames ?factories ?settings ?commands ?camera ?background
      ?seed ?grain ?domains ?max_entries ?max_payload_bytes ~graph ~prepare
      ~draw:scene2 ?overlay ?status ()

  let run ?layout ?name ?presets ?timeline_frames ?factories ?settings ?commands ?camera ?background
      ?seed ?grain ?domains ?max_entries ?max_payload_bytes ~config ~graph ~prepare
      ~scene2 ?overlay ?status () =
    run ?layout ?name ?presets ?timeline_frames ?factories ?settings ?commands ?camera ?background
      ?seed ?grain ?domains ?max_entries ?max_payload_bytes ~config ~graph ~prepare
      ~draw:scene2 ?overlay ?status ()
end

module Private = struct
  module Workspace = Workspace module Leader = Leader module Schedule = Schedule
end
