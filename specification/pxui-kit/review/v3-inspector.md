# Inspector, round 2: what still looks different from the sheets

The docked inspector with a SOP node selected now reads as the sheet; most of what a person still sees as wrong is in the floating window, material and bypassed nodes, and the head's missing pieces. Nothing in the repository was edited and `dune` was not run. I could not check the scrolled body: `ui_shot` has no wheel step and a `hold` on the thumb does not drag it.

Side-by-side pictures (sheet left, application right) are in `/private/tmp/claude-501/-Users-snowbear-WORK-GIT-prismel/3f162fa8-7a40-429c-8606-d41c30b5f285/scratchpad/kit/v2-inspector/`: `sbs_docked.png`, `sbs_ws.png`, `sbs_win.png`. State renders are named below.

The fixture's graph layout changed: `click:490,99` no longer selects a card. Use `click:420,262` for `scatter1` in layout 1 of `kit.rays`.

## Differences, worst first

### 1. Bypassed node shows another node's parameters
- **Seen:** select `soft` (`sop/smooth`) and press `b`. The head still says `SOP/SMOOTH` / `soft`, but the rows become those of the upstream `sop/grid` (counts, connectivity, orientation, Resolution, columns, rows) and the number changes from `NO. 0004` to `NO. 0003`. Renders `x2c_soft_i.png` and `x2c_byp_i.png`, fixture `fx2.rays` layout 2.
- **Change:** in `lib/rays_editor/core.ml` `workspace_inspector` (lines 666–681), `Probe.plan_node` resolves a bypassed node to the node it passes through, and `compiled_node` then supplies that node's fields. When `n.bypass` is set, or the compiled node's kind is not `n.head`, take the fields from `kind_fields value graph n.head authored_row` and keep the node's own index.

### 2. Material node has an empty body
- **Seen:** selecting `material/standard` gives the head, `Reset all`, a blank body and `0 ON CARD`, docked (`x2b_mat_i.png`) and floating (`wsl_mat_win.png`). The graph card shows name, color and roughness.
- **Change:** `kind_fields` (same place, line 681) yields nothing for `material/*`. It must return rows as it now does for `scene/*`.

### 3. Floating inspector has a bottom bar the sheet does not
- **Seen:** `windows.html` ends the window with rows and the resize corner. The application draws the hairline, `⌥ click type a value` and `N ON CARD`; the bar covers the last row and runs into the resize corner (`x2a_camf_win.png`).
- **Change:** do not call `Pxui.Ui.inspector_bar` (`core.ml` line 982) when the panel is a window.

### 4. Floating inspector content is narrower and its title sits low
- **Seen:** labels, title and detail start 1 point right of the sheet, fields end 1 point early, and the section chevron is 1 point left. The 20-point title is about 1 point low.
- **Change:** the window is inset twice. `core.ml` line 3569 already shrinks the bounds by the border, and the row rule in `lib/pxui/ui.ml` (`inspector_row`, `inspector_control_x`, `paint_section`, window branch of `inspector_header`) insets again. Targets from the window's outer left: label 13, field 109 to 307, chevron right edge 308.5, title text top 158 below a window top of 120.

### 5. Window title strip text is shifted left
- **Seen:** `INSPECTOR` starts 2 points left of the sheet and the name after it 3 points left. The sheet has 8 between the accent square and the word, and 8 before the name.
- **Change:** this is the window title strip in `pxui_shell` `Chrome`, not inspector code. Targets: word at 27 from the window's left, name 8 after it.

### 6. Breadcrumb shows `@result` where the title says `result`
- **Seen:** for a graph's result node (scene root, material) the panel header and window strip read `scene / @result` and `clay / @result`; the title below reads `result`.
- **Change:** the header route (`panel_title` in `pxui_shell`, fed by `Core.route`) should use the title `Projection.title n` gives.

### 7. Scene nodes repeat the kind and have one flat section
- **Seen:** the chip says `SCENE/CAMERA` and the detail line says `scene/camera · cached`. The sheet's detail is a state (`scene/camera · active`).
- **Seen:** all 15 camera rows sit in one `CAMERA` section; the sheet groups them as `Lens` and `Transform`.
- **Seen:** scene nodes get no button row, so `Reset all` sits alone under an empty line.
- **Change:** the detail fallback is `core.ml` 719–721. The grouping needs folders on the scene kinds' parameters (schema). The section named by the kind is `flow_fields` in `lib/pxui_shell/pxui_shell.ml`.

