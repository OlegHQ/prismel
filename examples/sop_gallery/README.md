# SOP gallery and editable presets

Run `dune exec examples/sop_gallery/main.exe -- --entry boolean`; `--list` names the
entries and `--check-all` cooks each without a window (part of `dune runtest`).

The gallery is one workspace, `gallery.rays`: a `sop` graph per entry, and a scene
showing the one `--entry` names. The `gallery_*` nodes (point clouds, curves and meshes the
catalog has no node for) are OCaml source SOPs registered beside the catalog in `main.ml`.
Save writes a preset (the workspace text); the entry is a rewritten scene ref, not a file.

Select a `sop` graph in the list and press `i` to edit it in the graph pane; edits rewrite
`gallery.rays`'s text in memory. `Space s` then Enter saves a preset and `Space b` loads one;
Command/Ctrl-Z undoes the load. A malformed preset is rejected before it replaces the current state.

The gallery's `prepare` callback only converts CPU geometry to mesh data on
the cook worker. `scene3` builds the scene on the initial domain.

The key light uses `:intensity (+ 1 (* 0.15 (sin t)))`: timeline playback
pulses its lighting while the prepared meshes stay cached. Light `:color`
also accepts time expressions. Other scene/World/panel fields remain static;
window title/size/fps and cook seed apply on restart.
