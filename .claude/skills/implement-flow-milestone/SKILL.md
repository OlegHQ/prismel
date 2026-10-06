---
name: implement-flow-milestone
description: Implement the next milestone of the Rays Flow node-editor rework (left-to-right canvas, polyline wires, levels, keys and guide mode, value ports and drives, expressions, compounds, graph/list/text views, [%flow] PPX). Use for any change to the SOP graph pane, pxui_graph, lib/flow or lib/flow_sop, or when asked to continue the Flow plan.
---

# Implement a Rays Flow milestone

1. Read `specification/flow.md` §1 (authority rules), then the milestone's
   section in `specification/flow-migration.md` and every `flow.md` section it
   cites. Open `specification/flow/prototype/index.html` in a browser to see the
   behavior; `specification/flow/prototype/README.md` maps behaviors to
   `engine.js` functions. The spec wins over the prototype.
2. Pick the first milestone in the status table that is not `done`. Check its
   preconditions. Do not implement anything from a later milestone.
3. Read the nested `AGENTS.md` for each directory you touch
   (`lib/pxui_graph`, `lib/rays_editor`, `lib/sop_catalog`, and so on).
4. Work in small commits that each keep `dune build @check` and default
   `dune runtest` green. Iterate with focused tests (`focused-test` skill);
   keep tests window-free and run `@runtest-native` once at the end.
5. Tick the milestone's tasks as they land. When they are all done:
   - write its tests (the milestone lists them) and run the pre-commit loop
     from the root `AGENTS.md`;
   - apply its "Docs when it lands" list: rewrite the target notes in the named
     specs and `AGENTS.md` files into current text;
   - run its "Measure" benchmarks before and after and put the numbers in
     `specification/performance-log.md` and the hand-off;
   - set the status row to `done` with the date and add a log line.
6. If the spec turns out wrong or ambiguous, change `flow.md` first (and the
   prototype if it shows the old behavior), record the decision in `flow.md`
   §18, then continue.

Never: curved graph wires, a second hit-test or text-entry path, model
mutation inside `Ui.frame`, `KeyPressed` matching in panes, drives that
overwrite literals, value kinds in `sop_catalog`, or JavaScript/Python in the
build.
