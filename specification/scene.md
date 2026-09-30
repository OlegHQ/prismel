# Scene tree

Prismel Editor navigates between the scene and each geometry object’s SOP
network (the World has its layer stack instead). SOP networks hold shared
compound definitions created by grouping SOP and value nodes. Entering an
instance with `i` or double-click follows its instance path into the shared
definition; `u` returns to and selects the parent instance. There is no
"no subnetworks" limit within SOP networks. Every network records its
`sop`, `scene`, or `world` context.

`Space l` cycles graph → list → text. Converting the scene and
World into full Flow contexts remains for a later revision of `flow.md`.

## Objects are nodes

The scene is itself an `Edit_graph`: every object is a node, input 0 is its
parent, and parameters hold its transform and kind settings. The graph view,
the list, the inspector, translate handles, copy/paste/duplicate, presets,
and undo therefore work on objects without a second code path. The scene
network is presentation only and never cooks.

| Kind | Operation | Parameters | Network |
|---|---|---|---|
| Geometry | `geometry` | translate, rotate (degrees, applied Z·Y·X), scale, visible, renderable | a SOP network |
| Light | `light` | type (area, point, spot, directional), translate, target, color, intensity, width/height, cone, visible, renderable | none |
| Camera | `camera` | eye, target, up, fov, near/far, follow viewport, aperture, focus distance (0: the target), render width/height (pixels), max samples per pixel | none; never parented |
| World | `world` | background, rotation, exposure, time of day, day cycle, latitude, day of year, sun linking | its layer stack |

`Document.t` holds the scene network, one network per geometry object and
per World (keyed by object id), the active camera object, and the sketch
`Settings`. History snapshots it; the open level, selection, projection
(graph, list, or text), and the map view are view state. A deleted object's
network goes with it; a pasted object copies its source's network.

An empty scene or object network has no display node (`null` in presets).
Deleting every SOP clears that object's preview, including a late cook from
before deletion. Disconnected nonempty SOPs stay editable; a compile error
retains the last successful preview with an error. Editor3 preserves an empty
scene without adding a camera. Editor2 requires a geometry object and rejects
a scene without one before installation; that object's SOPs may be empty.

Preset load validates unique IDs and owners, owner kinds, input arity and
references, display and camera references, and finite parameters/coordinates.
Rejected loads leave the installed document, history, camera and preview
unchanged. The same serializer writes crash-report presets. Document owns no
PXUI state; `Network_view` converts saved networks to and from graph presentation.

The sketch's code graph becomes the geometry object `geo1`; camera SOPs in it
move to the scene as camera objects. `?lights` become light objects and
`?world` the World. Presets are workspace documents (s-expressions, see `api.md`).

## Levels and keys

The scene and the World open as lists, a SOP network as a graph; `Space l`
cycles graph → list → text → graph (switching to the graph frames it), and each
level remembers its projection. The text projection prints SOP networks and
compound definitions read-only; scene and World levels show a reserved-context
message until their Flow syntax is specified. Inside the World the view pane
opens on the lat-long map and `Space l` flips it back to 3D. `i`, a double-click on a tile or row, or the row
menu's Enter open a geometry object or the World; `u` goes back up (both
from any pane). `Space e` opens the World, creating it on first use as a
daylight sky with a sun. `Space a` opens the add menu of the open level
(objects, SOPs, or World layers) in list and graph alike: hovering a
category opens its submenu to the right, typing searches everything, a lone
top-level category opens by itself. Leader sequences are
`Editor_core.Keymap.Leader` strings; which-key shows one page per typed
prefix. In the view, `w`/`e`/`r` show translate, rotate, or scale handles on
the selected node's xyz triples and Escape hides them so drags only orbit; a
selected camera also gets a handle sliding its target along the view
direction (its focus distance). Camera guides (frustum, aim line, eye marker)
are drawn over the sketch overlay for every camera the view is not looking
through; clicking the eye marker selects that camera. `Editor3.view_camera`
is what the pane shows, for sketch renderers: the render camera through
look-through, else the free viewport carrying the ACTIVE camera's lens. The
Viewport section pairs the look-through toggle with "Camera follows
viewport" (the ACTIVE camera's parameter, one undo entry) so a fixed camera
is set up by looking through it and orbiting. Looking through, the render
fills `Editor3.film`: the camera's aspect (its render resolution) fitted
into the pane; otherwise the whole pane. The editor paints its 3D view and
the sketch overlay inside that rect. "Render / save PNG" captures the screen
unless the sketch takes the request (`Editor3.take_export`) to render at
`Editor3.render_settings` (resolution, max samples) with progress in the
status bar (`Editor3.set_render_status`).
List rows carry a kind badge (G geometry, L light, C camera, W world, ✦ sun,
· layer, S SOP); the status bar names the open level's keys.

