Round 2 review of the kit widgets and overlays, by side-by-side pictures against `widgets@2x.png` and `overlays@2x.png`. The harness refused the findings file, so the full list is below; nothing in the repository was edited and `dune` was not run.

What I could not open: the panel header menu and every right-click menu (`tools/ui_shot.ml` scripts only the left button and has no text input), so typed search in the editor, a carry in flight and a refused echo were also not rendered. Those are judged from the widgets harness and the code, and marked so.

Pictures are in `/private/tmp/claude-501/-Users-snowbear-WORK-GIT-prismel/3f162fa8-7a40-429c-8606-d41c30b5f285/scratchpad/kit/v2-widgets/` (`p_*.png` are sheet on top, application below).

## What still reads as different, worst first

### 1. Floating window title row is not the sheet's [02]
- **Sheet:** `INSPECTOR` at the left; the subject (`camera`) dim and right-aligned just before the buttons; dock is a small hollow square; then `×`.
- **Application (`p_win.png`):** the subject (`clay`) sits right after the title, and the dock mark is a down chevron.
- **Change:** `lib/pxui_shell/pxui_shell.ml`, `Chrome.update`, the windowed header (around the `dock` box near line 487). Right-align the subject, ending 8 before the dock mark, in ink-2 at 70 %. Draw the dock mark as a 10 x 10 hollow square with a 1-point ink-3 edge (`Paint.frame`).
- Previous finding 9 is open; the implementer says nothing in `Chrome` except the panel menu changed. Previous finding 8 (window edge only at the top) is closed: all four edges are drawn now.

### 2. Status strip under the leader has no `SPACE` chip
- **Sheet:** dot, `Cook complete`, a rule, `SPACE` in accent, `waiting for a key` in ink-2, `60 FPS` at the end.
- **Application (`p_leader.png`):** `GRAPH LEADER ? toggle guide Space k all Flow keys Space s save preset …`; nothing is accent.
- **Change:** `pxui_shell.ml` `Status_bar.guide` / `focus_labels` and the host in `lib/rays_editor/core.ml`. While the leader is open, replace the focus and hint run with the accent label `SPACE` (the pending prefix) and `waiting for a key`.
- Previous finding 7 is open.

### 3. Caret is drawn through the placeholder in an empty search field
- **Application (`p_add.png`, `s_g_palette.png`):** in the add-node menu and the command palette the accent caret crosses the first letter of `type to search` / `Search commands`.
- **Sheet:** the at-rest field of [05] shows the placeholder with no caret; a caret only appears next to typed text.
- **Change:** `lib/pxui/ui.ml` `picker`. Do not draw the caret while the query is empty, as the `~at_rest` path already does for the key sheet.

### 4. Add-node menu opens as a category browser with no current row
- **Sheet [01]:** every row has a type square, the first row is current (control fill, `↵` at the right), details are right-aligned.
- **Application (`p_add.png`):** with an empty query the rows are `Attribute >`, `Boolean >`, … with no square, no current row and no `↵`. The footer still says `↵ place`.
- **Change:** `lib/pxui_graph/node_menu.ml` `update` / `picker_rows`. Either list kinds from the start, as the sheet does, or at least make the first category row current.
- The searching state (squares, accent letters, `not in sop` row) matches the sheet in the widgets harness, but I could not type into the editor's menu.
- The menu also runs to the very bottom of the 900-point window and covers the status strip (`s_g_add2.png`); clamp it above the strip.

### 5. Search prompt (palette, jump, browse) follows no sheet
- **Application (`s_g_palette.png`):** 420 wide, a list of rows, then `Cancel esc` / `Pick ↵` buttons.
- **Sheet:** the only window with a list is [01]: 320 wide, with a hairline and a hint bar (`↑↓ move ↵ place … N of M`), no buttons. Buttons belong to the one-field prompt [06].
- **Change:** `pxui_shell.ml` `Prompt.search`. Make it 320 wide, truncate labels with an ellipsis, and replace the buttons with `Ui.footer ~right:"N of M"`.
- The implementer's 420 is a deviation; no sheet shows a 420 window.

### 6. Panel header menu has rows and keys the sheet does not (from the code)
- **Extra rows:** after the seven panel kinds the code appends a separator, a disabled `Size of its split` heading and three sizing rows (`By ratio`, `Fix … side`). Sheet [04] ends at `Viewport`. Move them elsewhere, for example the splitter's own right-click, or drop them. `Chrome.update`, about lines 534–541.
- **Split keys are swapped against the sheet:** the sheet prints `Split right — Space o v` and `Split down — Space o h`; the application prints `h` and `v`, because in the keymap `h` is the side-by-side split. To match the sheet the keymap has to swap (`lib/rays_editor/leader.ml`), not the menu text. This needs the owner's decision.
- **Keys are hard-coded:** `Space o h/v/f/x` and the kind letters are literal strings in `pxui_shell.ml` line 542. Pass them in from the host, as `Which_key.panel` gets its entries, or they will drift from the keymap.

