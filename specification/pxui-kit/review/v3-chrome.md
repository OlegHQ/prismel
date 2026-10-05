Round 2 chrome review: the 13-point baseline complaint is fixed, but the viewport render frame is visibly broken and the status strip names the wrong panel in several states. Per the owner's change of bar, this is only what a person sees in side-by-side pictures. Nothing in the repository was touched and `dune` was not run. Pictures are in `/private/tmp/claude-501/-Users-snowbear-WORK-GIT-prismel/3f162fa8-7a40-429c-8606-d41c30b5f285/scratchpad/kit/v2-chrome/` (the `p_*.png`, `fr_*.png`, `sb_*.png`, `strips_*.png` files).

Code locations marked "round 1" are carried from the previous findings and were not re-opened.

## What still hurts the eye, worst first

### 1. Viewport render frame is cut up by its own label and readouts (`fr_tl.png`, `fr_tr.png`, `fr_bl.png`)
- **Sheet (`workspace.html`):** a complete rectangle with four L-shaped ink corner marks. The label `RENDER FRAME · 1920 × 1080` sits above the top-left corner with no background.
- **Application, layout 0:**
  - The label has a ground patch that erases the top edge from the left corner to the end of the text, plus the horizontal arm and top 4 points of the top-left mark. Only a short vertical tick is left.
  - The `CAMERA / LENS` readout patch erases the whole top-right mark and the first 24 points of the right edge.
  - The bottom-left mark lands on the axis gizmo: the X axis runs into it and the `X` letter sits inside the mark.
- **Change:** `lib/rays_editor/core.ml` near line 3327 (frame label) and 3377 (camera rows); frame rectangle in `Viewport3.film` (round 1).
  - Draw the label without a ground.
  - Keep the frame clear of the gizmo and the camera readout, or drop the camera readout at this width as the workspace sheet does.
- **Frame size, for the owner to decide:** the two sheets disagree and the application follows `viewport.html`.
  - `workspace.html`: frame 640 × 360 in a 902 × 485 body, 132 from the left, 32 from the top, 93 free below. It clears the gizmo and the stats line.
  - `viewport.html`: 896 × 472 in 1200 × 547, 152 at the sides, 40 above, 35 below. There the readouts do cover the two top corners, and only the tail `1920 × 1012` of the label shows.
  - Application in layout 0: 727 × 409, 87 from the left, 40 from the top, 36 below.
- **Edge colour and mark length** are right where they show.

### 2. Status strip names the wrong panel and shows the wrong keys (`strips_l.png`, `strips_r.png`)
- **Outline-only and Timeline-only fixtures** start with `VIEWPORT` in the strip. The Timeline one even lists the viewport keys, though no viewport exists. No header shows a focus square in that state.
- **Viewport focused by a click:** the keys vanish (`VIEWPORT GARDEN` only). They show only before the click.
- **Lisp focused:** shows the graph's `? toggle guide  Space k all Flow keys`.
- **Timeline and Inspector:** nothing beyond the kind.
- **Change:** the status code in `Core` (`Core.status_box` and the guide, round 1): take the strip's kind from the pane that is actually focused, and give each panel its own keys.

  | Sheet | Bottom bar |
  |---|---|
  | `outline.html` | `/ filter  i enter  Space j jump` … `3 GRAPHS` (application matches when clicked) |
  | `viewport.html` | `GARDEN  g move  r rotate  s scale  i enter object  ⌥ drag orbit` … `● Cook complete · 0.003 s` |
  | `graph.html` | `SCATTER1  Tab add after  o open  v view  b bypass  i enter  f hints  Space leader` … `6 nodes · 1 selected  ZOOM 100%` |
  | `inspector.html` | `s pin row to card  ⌥ click type a value` … `● 3 ON CARD` |
  | `text.html` | no keys; its own row `● 1 error  line 8 · …` … `7:58 · MODIFIED` |