The list (`Pxui_shell.Tree`) follows WAI-ARIA tree keys: arrows move the
focus and select, Shift extends, Left/Right fold or go to parent/child,
Home/End, Tab/Shift-Tab reparent under the row above or up a level (keeping
the world transform), Alt-arrows reorder, F2 renames, `/` filters (keeping
ancestors), `h` hides, `f` reveals. Rows drag with a 4-point dead zone onto
before/inside/after zones; toggle columns (`vis`, `rnd`; `disp` in a SOP
list; `vis` for layers) paint when dragged and apply to the whole selection
when the pressed row is selected. Right-click acts on the row, or the
selection when the row is in it, and never changes the selection. New rows
open in rename mode.

A SOP list follows each node's first input; other inputs nest under their
consumer, and a node used twice repeats as a muted `↳` row
(`Pxui_graph.trunk`). Scene siblings list by their canvas y position.
Reordering swaps the affected siblings' positions and saves both in history.

Inside the World (graph pane focused): `t` flips the selected emitter
between dome and light, `n` reseeds, `[`/`]` step the time of day, `d`
plays the day cycle, and `1`–`4` load the presets. Dragging on the lat-long
map moves the selected layer; with the Sun layer selected it places the sun
(unlinking it from the time of day). Shift-drag in the 3D view turns the
World.

PXUI owns the whole pointer gesture. The World edit latches its operation,
stable node ID, and map bounds at the press; releasing Shift or crossing panes
does not redirect it. Ordered movement and the release position enter the same
undo entry. Map coordinates clamp while captured, and popup, pointer, and
focus cancellation end the edit. World events are consumed before camera
navigation; they do not also orbit or pan the view.

## Cooking and drawing

Every visible geometry object's display node cooks in one bounded job
(`Async_cook.submit_all`); an object whose compiled graph and settings are
physically unchanged keeps its prepared value when the projection of its
declared context dependencies also matches. Time/Frame-dependent outputs
prepare again as the timeline changes. Each piece carries the submission's
settings and context projection; publication does not stamp current settings
onto an older result. Settings changes invalidate every object, including
settings whose schema only declares draw effects. Empty object sets submit
an empty request to supersede previous work. The sketch's `scene3` draws
each object, cached per prepared value, and the editor places the drawings
at their world transforms (`Scene3.nodes` under `Scene3.transform`), so
moving, parenting, hiding, or re-lighting objects never re-cooks SOPs. Light
objects light the scene when it has any; otherwise the first object's own
Scene3 lights do. While inside an object the others draw ghosted
(screen-blended, no depth writes) and are not editable. `Editor3.objects`,
`lights`, and `world` hand the same scene to a sketch's own renderer (the
voxel wall's path tracer).

The World bakes each frame it changes (`World.bake_cached`, capacity 4):
512×256 while a gesture or the day cycle runs, 2048×1024 when idle. The
day cycle advances the time of day by `day cycle` hours per timeline second,
so playback and `Sketch.export` with `Fixed dt` are deterministic. See
`environment.md` for the World itself.

## Deliberate limits

- Two levels only; cameras cannot be parented.
- Ghosting is a blend, not a material override.
- Reparenting drops shear (a non-uniformly scaled parent).
- More than one World object is allowed by the menu; the first one is used.
