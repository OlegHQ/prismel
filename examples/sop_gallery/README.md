# SOP gallery and editable presets

Run `dune exec examples/sop_gallery/main.exe -- --entry boolean`; `--list` names the
entries and `--check-all` cooks each without a window (part of `dune runtest`).

The gallery is one workspace, `gallery.plisp`: a `sop` graph per entry, and a scene
showing the one `--entry` names. The `gallery_*` nodes (point clouds, curves and meshes the
catalog has no node for) are OCaml source SOPs registered beside the catalog in `main.ml`.
Save writes a preset (the workspace text); the entry is a rewritten scene ref, not a file.

Select `gallery` in the scene list and press `i` to edit its SOP network.
Deleting every SOP clears the preview. `Space s` then Enter saves that empty
network; `Space b`, the saved name, then Enter restores it. Command/Ctrl-Z
undoes the load and Shift-Command/Ctrl-Z redoes it.

Press `u` to return to the scene. Delete the geometry and light objects,
then the camera, to leave an intentionally empty scene. Save and reload with
the same keys: Editor3 preserves the empty scene. Editor2 preserves empty SOP
networks too, but rejects a scene preset without a geometry object safely.
Malformed presets are rejected before replacing the current state.

The gallery's `prepare` callback only converts CPU geometry to mesh data on
the cook worker. `scene3` builds the scene on the initial domain.
