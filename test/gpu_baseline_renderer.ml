open Prismel

type frame_facts = {
  count : int;
  logical_width : int;
  logical_height : int;
  drawable_width : int;
  drawable_height : int;
  pixel_scale_x : float;
  pixel_scale_y : float;
}

type model = {
  image : Image.t;
  ui : Pxui.t;
  capture_path : string;
  trace_path : string;
  captured : bool;
  facts : frame_facts option;
}

let result_exn = function
  | Ok value -> value
  | Error message -> failwith message

let target_name () = match Sketch.render_target () with
  | Sketch.Native -> "native"
  | Headless -> "headless"
  | Web -> "web"

let fixture_path =
  Path.empty
  |> Path.move_to 28. 52.
  |> Path.line_to 166. 52.
  |> Path.line_to 166. 176.
  |> Path.line_to 28. 176.
  |> Path.close
  |> Path.move_to 66. 82.
  |> Path.line_to 66. 146.
  |> Path.line_to 130. 146.
  |> Path.line_to 130. 82.
  |> Path.close

let image_fixture () =
  let canvas = Canvas.create_exn ~width:72 ~height:72 in
  Canvas.render canvas Scene.[
    clear (Color.hex_exn "#0f172a");
    rect ~at:(4, 4) ~w:64 ~h:64 ~fill:(Color.hex_exn "#164e63")
      ~stroke:(Color.hex_exn "#67e8f9") ();
    circle ~at:(36, 36) ~radius:24 ~fill:(Color.rgba 251 191 36 210) ();
    translate 36 36 [
      rotate (Float.pi /. 4.) [
        rect ~at:(-16, -5) ~w:32 ~h:10 ~fill:(Color.hex_exn "#f8fafc") ();
      ];
    ];
  ];
  let image = result_exn (Canvas.to_image canvas) in
  Canvas.destroy canvas;
  image

let ui_fixture () =
  Pxui.create ~x:414 ~y:28 ~width:206 ~row_height:30 ~padding:8 ()
  |> Pxui.label ~text:"PXUI baseline"
  |> Pxui.toggle ~name:"enabled" ~label:"Enabled" ~value:true
  |> Pxui.slider ~name:"gain" ~label:"Gain" ~min:0. ~max:1. ~value:0.625
  |> Pxui.int_slider ~name:"steps" ~label:"Steps" ~min:1 ~max:12 ~value:7
  |> Pxui.text_field ~name:"title" ~label:"Title" ~value:"Prismel"
  |> Pxui.choice ~name:"mode" ~label:"Mode"
       ~options:["Solid"; "Wire"; "Points"] ~selected:1
  |> Pxui.range ~name:"range" ~label:"Range" ~min:(-1.) ~max:1.
       ~low:(-0.35) ~high:0.7
  |> Pxui.xy ~name:"xy" ~label:"XY" ~x_range:(-1., 1.)
       ~y_range:(-1., 1.) ~value:(0.35, -0.4)

let scene3_fixture =
  let warm = Material.create ~diffuse:(Color.hex_exn "#fb923c")
      ~ambient:(Color.hex_exn "#431407") ~specular:Color.white
      ~shininess:36. ()
  and cool = Material.create ~diffuse:(Color.hex_exn "#38bdf8")
      ~ambient:(Color.hex_exn "#082f49") ~specular:Color.white
      ~shininess:24. ()
  in
  Scene3.create ~samples:4 ~ambient:(Color.rgb 18 22 30)
    ~lights:[
      Light.directional ~direction:(Vec3.create (-0.7) (-1.) (-1.5))
        ~diffuse:(Color.hex_exn "#fff7ed") ();
      Light.directional ~direction:(Vec3.create 0.8 0.2 (-0.6))
        ~diffuse:(Color.hex_exn "#7dd3fc") ~intensity:0.45 ();
    ]
    [
      Scene3.rotate ~axis:Vec3.unit_y 0.58 [
        Scene3.rotate ~axis:Vec3.unit_x (-0.31) [
          Scene3.box ~material:warm ~cull:Scene3.Cull_back
            ~width:1.35 ~height:1.35 ~depth:1.35 ();
        ];
      ];
      Scene3.translate (Vec3.create 1.15 (-0.55) 0.15) [
        Scene3.sphere ~material:cool ~cull:Scene3.Cull_back ~radius:0.48 ();
      ];
    ]

let camera =
  Camera.perspective ~at:(Vec3.create 0. 0.25 4.7)
    ~target:(Vec3.create 0.1 0. 0.) ()