- **Viewport wording:** the application says `f frame the displayed node  w move handles  e rotate handles  r scale handles  esc orbit only (hide handles)`. The sheet's are one word each, on other keys.
- **Graph, nothing selected:** the application reads `? toggle guide  Space k all Flow keys  y pick up (carry it onto a place)  u back (up a level)`. Long parenthesised phrases; the sheet's style is one or two words.

### 3. Status strip right side lists every pane
- **Sheet:** `LAYOUT 0 · VIEW | GRAPH / LISP` (one name per column group); with windows just `3 FLOATING`.
- **Application:** `LAYOUT 0 · OUTLINE | VIEW / TIMELINE / GRAPH | INSPECTOR / LISP`.
- **With windows:** `4 FLOATING LAYOUT 1 · OUTLINE | VIEW / … + GRAPH + VIEW + INSPECTOR + LISP`, which pushes `Space n new window` off the strip while a window is moved (`p_win.png`).
- **Same string in the Outline's Layout rows:** `Outline | View / Timel…` is cut with an ellipsis at 216, where the sheet shows `View | Graph / Lisp`.
- **Change:** shorten the layout summary, and show only `N FLOATING` when there are windows.

### 4. An accent line escapes a floating graph window (`w1_s.png`)
- In `sketches/ws_layout` layout 1 a red diagonal line runs from the top of the floating `GRAPH clay / material` window up across the docked viewport to its header. It is there with and without a drag.
- It looks like a wire that is not clipped to the window, but I did not trace it. Check the graph pane's clip when hosted in a window.

### 5. Floating viewport window
- **Sheet:** white body with an inset frame and a `WIRE · TOP` label.
- **Application:** panel-grey body, no frame, no label, so it reads as a hole rather than a window. The implementer already lists the grey body as open.
- **Change:** `Chrome.update` and the viewport body fill.

### 6. Outline at 216 (`p_out216.png`)
- **Extra node rows:** the open graph lists its nodes (`grid1 200 prims` …) under `garden`. Neither sheet has node rows.
- **Extra sections and row:** `LAYOUT` with an `editor` graph row, and `DATA FLOW`. `workspace.html` ends at `INPUTS`. The implementer kept these on purpose; the owner should say whether the narrow sheet is literal.
- **Header:** reads `OUTLINE kit`. The narrow sheet has `OUTLINE` alone; the wide sheet has `OUTLINE kit.rays` (file name, not workspace name).
- **Camera row:** has no visibility box, only the render dot. The sheet's camera has both.

### 7. Outline at 380 (`p_out380.png`)
- **Selected row, literal sheet numbers:** `outline.html` draws the selected `G garden` row with its own chevron (ink 10.5–19.5), letter at 26.5, name at 41 (the root's indent, not a child's 38 / 52). Fill inset 4 each side with accent brackets, flags at 341 and 361. I could not get a bracketed object row in my render (the click filled the root row full width, no brackets), so this state is unverified in the application.
- **`window` function mark:** a small four-point star, visibly smaller than the sheet's 7 × 7 filled diamond. Change in `Navigator` row drawing.
- **`sky` count:** shows `world … 0` under WORLD while the Scene's world row says `ref sky`. The use count ignores the scene's reference. The sheet shows `panel dome … 1`.
- **Row order:** the application is in document order (garden, hedge, camera, light). The sheet lists camera, light, geometry, world.
- **Extra row:** `editor` under LAYOUT.
- **Root chevron:** present at 380, absent at 216, as in the sheets.

### 8. Text after every upper-case label starts 1 point early; right-aligned labels end 1 point late
- Since tracking became 0.88, the label's width leaves out the spacing after its last letter.
- Breadcrumbs after `VIEWPORT` / `GRAPH` / `INSPECTOR` and the header rule sit 1 left of the sheet.
- `60 FPS` in the strip and in the viewport stats sits 1 right.
- It is small, but it is one cause everywhere.
- **Change:** `Ui.Paint.cap_width` (`lib/pxui/ui.ml:1556`) and `Kit.cap_width` (`pxui_shell.ml:296`): add one tracking step per character, including the last.

