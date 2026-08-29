# PXUI interaction and visual contract

PXUI is a wrapped sibling library. It depends on `prismel`; the core library
does not depend on PXUI. New sketches keep a `Pxui.t` in their immutable model,
feed the current frame through `Pxui.update_frame`, and compose `Pxui.scene`
into their picture. Its compact creative-tool character is inspired by
[ofxUI](https://github.com/liquidzym/ofxUI), adapted to Prismel's functional
scene and event model.

## Visual language

The default theme is deliberately closer to a creative-tool control deck than
a native form:

- a near-black, slightly translucent panel with rounded corners and shadow;
- a bright cyan-green accent and restrained glow line;
- compact system UI typography;
- inset tracks and fields with quiet borders;
- distinct row hover, pressed, selected, focus, and active-drag feedback;
- accented handles and value fills that make control state readable at a
  glance.

The `theme` record keeps the palette small: `panel`, `foreground`, `control`,
`input`, `track`, and `accent`. Geometry derives secondary hover, border, and
pressed colors from those values so a custom palette retains the interaction
language.

`Pxui.create ?font ?font_size ?max_height` borrows an explicitly supplied `Font.t`, or uses
`Scene.text` and the installed system UI font by default. `font_size` is in
logical points. The default font is density-aware, so text retains its layout
and sharpness on Retina output. Empty labels and field values are valid, and
changing values share Prismel's bounded renderer-local text cache.

## Coordinate model

Panel position, width, padding, row height, rendering, and hit testing all use
Prismel logical points. Runtime translates SDL3 logical event coordinates into
that same space.
PXUI must never multiply event positions by `Frame.pixel_scale`.

A bounded panel reports the smaller visible height from `Pxui.bounds`. Rows,
text, and native text-input metadata are clipped to its content viewport.
Vertical wheel/trackpad motion over that viewport adjusts a clamped logical
scroll offset; horizontal motion does nothing. The optional scrollbar is a
view of the same offset, not a second source of state. Camera controls derive
a separate frame-fitting bound from the current `Frame.height`; the effective
height is the minimum of that bound and the host's authoritative `max_height`.
Frame fitting never overwrites the host cap, so a stable inspector layout does
not cancel pointer capture between press and release.

## Pointer state machine

PXUI tracks hover and one active left-pointer interaction:

- A button, toggle, or choice becomes armed when pressed inside its control.
  It commits only if the matching release is also inside. A release outside
  cancels the action; moving out and back in preserves the arm until release.
- A slider captures on press and emits `Slid (name, value)` whenever its
  clamped value changes during motion. Motion continues to update it outside
  the original bounds until release.
- An integer slider performs the same capture with integer min/max/value,
  snaps before comparison, emits `Int_slid`, displays an integer, and persists
  it as an integer. Sketches must not emulate it by rounding float sliders.
- A range chooses the nearest handle on press, captures that handle through
  release, preserves `low <= high`, and emits `Ranged`.
- An XY pad captures both axes, clamps them independently to their declared
  ranges, and emits `Moved2`.
- The final release position is applied to a captured continuous control before
  capture ends.

This state lives in the returned `Pxui.t`; `Pxui.update_frame` never mutates its
input value and returns changes in event order. It supplies `Frame.time` for
deterministic double-click recognition. `Pxui.update ?time` remains available
for direct event processing and tests. Compatibility functions (`add_*`,
`handle_event`, and `draw`) use the same single-click semantics.

## Focus and text

Pressing a text field gives it focus. `TextInput` appends committed UTF-8,
`TextEditing` records in-progress IME composition, and Backspace removes one
complete UTF-8 scalar sequence. A press elsewhere moves or clears focus.

Double-clicking a float- or integer-slider label within 0.35 logical seconds
opens an inline numeric editor and selects the current value. The first typed
numeric character replaces that value. Enter commits a finite value as written
and emits the slider's ordinary named change; Escape cancels.
Pressing elsewhere commits valid text and cancels invalid text. Slider min/max
are a soft drag range: dragging remains clamped, while typed, initial,
programmatic, and persisted values may extend beyond it. Integer sliders parse
strict integers, so fractional input remains visibly invalid and cannot change
the stored integer.

`Pxui.scene` includes a pure `Scene.text_input_region` for every text field and
the active inline numeric editor. Runtime uses those logical bounds to start or
stop SDL3 text input. Committed UTF-8 and IME composition then enter the same
ordered Prismel event stream as keyboard and pointer events.

`PointerCancelled` releases only the cancelled pointer and active drag. It does
not clear text focus. This avoids treating a cancelled pointer gesture as if
the entire window lost focus.

`WindowFocusLost` is a hard cancellation boundary: it clears pointer capture,
hover, text focus, and composition without emitting a value change. The core
Input module simultaneously clears held keys and mouse buttons, preventing a
lost release from leaving either layer active.

## SOP inspector adapter

PXUI itself remains independent of procedural geometry. The leaf
`prismel.sop_ui` library adapts the selected node's concrete
`Procedural.Parameter.field_view` values into ordinary PXUI widgets. Parameter
folder paths become nested accordions; bool/int/float/string/choice templates
become the corresponding native controls. Names are prefixed by stable node
identity so different operators can share the environment safely.

`Sop_ui.Node_inspector` takes the selected
node's type-erased `Parameter.field_view` list, generates the same native PXUI
widgets, and routes edits through `Procedural.Graph.apply_parameters`. Selection
changes rebuild only the inspector canvas; stable node IDs keep selection and
the Procedural session cache intact. It ignores camera and unrelated changes,
batches relevant writes, preserves view/export-only geometry cache identity,
and synchronizes strict-bound normalization back into the panel. There is no
second sketch-wide promoted parameter authority.

The separate `prismel.pxui_graph` canvas uses the PXUI theme but owns persistent
graph-space tile positions, ordered input ports, curved wires, navigation, and
hit testing. Left-drag moves the selected tile set, Shift-click and blank-area
marquee form multi-selection, middle/right drag pans, vertical wheel/trackpad
motion zooms around the logical pointer, [Home] frames all, [F] frames the
selection, and [O] restores a deterministic optimized layout. Wires are
selectable and output ports can be dragged to ordered input ports. Delete or
Backspace emits a typed node-removal or wire-disconnect request. Space opens a
searchable SOP catalog: every node type remains creatable, with unsupplied
inputs represented as disconnected slots; on a selected wire it emits an
atomic unary insertion request. Command/Ctrl-C, -V, and -X operate on an
internal subgraph clipboard, while Command/Ctrl-D duplicates the selection.
Pasted nodes receive fresh logical IDs, retain internal wiring and relative
positions, and drop connections to nodes outside the copied selection. Stable
nodes retain manual positions when the immutable document changes. The canvas
never applies topology or cooks: `Sketch_ui` validates its requests through
`Procedural.Edit_graph`, compiles the chosen display DAG, and schedules the
bounded worker while retaining the last successful preview. Scene
construction rejects off-screen node tiles before allocating their primitives.
Node titles, operation/dependency text, ordered connectors, and a separate VIEW
button use zoom-aware levels of detail. The VIEW flag is independent from
inspector selection and requests a bounded asynchronous cook of that node.
Unchanged visibility must preserve graph pointer capture across frames.

`Sketch_ui.Environment3` and `Environment2` place the view, graph, and inspector
in one responsive three-column workspace. Its default flexible widths are
45/35/20, splitters retain ratios across window resize, and each column is
collapsible. Camera gestures are restricted to the view. With no graph
selection the inspector hosts reusable camera/render controls; a node selection
replaces them with its generated SOP inspector. Both dimensions share the same
workspace, selection, display-node cooking, timeline, cook scheduling, and
status behavior. Sketch overlays receive view-local coordinates and a frame
whose logical dimensions match the current view pane.

## Regression requirements

Tests for PXUI changes must cover:

1. press/release-inside commit and release-outside cancellation;
2. multiple captured drag movements, including positions outside the control;
3. final release position for slider, range, and XY controls;
4. nearest-handle range selection and clamping;
5. high-DPI-neutral logical hit testing;
6. focus loss during an armed or dragged interaction;
7. ordered changes from a multi-event update;
8. hover/pressed/drag scene differences and system-font rendering in a
   native framebuffer;
9. pointer cancellation without a false text-focus loss;
10. SDL3 text-input activation only for text-field regions, including IME
    composition and focus transitions;
11. integer-slider snapping, integer persistence, and exact change payloads;
12. bounded panel clipping, scroll clamping, scrolled hit testing, accordion
    height changes, and resized camera-panel bounds.
13. deterministic numeric-label double-click entry, float/integer parsing,
    soft-range overflow, invalid input, outside-click commit, and Escape
    cancellation.
14. promoted-schema widget mapping, batched graph rebuilding, soft versus hard
    numeric bounds, unrelated-change filtering, and persisted-value import.
15. selected-node inspector edits with stable IDs and shared subgraphs;
16. deterministic top-down graph layout, selection, pan, zoom, visibility, and
    selection retention across immutable graph replacement.
