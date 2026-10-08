(* The kit's widgets, its overlays and the graph pane's zone tokens are compared pixel for pixel
   with goldens rendered by this kit (rev 3, specification/pxui.md) with DepartureMono: a change
   of a token or of a widget's geometry shows here.  The goldens are refreshed deliberately,
   with RAYS_UPDATE_FIXTURES=<dir>. *)
open Rays

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

let capture ?(config = config) prefix ~init ~update ~view =
  let directory = Filename.temp_dir "pxui-parity" "" in
  (* A static golden must not depend on the hardware pointer over its window. *)
  let update state (frame : Frame.t) = update state
      { frame with mouse = (-100., -100.); mouse_delta = (0., 0.);
        mouse_buttons = []; keys = []; events = [Event.MouseMoved (-100., -100.)] } in
  ignore (Sketch.export_state ~config ~directory ~prefix ~frames:2 ~init ~update
    ~view ());
  let image = Image.load_exn (Filename.concat directory (prefix ^ "-000001.png")) in
  let width, height = Image.get_size image in
  width, height, Result.get_ok (Image.Private.pixels image), directory

(* The floating widgets: a modal with a picker, and a context menu. *)
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
  (match Sys.getenv_opt "RAYS_UPDATE_FIXTURES" with
   | Some target when width > config.width -> Sys.rename (Filename.concat directory "overlays-000001.png")
       (Filename.concat target "kit_overlays_2x.png")
   | _ -> ());
  let golden = Image.load_exn "fixtures/kit_overlays_2x.png" in
  if Image.get_size golden <> (width, height) then
    print_endline "PXUI overlay parity: skipped (golden is 2x)"
  else if Result.get_ok (Image.Private.pixels golden) <> actual then
    failwith "PXUI modal/picker/context menu drifted from fixtures/kit_overlays_2x.png"
  else print_endline "PXUI overlay parity: exact"

(* The graph pane's zone tokens: for, fold, sum, a hollow dashed fn
   zone and a let scope, with the socket colours of lists and functions. *)
let zones ui =
  let theme = Pxui.Ui.theme ui in
  let box = Pxui.Ui.box ui ~w:(Pxui.Ui.Px 320.) ~h:(Pxui.Ui.Px 390.) ~at:(0., 0.) "zones" in
  Pxui.Ui.draw ui box (fun paint _ ->
    let module P = Pxui.Ui.Paint in
    List.iteri (fun i (zone : Pxui.Theme.zone) ->
      let x = 12. +. float (i mod 2) *. 154. and y = 12. +. float (i / 2) *. 92. in
      P.rect paint ~x ~y ~w:142. ~h:80. ~fill:zone.fill ();
      if zone.dashed then P.dashed_rect paint ~x ~y ~w:142. ~h:80. zone.edge
      else P.stroke paint ~x:(x +. 0.5) ~y:(y +. 0.5) ~w:141. ~h:79. zone.edge)
      [ Pxui.Theme.zone_for theme; Pxui.Theme.zone_fold theme; Pxui.Theme.zone_sum theme;
        Pxui.Theme.zone_fn theme; Pxui.Theme.zone_let theme;
        Pxui.Theme.zone_branch theme ~taken:false; Pxui.Theme.zone_branch theme ~taken:true ];
    let ports = Pxui.Theme.ports theme in
    List.iteri (fun i color -> P.rect paint ~x:(170. +. float i *. 20.) ~y:(200. +. 0.) ~w:10. ~h:10.
      ~fill:color ()) [ ports.text; ports.fn; ports.record ])

let check_zones () =
  let width, height, actual, directory =
    capture ~config:{config with height = 390} "zones" ~init:(fun _ -> Pxui.Ui.create ())
      ~update:(fun ui frame -> Pxui.Ui.frame ui frame zones; ui)
      ~view:(fun ui _ -> Scene.clear background :: Pxui.Ui.scene ui) in
  (match Sys.getenv_opt "RAYS_UPDATE_FIXTURES" with
   | Some target when width > config.width -> Sys.rename (Filename.concat directory "zones-000001.png")
       (Filename.concat target "kit_zones_2x.png")
   | _ -> ());
  let golden = Image.load_exn "fixtures/kit_zones_2x.png" in
  if Image.get_size golden <> (width, height) then
    print_endline "PXUI zone parity: skipped (golden is 2x)"
  else if Result.get_ok (Image.Private.pixels golden) <> actual then
    failwith "PXUI zone tokens drifted from fixtures/kit_zones_2x.png"
  else print_endline "PXUI zone parity: exact"

let check_table () =
  let width, height, actual, directory = capture "table" ~init:(fun _ -> Pxui.Ui.create ())
    ~update:(fun ui frame -> ignore (Pxui.Ui.frame ui frame (fun ui ->
      Pxui.Ui.table ui ~at:(8., 8.) ~w:304. ~h:280. ~headers:[|"index"; "P.x"; "weight"; "group"|]
        ~rows:1000000 ~cell:(fun row column -> if column = 0 then string_of_int row
          else if column = 3 then if row mod 2 = 0 then "1" else "0"
          else Printf.sprintf "%g" (float (row + column) *. 0.125)) "table")); ui)
    ~view:(fun ui _ -> Scene.clear background :: Pxui.Ui.scene ui) in
  (match Sys.getenv_opt "RAYS_UPDATE_FIXTURES" with
   | Some target when width > config.width ->
       Sys.rename (Filename.concat directory "table-000001.png") (Filename.concat target "kit_table_2x.png")
   | _ -> ());
  let golden = Image.load_exn "fixtures/kit_table_2x.png" in
  if Image.get_size golden <> (width, height) then print_endline "PXUI table parity: skipped (golden is 2x)"
  else if Result.get_ok (Image.Private.pixels golden) <> actual then failwith "PXUI table golden drifted"
  else print_endline "PXUI table parity: exact"

let run () =
  check_overlays ();
  check_zones ();
  check_table ();
  let golden = Image.load_exn "fixtures/kit_panel_2x.png" in
  let old_width, old_height = Image.get_size golden in
  let expected = Result.get_ok (Image.Private.pixels golden) in
  let width, height, actual, directory =
    capture "new" ~init:(fun _ -> Pxui.Ui.create ())
      ~update:(fun ui frame -> Pxui.Ui.frame ui frame new_panel; ui)
      ~view:(fun ui _ -> Scene.clear background :: Pxui.Ui.scene ui) in
  (match Sys.getenv_opt "RAYS_UPDATE_FIXTURES" with
   | Some target when width > config.width -> Sys.rename (Filename.concat directory "new-000001.png")
       (Filename.concat target "kit_panel_2x.png")
   | _ -> ());
  let density = width / config.width in
  if (old_width, old_height) <> (width, height) then
    Printf.printf "PXUI Ui parity: skipped at %dx (golden is 2x)\n" density
  else if expected <> actual then failwith "PXUI kit widgets drifted from fixtures/kit_panel_2x.png"
  else Printf.printf "PXUI Ui parity: %dx%d at %dx, exact\n" width height density