### 7. Leader: `Add` column order
- **Sheet [09]:** `a object`, then `n window`.
- **Application (`p_leader.png`):** `n window`, then `a add (menu)`.
- **Change:** order the rows within a section explicitly in `lib/rays_editor/leader.ml` (`group`), not by keymap order.
- The six columns, the labels, the `>` marks and the head row otherwise read like the sheet.

### 8. Submenu is much wider than the sheet's
- **Sheet [03]:** the `Level` submenu is 132 wide, just fitting `Point … p`.
- **Application (`p_sub.png`):** 180 wide for the same four rows, with its keys `p` / `o` far from the labels.
- **Change:** `ui.ml` `context_menu`, the submenu's width. Measure the submenu's own rows (lead slot + label + 24 + key + padding) instead of using a minimum.

### 9. Echo tips are used for every key press, and sit on top of graph cards
- **Sheet [08]:** echoes are messages (`Saved kit.rays`, `Undo: nothing to undo`).
- **Application (`p_echo.png`):** every chord is echoed as an information tip with the yellow dot (`Space k · all Flow keys`, `u · back (up a level)`). It is placed over the bottom-left card of the graph and stays visible while the prompt or key sheet it opened is on screen.
- **Change:** `core.ml` around line 3800 (`notice_at`, `Status_bar.tips`). Do not echo a key that opened an overlay, and keep the tips clear of the cards.
- **Refusal heuristic:** red ink is chosen by `notice_refused`, a keyword list at `core.ml` 1979–1985 (`"cannot"`, `"Clipboard:"`, `"Default:"`, …). Any refusal worded differently shows as information. Notices should carry `` `Refusal `` / `` `Info `` from where they are raised. I could not render one, since modifier keys are not scriptable.

### 10. Sheet widgets the application still hand-draws or lacks
- **Vector row and colour row [07]:** no kit function; the inspector draws its own (`Inspector.swatch_and_hex`, the vector fields).
- **Buttons:** `Pxui_shell.Kit.button` (`pxui_shell.ml` 311) is still a second painter beside `Ui.button`. They look the same now, but they are two implementations.
- **Unused painters:** `Paint.flag` and `Paint.ratio` appear to be unused by the application (my one grep for callers errored, so this rests on the implementer's report). `Tree` and `navigator.ml` draw their own flags, and `Chrome.splitters` shows its own tip while dragging instead of the accent `58 / 42` label.
- **Icon buttons with a chevron:** `Ui.button ~icon` takes text only; the sheet's `<` and `v` icon buttons are drawn by hand in `Chrome`.
- **Bare button ink:** the sheet's `Reset` is ink-2; `Ui.button ~bare` draws foreground unless `~ink` is passed (the harness does not pass it). Make ink-2 the default for `bare`.
- **Hatched progress bar (`d_progress.png`):** the stripes are soft and anti-aliased where the sheet's are crisp 1-point lines, and they poke past the box at its corners. `ui.ml` `Paint.hatch`: clip to the box and snap the lines.

### 11. Tab can put an accent box round a header's icon button
- **Application (`s_g_tab.png`):** after a Tab press the outline header's collapse `<` has a full accent rectangle.
- **Sheet:** focus is only ever an accent line under the control.
- **Change:** `pxui_shell.ml` `Chrome.update`, the `workspace-collapse-…` box. Give it the `focus_mark` flag and draw the 1-point accent line on its bottom row.

## Implementer's deviations, judged against the sheets

| Deviation | Verdict |
|---|---|
| Search prompt 420 wide | Not in any sheet; see 5 |
| `Size of its split` rows in the panel menu | Not in the sheet; see 6 |
| `Add` section order | Differs from the sheet; see 7 |
| Refusal by keyword list | Fragile; see 9 |
| Hard-coded leader keys in the panel menu | Will drift; see 6 |
| `Split right` = `Space o h` | Opposite of the sheet's print; needs an owner decision between sheet and keymap; see 6 |

Everything else compared (buttons and their states, switches, sections, sliders, text fields, messages, context menu, picker rows, tooltip, XY pad, key sheet, save prompt, open choice menu) reads the same as the sheet in the side-by-side pictures.