open Prismel

let dot_field = Scene.group
  (List.init (54 * 30) (fun index ->
     Scene.rect ~at:((index mod 54) * 12, (index / 54) * 12)
       ~w:1 ~h:1 ~fill:(Color.rgb 30 30 30) ()))

let palettes = ["ocean"; "sunset"; "mono"]

(* Values live in the model; [ui] is the widget cache threaded through it. *)
type model = {
  ui : Pxui.Ui.t;
  angle : float;
  animate : bool;
  radius : float;
  center : float * float;
  band : float * float;
  palette : int;
  caption : string;
}

let init _frame = {
  ui = Pxui.Ui.create (); angle = 0.; animate = true; radius = 48.;
  center = (470., 180.); band = (0.2, 0.8); palette = 0;
  caption = "Functional UI";
}

let update model (frame : Frame.t) =
  let model = Pxui.Ui.frame model.ui frame @@ fun ui ->
    Pxui.Ui.panel ui "PXUI" @@ fun () ->
    Pxui.Ui.label ui "PXUI";
    let model = Option.value ~default:model
        (Pxui.Ui.accordion ui ~expanded:true "Motion" (fun () ->
          let animate = Pxui.Ui.toggle ui "Animate" model.animate in
          let radius = Pxui.Ui.slider ui "Radius" ~range:(10., 120.) model.radius in
          let center = Pxui.Ui.xy ui "Center" ~x_range:(340., 600.)
              ~y_range:(80., 300.) model.center in
          { model with animate; radius; center })) in
    let model = Option.value ~default:model
        (Pxui.Ui.accordion ui "Appearance" (fun () ->
          let band = Pxui.Ui.range_slider ui "Band" ~range:(0., 1.) model.band in
          let palette = Pxui.Ui.choice ui "Palette" palettes model.palette in
          (* Focus Caption to try Command/Ctrl-C, X, and V. *)
          let caption = Pxui.Ui.text_field ui "Caption" model.caption in
          { model with band; palette; caption })) in
    if Pxui.Ui.button ui "Quit" then Sketch.quit ();
    model in
  { model with angle = if model.animate then model.angle +. frame.dt else model.angle }

let view model _frame =
  let pulse = int_of_float (40. *. (0.5 +. (0.5 *. sin model.angle))) in
  let x, y = model.center in
  let color = match List.nth palettes model.palette with
    | "sunset" -> Color.rgb 240 (100 + pulse) 90
    | "mono" -> Color.gray (140 + pulse)
    | _ -> Color.rgb (80 + pulse) 150 225 in
  Scene.clear (Color.rgb 228 139 161)
  :: dot_field
  :: Scene.circle ~at:(int_of_float x, int_of_float y)
       ~radius:(int_of_float model.radius) ~fill:color ()
  :: Pxui.Ui.scene model.ui

let on_stop model = Pxui.Ui.destroy model.ui

let () =
  let config = { Sketch.default_config with
    width = 640; height = 360; title = "PXUI example" } in
  match Array.to_list Sys.argv with
  | [_; "--export"; directory] ->
      ignore (Sketch.export_state ~config ~directory ~prefix:"pxui"
        ~frames:1 ~init ~update ~view ~on_stop ())
  | [_] -> ignore (Sketch.run_state ~config ~init ~update ~view ~on_stop ())
  | _ -> invalid_arg "usage: pxui [--export DIRECTORY]"
