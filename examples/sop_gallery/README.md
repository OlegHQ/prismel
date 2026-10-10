# SOP gallery and editable presets

Run `dune exec examples/sop_gallery/lisp.exe`. `dune runtest` cooks every graph of
`gallery.rays` without a window (`test/test_workspace_ir`).

The gallery is one workspace, `gallery.rays`: a `sop` graph per entry, and a scene
showing `(ref boolean)`; select another graph in the outline to see it. Curves, point clouds,
the Voronoi cells and the gyroid are written in `gallery.rays` itself, and so is the star prism
(a closed `sop/curve` swept by `sop/sweep :caps true`).
Save writes a preset (the workspace text).

Select a `sop` graph in the list and press `i` to edit it in the graph pane; edits rewrite
`gallery.rays`'s text in memory. `Space s` then Enter saves a preset and `Space b` loads one;
Command/Ctrl-Z undoes the load. A malformed preset is rejected before it replaces the current state.

The key light uses `:intensity (+ 1 (* 0.15 (sin t)))`: timeline playback
pulses its lighting while the prepared meshes stay cached. Light `:color`
also accepts time expressions. Other scene/World/panel fields remain static;
window title/size/fps and cook seed apply on restart.
