(* The immediate-mode kit must draw the retired retained PXUI panel pixel for
   pixel: same face, sizes, colours, text positions, and control geometry.
   [fixtures/kit_panel_2x.png] is that panel as the retained PXUI rendered it
   at 2x before it was removed. The only permitted differences are the corner
   squares of 1-point strokes (the old tessellated stroke notched outer
   corners and double-blended inner ones) and the XY knob, now an
   anti-aliased circle instead of a 32-gon. *)
open Prismel

let rows = [
  `Label "PXUI"; `Accordion "Motion"; `Toggle ("Animate", true);
  `Toggle ("Wire", false); `Slider ("Radius", 48.); `Int ("Steps", 8);
  `Xy "Center"; `Range "Band"; `Choice "Palette"; `Text "Caption";
  `Button "Quit" ]

let new_panel ui =
  Pxui.Ui.panel ui "panel" (fun () ->
    List.iter (fun row -> match row with
      | `Label text -> Pxui.Ui.label ui text
      | `Accordion name ->
          ignore (Pxui.Ui.accordion ui ~expanded:true name (fun () -> ()))
      | `Toggle (name, value) -> ignore (Pxui.Ui.toggle ui name value)
      | `Slider (name, value) ->
          ignore (Pxui.Ui.slider ui name ~range:(10., 120.) value)
      | `Int (name, value) -> ignore (Pxui.Ui.int_slider ui name ~range:(1, 64) value)
      | `Xy name ->
          ignore (Pxui.Ui.xy ui name ~x_range:(340., 600.) ~y_range:(80., 300.)
            (470., 180.))
      | `Range name -> ignore (Pxui.Ui.range_slider ui name ~range:(0., 1.) (0.2, 0.8))
      | `Choice name -> ignore (Pxui.Ui.choice ui name ["ocean"; "sunset"; "mono"] 1)
      | `Text name -> ignore (Pxui.Ui.text_field ui name "Functional UI")
      | `Button name -> ignore (Pxui.Ui.button ui name)) rows)

let config = { Sketch.default_config with width = 320; height = 300;
  title = "PXUI parity" }
let background = Color.rgb 228 139 161

let capture prefix ~init ~update ~view =
  let directory = Filename.temp_dir "pxui-parity" "" in
  ignore (Sketch.export_state ~config ~directory ~prefix ~frames:2 ~init ~update
    ~view ());
  let image = Image.load_exn (Filename.concat directory (prefix ^ "-000001.png")) in
  let width, height = Image.get_size image in
  width, height, Result.get_ok (Image.Private.pixels image), directory

(* Control rectangles of the stroked widgets, in logical points. *)
let stroked_controls () =
  let inner_x = 15 and inner_w = 274 and label = 120 in
  List.concat (List.mapi (fun index row ->
    let y = 15 + (index * 24) in
    let value = inner_x + label, y + 3, inner_w - label, 18 in
    let cx, cy, cw, ch = value in
    match row with
    | `Toggle _ -> [inner_x + inner_w - 40, y + 3, 40, 18]
    | `Slider _ | `Int _ -> [cx, cy + 4, cw, ch - 8]
    | `Range _ -> [cx, cy + 7, cw, ch - 14]
    | `Xy _ | `Choice _ | `Text _ -> [value]
    | `Label _ | `Accordion _ | `Button _ -> []) rows)

let knob () =
  let index = 6 in
  let y = 15 + (index * 24) in
  let cx = 135 and cy = y + 3 and cw = 154 and ch = 18 in
  let px = cx + int_of_float ((130. /. 260. *. float (cw - 1)) +. 0.5)
  and py = cy + int_of_float ((100. /. 220. *. float (ch - 1)) +. 0.5) in
  px - 7, py - 7, 14, 14

let permitted density (x, y) =
  let lx = (float x +. 0.5) /. float density and ly = (float y +. 0.5) /. float density in
  let near edge value = Float.abs (value -. float edge) <= 0.5 in
  let kx, ky, kw, kh = knob () in
  (lx >= float kx && lx < float (kx + kw) && ly >= float ky && ly < float (ky + kh))
  || List.exists (fun (cx, cy, cw, ch) ->
    (near cx lx || near (cx + cw) lx) && (near cy ly || near (cy + ch) ly))
    (stroked_controls ())

(* Overlay widgets have no retired counterpart; their golden is this kit's own
   2x rendering, refreshed deliberately with PRISMEL_UPDATE_FIXTURES=<dir>. *)
let overlays ui =
  ignore (Pxui.Ui.modal ui ~width:220. "modal" (fun () ->
    Pxui.Ui.label ui "Presets";
    Pxui.Ui.picker ui ~limit:3 "Search presets" ~query:""
      (fun _ -> [| "wall", "09-24"; "tower", "09-23"; "arch", "09-20";
                   "dome", "09-19" |])));
  ignore (Pxui.Ui.context_menu ui ~at:(12., 200.) "context"
    ["View", true; "Set active camera", false; "Delete", true])

let check_overlays () =
  let width, height, actual, directory =
    capture "overlays" ~init:(fun _ -> Pxui.Ui.create ())
      ~update:(fun ui frame -> Pxui.Ui.frame ui frame overlays; ui)
      ~view:(fun ui _ -> Scene.clear background :: Pxui.Ui.scene ui) in
  (match Sys.getenv_opt "PRISMEL_UPDATE_FIXTURES" with
   | Some target -> Sys.rename (Filename.concat directory "overlays-000001.png")
       (Filename.concat target "kit_overlays_2x.png")
   | None -> ());
  let golden = Image.load_exn "fixtures/kit_overlays_2x.png" in
  if Image.get_size golden <> (width, height) then
    print_endline "PXUI overlay parity: skipped (golden is 2x)"
  else if Result.get_ok (Image.Private.pixels golden) <> actual then
    failwith "PXUI modal/picker/context menu drifted from fixtures/kit_overlays_2x.png"
  else print_endline "PXUI overlay parity: exact"

let run () =
  check_overlays ();
  let golden = Image.load_exn "fixtures/kit_panel_2x.png" in
  let old_width, old_height = Image.get_size golden in
  let expected = Result.get_ok (Image.Private.pixels golden) in
  let width, height, actual, _ =
    capture "new" ~init:(fun _ -> Pxui.Ui.create ())
      ~update:(fun ui frame -> Pxui.Ui.frame ui frame new_panel; ui)
      ~view:(fun ui _ -> Scene.clear background :: Pxui.Ui.scene ui) in
  let density = width / config.width in
  if (old_width, old_height) <> (width, height) then
    Printf.printf "PXUI Ui parity: skipped at %dx (golden is 2x)\n" density
  else begin
  let differences = ref 0 and unexpected = ref [] in
  for pixel = 0 to (width * height) - 1 do
    let offset = pixel * 4 in
    if Bytes.sub expected offset 4 <> Bytes.sub actual offset 4 then begin
      incr differences;
      let point = pixel mod width, pixel / width in
      if not (permitted density point) then unexpected := point :: !unexpected
    end
  done;
  match List.rev !unexpected with
  | [] ->
      Printf.printf "PXUI Ui parity: %dx%d at %dx, %d permitted pixel changes\n"
        width height density !differences
  | (x, y) :: _ as points ->
      let offset = ((y * width) + x) * 4 in
      let show bytes = String.concat "," (List.init 4 (fun k ->
        string_of_int (Char.code (Bytes.get bytes (offset + k))))) in
      failwith (Printf.sprintf
        "%d unexpected pixel changes; first at (%d,%d): new %s, old %s"
        (List.length points) x y (show actual) (show expected))
  end
