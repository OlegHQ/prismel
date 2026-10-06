---
name: extend-rays-editor
description: Extend Rays Editor or build a sketch/editor from its blocks - add a command, a node, sketch settings, a widget, or a panel/custom shell. Use for any change to lib/rays_editor, lib/pxui_shell, lib/editor_core, or a sketch that wants an inspector, undo, or editor commands.
---

# Extend Rays Editor

Read `lib/rays_editor/AGENTS.md` first. Pick the lowest level that works:

| Level | Blocks | Example |
|---|---|---|
| 0 sketch | `rays` (`Sketch`, `Frame`, `Scene`) | `examples/basic` |
| 1 sketch + panel | `pxui`, `Editor_core.Param/History/Store`, `Pxui_shell.Inspector` | `sketches/pastel_flow` |
| 2 custom shell | `Pxui_shell` (Layout, Chrome, Which_key, Prompt, Timeline_bar, Status_bar, Shell), `Pxui_graph`, `Editor_core.Command/Keymap/Router` | none yet |
| 3 Rays Editor | `Rays_editor.Editor3` with a SOP graph | `sketches/voxel_wall`, `sketches/shattered_cube` |

1. **Command**: one `Editor_core.Command.make ~id ~label ?trigger ?scope
   action` entry, the same type as every built-in. In Rays Editor pass it
   as `?commands` with `action : 'prepared t -> 'prepared t`; its trigger
   joins the keymap and which-key, and it appears in the palette
   (`Space /`). A built-in is a `Leader.keymap` entry with a `Leader.action`
   payload handled in the update pipeline. Change undoable state in the action through
   `set_settings` or document edits, never a ref. Never add a variant or a
   `match` for a sketch command.
2. **Node**: catalog nodes use the `add-sop` skill. A sketch node is a
   `Procedural.Custom` node with a `Param` schema plus an
   `Edit_graph.factory` passed in `~factories` (see voxel_wall's
   `factories`), so the node menu can create it.
3. **Sketch state**: put it in a `Param` schema and pass
   `~settings:(Settings.make schema value)`. It shows in the unselected
   inspector, is undoable, is saved in presets, and reaches
   `prepare settings output`. Read it back with `Settings.get schema`.
   Never keep it in an `Atomic` or global ref.
4. **Widget**: a function over `Ui.box`/`signal`/`draw` in the lowest family
   that fits: `pxui` (primitives), `pxui_shell` (editor widgets),
   `pxui_graph` (graph). Never a second hit-test, capture, or paint path.
   Widgets return values or intents; the host applies them.
5. **Where code goes**: if a second shell would want it, it goes down into
   `pxui_shell` or `editor_core`, not into `rays_editor`.
6. **Undo**: `Editor_core.History` snapshots one immutable value. Give each
   record a `~label`; merge drags with `Gesture`, bursts with `Burst`.
7. **Scene objects and levels**: an object kind is a node of the scene
   network (`Objects`, `Layers`: PPX `sop_params`/`sop_node` records with an
   optional input 0 as the parent, no `[@@sop.register]`), added to the
   scene catalog in `Core.catalog`. A key that only means something on one
   level is a `Leader` chord or sequence filtered in `Core.routed`. Sketches
   pass lights as `?lights` and read `Editor3.objects`/`lights`/`world` for
   their own renderers; see `specification/scene.md`.

8. **Graph pane work** (canvas, graph keys, parameter drives,
   list/text views, guide strip): the graph pane is `Pxui_graph.Scope` over workspace text.
   Follow `specification/flow.md` and the next open milestone in
   `specification/flow-migration.md` (skill `implement-flow-milestone`); new
   graph commands carry their `guide` contexts from M2 on.

Check: `dune build @lib/editor_core/runtest @lib/pxui_shell/runtest`,
`SDL_VIDEODRIVER=dummy dune build @test/test_scene_tree @test/test_rays_editor_logic`, then one
native run of `dune build @test/test_rays_editor` (opens a few windows;
do not loop on it), `dune build @tools/api_manifest/runtest` (promote an
intended `.mli` change), and the dependency gate in `dune runtest`.
