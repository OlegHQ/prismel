# Composable workspaces design study

Pending proposal, 28 September 2026. Open **[index.html](index.html)** directly:

```sh
open specification/workspace/prototype/index.html
```

No server, build step, package install or network is needed to use the prototype.
The existing Flow font is loaded locally. This is a standalone research artifact;
it does not change `specification/flow.md`, native editor behavior, or Dune.

Read **[the HTML proposal](proposal.html)** for research, language semantics,
architecture, migration stages, open decisions and usability experiments. The
same report is in [Markdown](../../../reports/Composable%20Lisp%20workspaces.md).
Research notes are in [research_notes](../../../research_notes/Composable%20Lisp%20workspaces).

## Try it

1. In Geometry, select **size**, adjust its slider or apply `0.9`. Switch to
   List and Lisp: selection and the applied value follow you.
2. Select **flower**. Its argument controls belong to this call; typed connection
   menus let you choose an earlier binding without writing Lisp. Enter
   **Edit shared definition**. Select **disc**, apply
   `(sop/disc (* radius 0.5))`, and watch both blooms shrink. The header names
   the caller used for preview. Return to call. **Make unique** copies the body
   and retargets only this call; Undo reverses it.
3. Shift-select **size**, **petals** and **flower**. **Group** (`G`) draws a visual
   frame; repeating removes it. **Make function** (`F`) previews the boundary,
   asks for a name and extracts one reusable call. Its parameters come from
   outside dependencies. Undo restores the original bindings.
4. In Settings, select **exposure** and **Inspect macro expansion**. The authored
   `(twice 0.5)` expands to `(+ 0.5 0.5)`. To reuse a function across contexts,
   apply `(half 3.0)` to exposure; `half` also drives geometry's twist.
5. In Editor, choose **Try workspace layouts**. Three panels, single view and
   floating tools each change real Lisp and graph structure. The dialog previews
   the resulting panel tree. **Restore three panels** remains a host control.
6. In Lisp, replace `size 0.7` (or its current value) with `size "oops"`.
   **Check & apply** reports the type mismatch while the live study remains at
   the last applied version. Fix and apply, or discard the draft. Undo/redo each
   document transaction with the toolbar or Command/Ctrl-Z / Shift-Z.
7. Use **Actions & keys** for searchable commands. Tab follows browser focus;
   arrow keys switch focused projection tabs. `1`, `2`, `3` switch views outside
   text fields; Enter on a function node enters it; Escape returns to its call.
   **Export Lisp** downloads the applied document.

## What is real in this study

- One AST feeds graph, list, text, typed inspector, scene illustration and layout
  preview. Graph references establish dependencies across six named contexts.
- Shared function definitions, per-call arguments, explicit independent copies,
  call-context inspection, graph/list selection and source-name highlighting.
- Typed connection menus for preceding compatible bindings. Expressions and
  connections are also editable in the inspector or text.
- Atomic validation and apply, retained invalid draft, 60-step undo capacity,
  explicit graph-cycle/recursion errors, arity/type/context checks, bounded
  geometry counts and numeric runtime checks.
- Binding-free value template macros with a read-only expansion display.
- Visual grouping, single-output function extraction, source export and a
  schematic layout preview driven by the checked editor graph.

## Deliberate limits

This is an interaction prototype, **not** a production compiler, usability study,
complete replacement editor, or browser rendering backend. Its JavaScript flower
illustration is not Prismel geometry or Metal output.

The language implements the small catalog in `model.js`, positional calls and
one return per function. It does not support all current Flow syntax, named
outputs/defaults, general macros, units/effects, arbitrary editor widgets, native
windows, holes, or lossless source identity. Its value macros cannot introduce
bindings; full hygienic expansion is a proposed native milestone. Source applies
normalize formatting and drop comments. New bindings can be authored in Lisp;
there is no node-creation catalog, wire dragging, graph panning/zooming or node
position editing in this study. Large graphs scroll in the canvas. Extraction
is restricted to a selection with one outward result and representable local
inputs; it rejects unsupported boundaries without changing the document.

Visual frames are session metadata, excluded from Lisp export. Refresh loses
session edits; a browser unload prompt guards changed state, and Export saves
the applied source. Saved-literal restoration for parameter drives is specified
for the native design but is not implemented here: the lab's Apply explicitly
replaces a binding expression. Settings FPS and seed are checked configuration
values; the static illustration does not animate or sample randomness.

The panel preview shows layout structure. Selecting a layout changes the editor
root, but intentionally leaves the lab's inspection shell available; it does not
instantiate a complete alternate application or operating-system windows. Native
layout lifecycle and host recovery still need implementation and native tests.

## Verification

The model check uses only Node's standard library:

```sh
node specification/workspace/prototype/check.cjs
```

Optional browser checks use an externally installed Playwright and Chrome; no
project dependency is added:

```sh
node specification/workspace/prototype/browser-check.cjs \
  /absolute/path/to/playwright \
  '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome'
```

`check.cjs` covers the six roots, semantic print/read round trips, shared and
independent functions, cross-context value reuse, restricted macros, static
rejections, cycles, runtime bounds and malformed source. `browser-check.cjs`
covers actual control interactions, caller preview, source errors preserving
state, history, extraction preserving output, grouping, layouts, recovery,
export, keyboard behavior, responsive widths and local proposal links.

These checks establish prototype behavior only. The proposal has separate gates
for OCaml compilation, lossless projections, multi-output extraction, hygienic
macros, runtime/resource safety, native windows and formative user testing.