### 9. 13-point lower-case text is slightly taller and heavier than the sheet
- The baseline now matches at both 1x and 2x, in the strip, headers, rows and code. The round-1 one-pixel drop is gone and 11-point labels match exactly.
- What remains: the x-height is one device pixel taller at 1x and about half a pixel at 2x, so text reads a little bolder.
- **Likely cause:** `lib/rays/font.ml:17` loads fonts with `Normal_hinting`; Chrome does not hint. Trying `Light_hinting` or `None_hinting` for the UI font is my guess at the fix, not tested.
- I see no remaining vertical misalignment in the strip at 2x (`sb_a.png`, `sb_b.png`).

### 10. Axis gizmo
- Lines are still 2 points wide (4 device columns); the sheet's are 1.5 (3 columns). Round-1 finding 23 is not fixed on pixels.
- `Viewport3.gizmo` calls `thick_line 1.5`; the result is snapped wide.
- The workspace sheet's gizmo has no letters; the viewport sheet's has them. The application always draws them.

### 11. Viewport readouts: wording and missing parts
- **Stats:** `720 PRIMS  1 OBJECT`; the sheets say `2 408 TRIS` (workspace: no object count).
- **Camera block:** lacks `· f 2.8` and the `FOCUS 4.20` row.
- **Traced block, third row:** `1920 × 1080 · ½`; the sheet has `0.8 S · 4 BOUNCES · 960 × 506`.
- **Traced block, workspace sheet:** it is a narrower block (112 wide: `128 / 512` with a small total, `SPP · 0.8 S`, no `METAL RT`). The application uses the wide viewport-sheet form at every width.
- **Traced label:** the application moves the whole frame label to the right of the readout. The sheet leaves it at the frame's left, with the readout covering its head.

### 12. Collapsed pane header
- Reads `GRAPH garden / sop collapsed`. `docking.html` has `LISP collapsed`, kind plus the word and no breadcrumb.

### 13. Graph header tools: the two sheets disagree
- `graph.html` (1200 wide): Add, Repeat, Iterate, fn, **macro M**, defn.
- `workspace.html` (902 wide): Add, Repeat, Iterate, fn, defn.
- The application shows the five at every width. To be literal, show `macro M` when the pane is wide enough (layout 1) and drop it when narrow.

## Fixed since round 1 (seen in pictures)
- Window edges on all four sides.
- Viewport frame margins, `Frame F`, selection count label.
- Root row and flags in the Outline; `defn` listed under Geometry.
- Lisp top padding and gutter; narrow Lisp bar (`Doc`, no `esc`, no parinfer, no status row); `kit.rays / graph` header.
- `fixed dt 1/60` in the timeline header; smooth Play triangle.
- Dock bars only on the hovered pane; accent frame and tip on a moving window.
- Timeline strip and tall timeline match their sheets apart from mock numbers.

## Not reachable from a script
- Lisp error row, underline, selection tint and draft state: typing cannot be scripted.
- A bracketed selected object row in the Outline, at either width.
- The tile layout in `docking.html`.

## Drawn by the sheets with no real feature behind it
- Diagonal cross and `SCENE RENDER` placeholder inside the render frame.
- `f 2.8` and `FOCUS 4.20` (camera aperture and focus distance); the same `aperture` / `focus` rows in the windows sheet's inspector.
- `4 BOUNCES` and render seconds in the traced readout.
- Transform handle with its `translate x 0.42` tip.
- `i enter object` and `⌥ drag orbit` as strip keys.
- `ZOOM 100%` and `6 nodes · 1 selected` in the graph bar.
- `3 ON CARD` and `s pin row to card` in the inspector bar.
- `panel dome` as a world detail; `rough 0.3` as a material detail.
- `512 spp` on the root row (the application shows the real `256 spp`).
- `View ×4` tile layout row.
- `WIRE · TOP` orthographic view label.