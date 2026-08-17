open Prismel

type model = {
  angle : float;
  ui : Pxui.t;
}

let init _frame =
  let ui =
    Pxui.create ()
    |> Pxui.label ~text:"PXUI"
    |> Pxui.accordion ~name:"motion" ~label:"Motion" ~expanded:true
         (fun ui -> ui
           |> Pxui.toggle ~name:"animate" ~label:"Animate" ~value:true
           |> Pxui.slider ~name:"radius" ~label:"Radius"
                ~min:10. ~max:120. ~value:48.
           |> Pxui.xy ~name:"center" ~label:"Center"
                ~x_range:(340., 600.) ~y_range:(80., 300.)
                ~value:(470., 180.))
    |> Pxui.accordion ~name:"appearance" ~label:"Appearance" ~expanded:false
         (fun ui -> ui
           |> Pxui.range ~name:"band" ~label:"Band"
                ~min:0. ~max:1. ~low:0.2 ~high:0.8
           |> Pxui.choice ~name:"palette" ~label:"Palette"
                ~options:["ocean"; "sunset"; "mono"] ~selected:0
           |> Pxui.text_field ~name:"caption" ~label:"Caption"
                ~value:"Functional UI")
    |> Pxui.button ~name:"quit" ~label:"Quit"
  in
  { angle = 0.; ui }

let update model (frame : Frame.t) =
  let ui, changes = Pxui.update_frame model.ui frame in
  if List.exists (function Pxui.Clicked "quit" -> true | _ -> false) changes
  then Sketch.quit ();
  if Sketch.is_headless () && frame.count >= 3 then Sketch.quit ();
  let angle =
    match Pxui.toggle_value ui "animate" with
    | Some true -> model.angle +. frame.dt
    | _ -> model.angle
  in
  { angle; ui }

let view model _frame =
  let radius =
    Option.value ~default:48. (Pxui.slider_value model.ui "radius")
    |> int_of_float
  in
  let pulse = int_of_float (40. *. (0.5 +. (0.5 *. sin model.angle))) in
  let center =
    Option.value ~default:(470., 180.) (Pxui.xy_value model.ui "center")
  in
  let color =
    match Pxui.choice_value model.ui "palette" with
    | Some "sunset" -> Color.rgb 240 (100 + pulse) 90
    | Some "mono" -> Color.gray (140 + pulse)
    | _ -> Color.rgb (80 + pulse) 150 225
  in
  Scene.(
    [
      clear (Color.rgb 17 19 24);
      circle ~at:(int_of_float (fst center), int_of_float (snd center))
        ~radius ~fill:color ();
    ]
    @ Pxui.scene model.ui)

let () =
  ignore
    (Sketch.run_state
       ~config:{ Sketch.default_config with
         width = 640;
         height = 360;
         title = "PXUI example";
       }
       ~init ~update ~view ())