### 8. Head is missing `Enter`, the cook time and kerning
- **`Enter I`:** never appears for `sop/scatter`; it is drawn only when `follow_target` finds a reference (`core.ml` 702).
- **Detail line:** `120 points · 0 prims`, with no `· cooked 0.003 s`.
- **`NO. 0005`:** starts about 3 points right of the sheet's number because the 0.04em tracking is missing.
- **Title:** the 40-point title runs about 2.5 points wider because the −0.01em tracking is missing.
- **Change:** both tracking fixes are in `ui.ml` `inspector_header`.

### 9. Bottom bar lacks the first hint and its right group is off
- **Seen:** `s  pin row to card` is absent, so `⌥ click  type a value` starts at the left edge instead of second.
- **Seen:** the dot and `N ON CARD` sit 1 point right of the sheet.
- **Change:** in `ui.ml` `inspector_bar`, right-align the cap including its trailing letter-spacing so its ink ends at 366.5.

### 10. Clicking the pin dot does nothing
- **Seen:** the ring and dot are drawn as the sheet draws them, but a click only hovers the row (`s_pin_i.png`).
- **Seen:** the dot means "argument is written", not "on card", so `N ON CARD` counts written arguments.

### 11. Empty selection starts with a bare row
- **Seen:** `Live update` sits directly under the head with no section header. It has no pin slot, so its label lines up with the other labels only by accident.
- **Seen:** in a window the same pane is clipped at the bottom, with a half-drawn `RENDER` header over the resize corner (`x2a.png`).
- **Change:** `core.ml` 3608–3611; put the row under a section (for example the graph's name).

### 12. Text placeholder wording
- **Seen:** an empty `group` field shows `all`; the sheet shows `all points`.
- **Seen:** other empty text fields (`point_pattern`, `name`, `parent`) show only the hairline.
- **Change:** the placeholder passed to `value_field ?placeholder` from `pxui_shell.ml` `row_widget`.

### 13. Renaming the title uses a small caret
- **Seen:** a click on the 40-point title opens the rename with a caret sized for 13-point text, in the top third of the wash (`view_i.png` from my first attempt, `click:1300,90`).
- **Change:** size the caret to the title's line in `ui.ml` `inspector_header` (`?rename`).

### 14. `Reset all` is offered when there is nothing to reset
- **Seen:** it is drawn at full ink-2 on nodes with `0 ON CARD` (`x2b_mat_i.png`, `f_root_i.png`).
- **Seen:** on `scatter1` it also removed the `count ← count` drive (count became 100).
- **Change:** if removing drives is intended, keep it. The idle state should be the disabled ink or hidden.

### 15. Vector fields are a hair uneven
- **Seen:** the three fields are 73 / 74 / 73 wide where the sheet has equal thirds. Visible only when zoomed.
- **Change:** `Ui.ints` rounding inside `value_field`.

## Round 1 findings

| Status | Findings |
|---|---|
| Closed | 2 (bar), 3, 4, 5, 7, 8, 9, 10 (points and bounds), 11, 12, 13, 14, 15, 16, 17, 18, 20, 22, 25, 26, 28, 30 |
| Closed for scene nodes, open for material | 1 (see item 2) |
| Partly open | 6 and 19 (window head is right; inset and bar remain, items 3–4) |
| Open | 23 (item 15), 24 (item 8; cap tracking is fixed, index and title are not), 31 (`Enter`) |
| Open, no longer visible to the eye | 27 (collapse chevron now draws in foreground), 29 (line colours one level off) |

Finding 21 stays as the owner decided (12-point top padding).

## Drawn on the sheet with no feature behind it

- **Row pin to card:** the `s` key, the hint, a click on the dot, and a true "on card" count. This needs a `Flow_edit` op and a per-node card list.
- **Per-node cook time:** `cooked 0.003 s` in the detail line; `Cook` only knows the whole network's seconds.
- **`Enter I`:** for nodes that are not references.
- **Bypassed node rows:** wrong, not just missing (item 1).
- **`Lens` / `Transform` grouping and `35 mm` unit suffixes:** on the camera.
- **`active` state in the camera's detail line.**

## Decisions for the owner

- **The sheets disagree on the docked head and bar.** `workspace.html` has no `NO.` index, no bottom bar, and a breadcrumb of just `scatter1`; `inspector.html` has all three. The application follows `inspector.html` everywhere, including the 320-wide column (`sbs_ws.png`).
- **The fixture is 1 point short.** `kit.rays` layout 1 rendered at 784 high gives a 759-point panel, because the status strip is 1 + 24. Compare at 785 high or the bar reads 1 point high against the sheet.