let scene model =
  let base = Scene.[
    clear (Color.hex_exn "#07111f");
    rounded_rect ~at:(16, 18) ~w:382 ~h:208 ~radius:12
      ~fill:(Color.hex_exn "#111827") ~stroke:(Color.hex_exn "#334155") ();
    path ~fill_rule:Path.Even_odd ~fill:(Color.hex_exn "#155e75")
      ~stroke:(Color.hex_exn "#67e8f9") fixture_path;
    clip ~at:(36, 60) ~w:122 ~h:108 [
      translate 96 114 [
        rotate 0.42 [
          rect ~at:(-68, -9) ~w:136 ~h:18
            ~fill:(Color.rgba 244 63 94 190) ();
        ];
      ];
    ];
    image model.image ~at:(106, 142) ~scale:0.82 ~angle:(-0.18)
      ~center:(36, 36) ();
    debug_text ~at:(26, 198) ~color:(Color.hex_exn "#f8fafc")
      "FIXED 8x8";
    view3d ~viewport:(184, 34, 206, 184) ~camera scene3_fixture;
    rounded_rect ~at:(414, 18) ~w:206 ~h:444 ~radius:10
      ~fill:(Color.rgba 15 23 42 180) ~stroke:(Color.hex_exn "#475569") ();
    text ~at:(22, 244) ~size:17 ~color:(Color.hex_exn "#e2e8f0")
      "Scene2 · Canvas · Scene3 · PXUI";
    blend Scene.Add [
      circle ~at:(78, 306) ~radius:34 ~fill:(Color.rgba 14 165 233 150) ();
      circle ~at:(106, 306) ~radius:34 ~fill:(Color.rgba 244 63 94 150) ();
    ];
    translate 164 286 [
      scale 1.25 0.72 [
        ellipse ~at:(0, 0) ~rx:45 ~ry:30
          ~fill:(Color.rgba 34 197 94 180) ~stroke:Color.white ();
      ];
    ];
    polygon [238, 278; 304, 268; 350, 318; 286, 352; 230, 326]
      ~fill:(Color.hex_exn "#a78bfa") ~stroke:(Color.hex_exn "#f5f3ff") ();
    bezier [24, 392; 92, 340; 148, 442; 214, 382]
      ~steps:32 ~color:(Color.hex_exn "#fbbf24") ();
    line ~from_:(24, 438) ~to_:(382, 438) ~width:3
      ~color:(Color.hex_exn "#22d3ee") ();
  ] in
  base @ Pxui.scene model.ui

let init _frame =
  if Array.length Sys.argv <> 3 then
    invalid_arg "gpu_baseline_renderer: expected PNG and trace output paths";
  {
    image = image_fixture ();
    ui = ui_fixture ();
    capture_path = Sys.argv.(1);
    trace_path = Sys.argv.(2);
    captured = false;
    facts = None;
  }

let update model (frame : Frame.t) =
  if frame.count = 4 then begin
    let capture = result_exn (Canvas.capture ()) in
    Fun.protect ~finally:(fun () -> Canvas.destroy capture) (fun () ->
      result_exn (Canvas.save_png capture model.capture_path));
    Sketch.quit ();
    {
      model with
      captured = true;
      facts = Some {
        count = frame.count - 1;
        logical_width = frame.width;
        logical_height = frame.height;
        drawable_width = frame.drawable_width;
        drawable_height = frame.drawable_height;
        pixel_scale_x = fst frame.pixel_scale;
        pixel_scale_y = snd frame.pixel_scale;
      };
    }
  end else model

let write_trace model facts =
  let channel = open_out_bin model.trace_path in
  Fun.protect ~finally:(fun () -> close_out channel) (fun () ->
    Printf.fprintf channel
      "{\n  \"schema\": 1,\n  \"target\": \"%s\",\n  \"captured_presented_frame\": %d,\n  \"logical_size\": [%d, %d],\n  \"drawable_size\": [%d, %d],\n  \"pixel_scale\": [%.6f, %.6f],\n  \"lifecycle\": [\n    \"canvas.create\",\n    \"canvas.render\",\n    \"canvas.to_image\",\n    \"canvas.destroy\",\n    \"capture.create\",\n    \"capture.save_png\",\n    \"capture.destroy\",\n    \"image.destroy\"\n  ]\n}\n"
      (target_name ()) facts.count facts.logical_width facts.logical_height
      facts.drawable_width facts.drawable_height facts.pixel_scale_x
      facts.pixel_scale_y)

let stop model =
  if not model.captured then failwith "baseline renderer did not capture a frame";
  Image.destroy model.image;
  match model.facts with
  | None -> failwith "baseline renderer omitted captured frame facts"
  | Some facts -> write_trace model facts

let () =
  ignore
    (Sketch.run_state
      ~config:{
        Sketch.default_config with
        width = 640;
        height = 480;
        title = "Prismel GPU migration baseline";
        fps = Some 120;
        domains = Some 1;
        clock = Sketch.Fixed (1. /. 60.);
        resizable = false;
      }
      ~init ~update ~view:(fun model _ -> scene model) ~on_stop:stop ())
