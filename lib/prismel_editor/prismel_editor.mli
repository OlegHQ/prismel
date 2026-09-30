(** Reusable graph-driven procedural sketch environments.

    Both environments share a responsive view/graph/inspector workspace,
    persistent graph navigation, generated node inspection, bounded
    asynchronous cooking, status UI, and finite native execution. Their thin
    adapters own only the dimensional camera, viewport composition, and
    still-image renderer. Overlay callbacks receive a frame and coordinates
    local to the current view pane. *)

(** Sketch-owned settings in the editor document. *)
module Settings : sig
  type t
  val none : t
  val make : 'record Editor_core.Param.schema -> 'record -> t
  (** Settings drawn in the inspector while no node is selected. *)

  val get : 'record Editor_core.Param.schema -> t -> 'record
  (** Read the current record back; raises [Invalid_argument] when [schema]
      does not describe it. *)
end

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

(** Default 45% view, 35% graph, and 20% inspector proportions. *)
val default_layout : layout

(** Editor internals exposed for tests and diagnostics.
    Layout and chrome live in [Pxui_shell]; sketches use [Editor3]/[2]. *)
module Private : sig
  (** Unstable test and diagnostic hooks. These are outside the supported
      sketch API and may change without compatibility shims. *)
  (** Helix-style leader keys. Space (while no text field is focused) opens a
      centered which-key panel; the next key runs a binding from the global
      scope or from the focused pane, the one last clicked. Escape, Space, an
      unknown key, a click, or window focus loss cancel it. *)
  module Leader : sig
    type action =
      | Save_preset | Browse_presets
      | Toggle_timeline | Toggle_graph | Toggle_inspector | Hide_ui | Open_camera
      | Play_pause | Reset | Stop
      | Add_node | Layout | Frame_tile | Frame_camera
      | Look_through | Fly | Tool of int
      | Undo | Redo
      | Toggle_projection | Enter | Up | Go_world | Group | Ungroup | Make_unique
      | World_emit | World_reseed | World_time of float | World_play | World_preset of int
      | Graph_command of Pxui_graph.command
      | List_command of Pxui_shell.Tree.command
      | Guide_toggle | Guide_keys
      | Command_palette
      | Sketch_command of string

    type command = (Pxui_shell.Layout.column, action) Editor_core.Command.t

    type state = Editor_core.Router.state = Idle | Pending of string

    val keymap : command list
    (** The single table behind dispatch, which-key, and the palette. *)

    val keymap3 : command list
    (** [keymap] plus the 3D view commands ([w] fly, [v] look through). *)

  end

  (** [timeline_frames] (default 240) is the scrub range of the timeline bar,
      extended while playback runs past it. [name] (default ["sketch"]; [run]
      uses the window title) is recorded in presets, which live in [presets]
      (default [~/.prismel/<name>]): [Space s] saves the full document under a
      typed name (prefilled with the time), [Space b] searches, loads (Enter, one
      undo entry), and deletes (Delete twice) them. See {!Preset}. *)

  (** Effect- and dependency-aware cook scheduler. It fires initially, after a
      committed cook parameter change, after [force], and whenever the sketch
      clock changed and any reachable node declares [Time] or [Frame]. While a
      primary-pointer edit is held it cooks only when [live] (the inspector's
      "Live update while dragging", on by default) and the worker is idle;
      otherwise only the latest desired cook is retained until release. *)
  module Document : sig
    type t
    val scene_graph : t -> Procedural.Edit_graph.t
    val object_network : t -> int -> (Flow_sop.Network.t * int option) option
    (** An object's immutable network and optional geometry display node.
        A missing owner returns [None]; an empty geometry network has no display. *)

    val positions : t -> int -> (int * float * float) list option
  end

  (** Presets: the scene, every object's geometry/value/drive network, the
      active camera, and settings as version 3 JSON with Flow layout. *)
  module Preset : sig
    type loaded = { doc : Document.t; view : Yojson.Safe.t }
    val sanitize : string -> string
    val default_name : unit -> string
    val path : directory:string -> name:string -> string
    val save : directory:string -> name:string -> sketch:string -> doc:Document.t ->
      view:Yojson.Safe.t -> (string, string) result
    val list : directory:string -> (string * float) list
    val delete : directory:string -> name:string -> (unit, string) result
    val load : path:string -> code:Procedural.Graph.t ->
      factories:Procedural.Edit_graph.factory list -> settings:Settings.t ->
      (loaded, string) result
  end

  module Schedule : sig
    type t
    val initial : t
    val step :
      ?live:bool -> t -> graphs:Procedural.Graph.t list -> effects:Procedural.Parameter.effects ->
      context_changed:bool -> force:bool -> busy:bool -> frame:Prismel.Frame.t ->
      t * bool
  end

  (** Host cook boundary, exposed for deterministic worker tests and measurements. *)
  module Cook : sig
    type bounds = Prismel.Vec3.t * Prismel.Vec3.t
    type 'prepared piece = {
      id : int;
      graph : Procedural.Graph.t;
      prepared : 'prepared;
      bounds : bounds option;
      settings : Settings.t;
      context : string;
    }
    type 'prepared t
    type 'prepared update = {
      cook : 'prepared t;
      edit_error : string option;
      prepared_changed : bool;
      framed : bounds option option;
    }
    val create : prepare:(Settings.t -> Procedural.Session.output -> ('a, string) result) ->
      seed:int64 -> grain:int -> ?domains:int -> ?await:bool -> max_entries:int ->
      max_payload_bytes:int -> unit -> ('a t, string) result
    (** [await] (default: [PRISMEL_MAX_FRAMES] is set) makes [update] block on
        the cook it submits, so a fixed-step run shows exactly frame n. *)
    val status : 'a t -> Procedural.Async_cook.status
    val set_volatile : 'a t -> (int -> bool) -> unit
    (** Pass [Flow_sop.Lower.is_volatile lowered] after each lowering (W3). *)
    val stats : 'a t -> Procedural.Session.stats
    val seconds : 'a t -> float option
    (** The last completed cook, in seconds. *)
    val pieces : 'a t -> 'a piece list
    val applied : 'a t -> int -> Flow_sop.Value_lane.resolved option
    val force : 'a t -> 'a t
    val update : ?live:bool ->
      definitions:Editor_document.Document.definition
        Editor_document.Document.String_map.t ->
      compiled_ids:int Flow_sop.Instance_path.Map.t ->
      'a t -> settings:Settings.t ->
      objects:(int * Flow_sop.Network.t * int) list -> edit_error:string option ->
      effects:Procedural.Parameter.effects -> timeline_changes:Sketch_support.Timeline.change list ->
      timeline:Sketch_support.Timeline.t -> frame:Prismel.Frame.t ->
      frame_request:(int * int) option -> 'a update
    val close : 'a t -> unit
  end
end

(** The renderer choice a sketch offers in its settings block: one shared
    field, so the control reads the same in every sketch. The sketch's
    [prepare] reads it back through its own schema. *)
module Renderer : sig
  type t = Path_traced | Raster | Wireframe

  val field :
    default:t -> get:('record -> t) -> set:(t -> 'record -> 'record) ->
    'record Editor_core.Param.field
  (** The ["renderer"] field labelled "Renderer". *)

  val of_env : string -> t option
  (** ["path"], ["raster"], or ["wireframe"] from an environment variable. *)

  val wire_mesh : Pdk.Geometry.t -> (Prismel.Mesh.t, string) result
  (** Every polygon edge once, as a line mesh for the wireframe renderer. *)

  val wire_color : Prismel.Color.t -> Prismel.Color.t
  (** A contrasting blue wire color for a light or dark viewport background. *)
end

module Editor3 : sig
  type 'prepared t
  type nonrec layout = layout
  val default_layout : layout

  val create :
    ?layout:layout ->
    ?name:string ->
    ?presets:string ->
    ?timeline_frames:int ->
    ?factories:Procedural.Edit_graph.factory list ->
    ?settings:Settings.t ->
    ?commands:(Pxui_shell.Layout.column, 'prepared t -> 'prepared t) Editor_core.Command.t list ->
    ?lights:Prismel.Light.t list ->
    ?world:Prismel.World.t ->
    ?camera:Prismel.Easy_camera.t ->
    ?lens:Prismel.Camera.lens ->
    ?background:Prismel.Color.t ->
    ?seed:int64 ->
    ?grain:int ->
    ?domains:int ->
    ?max_entries:int ->
    ?max_payload_bytes:int ->
    ?graph:Procedural.Graph.t ->
    ?program:Flow_sop.Program.t ->
    prepare:(Settings.t -> Procedural.Session.output -> ('prepared, string) result) ->
    scene3:(Procedural.Graph.t -> 'prepared -> Prismel.Scene3.t) ->
    ?overlay:(Procedural.Graph.t -> 'prepared option -> Prismel.Frame.t ->
      Prismel.Scene.t) ->
    ?status:('prepared option -> string option) ->
    unit ->
    ('prepared t, string) result
  (** [lens] is the default camera object's depth of field (pinhole
      otherwise). [prepare] runs on the cook worker domain with submission settings.
      It must only do pure CPU work on immutable/disjointly owned data;
      SDL, Metal, textures, fonts, audio, UI and runtime caches stay on the
      initial domain. [scene3] and [overlay] run on the initial domain. *)

  val update : 'prepared t -> Prismel.Frame.t -> 'prepared t

  val update_with :
    'prepared t -> Prismel.Frame.t -> inspector:(Pxui.Ui.t -> 'a) ->
    'prepared t * 'a option
  (** [update], also building sketch-owned kit widgets below the camera and
      render sections shown while no node is selected. The result is [None]
      on frames where that panel is not built. *)

  (* Call from [Sketch.run_state ~after_present] when driving the environment
      manually so PNG requests save the completed frame. *)
  val after_present : 'prepared t -> Prismel.Frame.t -> 'prepared t

  val settings : 'prepared t -> Settings.t
  val set_settings : 'prepared t -> Settings.t -> 'prepared t
  (** Replace the sketch settings from code: one undo step and a fresh cook,
      since [prepare] receives them. Inspector edits do the same. *)

  (* [?status] text joins the status bar under the view (cook state, then
     the sketch's line, e.g. renderer stats); keep view overlays for pictures. *)
  (* [?commands] (on [create]/[run]) add sketch [Editor_core.Command]s to the
     same table as the built-ins: triggers join key routing and which-key, and
     scoped commands appear while their pane has focus. A command's [action]
     gets this environment after the frame. [create] rejects reserved IDs,
     overlapping triggers and leader prefixes, and aliases with different
     action closures. Bind each alias to the same action value. Chord keys
     and leader sequences are case-insensitive; modifier lists are normalized. *)

  (** The workspace keeps one [Editor_core.History] history of the editable document:
      graph edits and inspector commits are entries, continuous slider drags
      collapse into one, and Command/Ctrl-Z, Shift-Command/Ctrl-Z, and
      Ctrl-Y step it. *)
  val can_undo : 'prepared t -> bool
  val can_redo : 'prepared t -> bool
  val scene : 'prepared t -> Prismel.Frame.t -> Prismel.Scene.t
  val close : 'prepared t -> unit
  val crash_dump : 'prepared t -> string -> unit
  (** Write the document (a preset) and editor state into a crash report
      folder; pass it as [Sketch.run_state ~crash_dump] when driving the
      editor from your own [run_state]. [run] does this itself. *)
  val graph : 'prepared t -> Procedural.Graph.t
  val document : 'prepared t -> Procedural.Edit_graph.t
  val selected_node : 'prepared t -> Procedural.Node.t option
  val displayed_node : 'prepared t -> Procedural.Node.t
  val prepared : 'prepared t -> 'prepared option
  val camera : 'prepared t -> Prismel.Easy_camera.t
  (** The interactive viewport camera. *)

  val render_camera : 'prepared t -> Prismel.Camera.t
  (** The ACTIVE camera object's view and lens (the viewport camera when the
      document has none). A default camera following the viewport is added
      to a document without one, and again if the last is deleted (inside
      the same undo entry). With follow viewport on, viewport motion writes
      the node (one undo entry per gesture) and node edits or undo move the
      viewport. PNG export and look-through use it. *)

  type render_settings = { width : int; height : int; max_spp : int }

  val render_settings : 'prepared t -> render_settings
  (** The ACTIVE camera object's Render folder: output resolution in pixels
      (its aspect also frames look-through) and the samples per pixel at
      which a sketch's progressive renderer stops. *)

  val film : 'prepared t -> Prismel.Frame.t -> int * int * int * int
  (** The rect inside the view pane (pane-relative) that the render fills:
      the whole pane, or the render camera's aspect fitted and centred while
      looking through it. The editor paints its own 3D view into it and
      draws the sketch [overlay] inside it, with a [Frame.t] of its size, so
      an overlay drawing a film at the origin needs nothing else. *)

  val take_export : 'prepared t -> 'prepared t * string option
  (** The output path of a "Render / save PNG" request made this frame,
      taken over by the sketch (the editor then does not capture the screen
      in [after_present]); call it after [update] and before
      [after_present]. A sketch renderer exports at [render_settings]. *)

  val set_render_status : 'prepared t -> string option -> 'prepared t
  (** Replaces the status bar's render text, e.g. an export's progress. *)

  val view_camera : 'prepared t -> Prismel.Camera.t
  (** What the view pane shows this frame, for a sketch's own renderer:
      [render_camera] while looking through it, otherwise the viewport camera
      with the ACTIVE camera's lens (focused on the orbit target unless the
      camera follows the viewport). With follow viewport off, the view orbits
      freely around the camera object, whose frustum, aim line, and eye
      marker are drawn over the sketch's overlay; clicking the eye selects
      it, and W shows a handle sliding its target along the view direction,
      its focus distance. The Viewport section pairs the look-through toggle
      with "Camera follows viewport" (the ACTIVE camera's own parameter, one
      undo entry), so a fixed camera is set up by looking through it and
      orbiting. *)

  val flying : 'prepared t -> bool
  (** [Space w] with the view focused: held W/S/A/D/Q/E fly the viewport
      camera ([Easy_camera.fly]) with the pointer captured through
      [Sketch.set_relative_mouse]. Escape or focus loss exits; Space exits and
      opens the leader. *)

  val look_through : 'prepared t -> bool
  (** The view shows [render_camera] ([Space v], or the Camera panel toggle);
      orbit input is frozen unless the active camera follows the viewport. *)

  val timeline : 'prepared t -> Sketch_support.Timeline.t
  val panes : 'prepared t -> Prismel.Frame.t -> Pxui_shell.Layout.panes
  val graph_nodes : 'prepared t -> Pxui_graph.node_view list

  (** {2 Scene}

      The document is a scene of objects above the SOP networks. The code
      [graph] is the geometry object [geo1]; [?lights] become light objects
      and [?world] the World. The graph pane shows the open level as a graph
      or a list ([Space l]): [i], a double-click, or activating a list row
      enters a geometry object's SOP network or the World's layer stack, and
      [u] goes back up; [Space e] opens the World (created on first use), and
      [Space a] opens the add menu of the open level (objects, SOPs, or World
      layers): hover a category for its submenu, or type to search. Object transforms place each object's cook as a
      whole, so moving one never re-cooks SOPs. [graph], [document],
      [prepared], and [displayed_node] describe the open (else the first)
      geometry object. *)

  val level : 'prepared t -> string option
  (** The object whose network is open; [None] at the scene level. *)

  val scene_document : 'prepared t -> Procedural.Edit_graph.t
  (** Objects as nodes: input 0 is the parent, parameters the transform. *)

  val objects : 'prepared t -> (Prismel.Mat4.t * 'prepared) list
  (** Visible, renderable geometry objects' latest cooks at their world
      transforms, e.g. for a sketch's own path tracer. *)

  val lights : 'prepared t -> Prismel.Light.t list
  (** Visible, renderable light objects in world space. *)

  val world : 'prepared t -> Prismel.World.baked option
  (** This frame's World bake (preview size during a gesture or playback),
      or [None] without a World. *)

  val run :
    ?layout:layout ->
    ?name:string ->
    ?presets:string ->
    ?timeline_frames:int ->
    ?factories:Procedural.Edit_graph.factory list ->
    ?settings:Settings.t ->
    ?commands:(Pxui_shell.Layout.column, 'prepared t -> 'prepared t) Editor_core.Command.t list ->
    ?lights:Prismel.Light.t list ->
    ?world:Prismel.World.t ->
    ?camera:Prismel.Easy_camera.t ->
    ?lens:Prismel.Camera.lens ->
    ?background:Prismel.Color.t ->
    ?seed:int64 ->
    ?grain:int ->
    ?domains:int ->
    ?max_entries:int ->
    ?max_payload_bytes:int ->
    config:Prismel.Sketch.config ->
    ?graph:Procedural.Graph.t ->
    ?program:Flow_sop.Program.t ->
    prepare:(Settings.t -> Procedural.Session.output -> ('prepared, string) result) ->
    scene3:(Procedural.Graph.t -> 'prepared -> Prismel.Scene3.t) ->
    ?overlay:(Procedural.Graph.t -> 'prepared option -> Prismel.Frame.t ->
      Prismel.Scene.t) ->
    ?status:('prepared option -> string option) ->
    unit ->
    unit
end

module Editor2 : sig
  type 'prepared t
  type nonrec layout = layout
  val default_layout : layout

  val create :
    ?layout:layout ->
    ?name:string ->
    ?presets:string ->
    ?timeline_frames:int ->
    ?factories:Procedural.Edit_graph.factory list ->
    ?settings:Settings.t ->
    ?commands:(Pxui_shell.Layout.column, 'prepared t -> 'prepared t) Editor_core.Command.t list ->
    ?lights:Prismel.Light.t list ->
    ?world:Prismel.World.t ->
    ?camera:Prismel.Easy_camera2.t ->
    ?background:Prismel.Color.t ->
    ?seed:int64 ->
    ?grain:int ->
    ?domains:int ->
    ?max_entries:int ->
    ?max_payload_bytes:int ->
    ?graph:Procedural.Graph.t ->
    ?program:Flow_sop.Program.t ->
    prepare:(Settings.t -> Procedural.Session.output -> ('prepared, string) result) ->
    scene2:(Procedural.Graph.t -> 'prepared -> Prismel.Scene.t) ->
    ?overlay:(Procedural.Graph.t -> 'prepared option -> Prismel.Frame.t ->
      Prismel.Scene.t) ->
    ?status:('prepared option -> string option) ->
    unit ->
    ('prepared t, string) result
  (** [prepare] runs on the cook worker domain with submission settings.
      It must only do pure CPU work on immutable/disjointly owned data;
      SDL, Metal, textures, fonts, audio, UI and runtime caches stay on the
      initial domain. [scene2] and [overlay] run on the initial domain. *)

  val update : 'prepared t -> Prismel.Frame.t -> 'prepared t
  val update_with :
    'prepared t -> Prismel.Frame.t -> inspector:(Pxui.Ui.t -> 'a) ->
    'prepared t * 'a option
  (** [update], also building sketch-owned widgets in the unselected inspector.
      The result is [None] when that panel is not built. *)

  (* Call from [Sketch.run_state ~after_present] when driving the environment
      manually so PNG requests save the completed frame. *)
  val after_present : 'prepared t -> Prismel.Frame.t -> 'prepared t
  val settings : 'prepared t -> Settings.t
  val set_settings : 'prepared t -> Settings.t -> 'prepared t
  val can_undo : 'prepared t -> bool
  val can_redo : 'prepared t -> bool
  val scene : 'prepared t -> Prismel.Frame.t -> Prismel.Scene.t
  val close : 'prepared t -> unit
  val crash_dump : 'prepared t -> string -> unit
  (** Write the document (a preset) and editor state into a crash report
      folder; pass it as [Sketch.run_state ~crash_dump] when driving the
      editor from your own [run_state]. [run] does this itself. *)
  val graph : 'prepared t -> Procedural.Graph.t
  val document : 'prepared t -> Procedural.Edit_graph.t
  val selected_node : 'prepared t -> Procedural.Node.t option
  val displayed_node : 'prepared t -> Procedural.Node.t
  val prepared : 'prepared t -> 'prepared option
  val camera : 'prepared t -> Prismel.Easy_camera2.t
  val timeline : 'prepared t -> Sketch_support.Timeline.t
  val panes : 'prepared t -> Prismel.Frame.t -> Pxui_shell.Layout.panes
  val graph_nodes : 'prepared t -> Pxui_graph.node_view list

  val run :
    ?layout:layout ->
    ?name:string ->
    ?presets:string ->
    ?timeline_frames:int ->
    ?factories:Procedural.Edit_graph.factory list ->
    ?settings:Settings.t ->
    ?commands:(Pxui_shell.Layout.column, 'prepared t -> 'prepared t) Editor_core.Command.t list ->
    ?lights:Prismel.Light.t list ->
    ?world:Prismel.World.t ->
    ?camera:Prismel.Easy_camera2.t ->
    ?background:Prismel.Color.t ->
    ?seed:int64 ->
    ?grain:int ->
    ?domains:int ->
    ?max_entries:int ->
    ?max_payload_bytes:int ->
    config:Prismel.Sketch.config ->
    ?graph:Procedural.Graph.t ->
    ?program:Flow_sop.Program.t ->
    prepare:(Settings.t -> Procedural.Session.output -> ('prepared, string) result) ->
    scene2:(Procedural.Graph.t -> 'prepared -> Prismel.Scene.t) ->
    ?overlay:(Procedural.Graph.t -> 'prepared option -> Prismel.Frame.t ->
      Prismel.Scene.t) ->
    ?status:('prepared option -> string option) ->
    unit ->
    unit
end
