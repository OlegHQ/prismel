open Prismel
open Tsdl

let format_rgba32 =
  if Sys.big_endian then Sdl.Pixel.format_rgba8888
  else Sdl.Pixel.format_abgr8888

let sdl_exn context = function
  | Ok value -> value
  | Error (`Msg message) -> failwith (context ^ ": " ^ message)

let push_mouse_motion x y =
  let event = Sdl.Event.create () in
  Sdl.Event.set event Sdl.Event.typ Sdl.Event.mouse_motion;
  Sdl.Event.set event Sdl.Event.mouse_motion_x x;
  Sdl.Event.set event Sdl.Event.mouse_motion_y y;
  if not (sdl_exn "push mouse motion" (Sdl.push_event event)) then
    failwith "SDL rejected a synthetic mouse motion"

let push_mouse_button ?(button = 1) event_type x y =
  let event = Sdl.Event.create () in
  Sdl.Event.set event Sdl.Event.typ event_type;
  Sdl.Event.set event Sdl.Event.mouse_button_button button;
  Sdl.Event.set event Sdl.Event.mouse_button_x x;
  Sdl.Event.set event Sdl.Event.mouse_button_y y;
  if not (sdl_exn "push mouse button" (Sdl.push_event event)) then
    failwith "SDL rejected a synthetic mouse button event"

let verify_two_x_renderer () =
  let surface =
    sdl_exn "2x probe surface"
      (Sdl.create_rgb_surface_with_format ~w:128 ~h:96 ~depth:32
         format_rgba32)
  in
  let renderer =
    match Sdl.create_software_renderer surface with
    | Ok renderer -> renderer
    | Error (`Msg message) ->
        Sdl.free_surface surface;
        failwith ("2x probe renderer: " ^ message)
  in
  let previous_renderer = !Image.Private.current_renderer in
  Fun.protect
    ~finally:(fun () ->
      Font.release_renderer renderer;
      Image.Private.current_renderer := previous_renderer;
      Sdl.destroy_renderer renderer;
      Sdl.free_surface surface)
    (fun () ->
      sdl_exn "2x logical size"
        (Sdl.render_set_logical_size renderer 64 48);
      ignore (Sdl.set_render_draw_color renderer 0 0 0 255);
      sdl_exn "2x clear" (Sdl.render_clear renderer);
      ignore (Sdl.set_render_draw_color renderer 255 0 0 255);
      let full = Sdl.Rect.create ~x:0 ~y:0 ~w:64 ~h:48 in
      sdl_exn "2x logical rectangle"
        (Sdl.render_fill_rect renderer (Some full));
      Sdl.render_present renderer;
      sdl_exn "2x surface lock" (Sdl.lock_surface surface);
      Fun.protect
        ~finally:(fun () -> Sdl.unlock_surface surface)
        (fun () ->
          let values = Sdl.get_surface_pixels surface Bigarray.int32 in
          let stride = Sdl.get_surface_pitch surface / 4 in
          let format =
            sdl_exn "2x pixel format"
              (Sdl.alloc_format format_rgba32)
          in
          Fun.protect ~finally:(fun () -> Sdl.free_format format) (fun () ->
            match Sdl.get_rgba format values.{(95 * stride) + 127} with
            | 255, 0, 0, 255 -> ()
            | _ ->
                failwith
                  "logical rectangle did not reach the physical bottom-right pixel"));
      Image.Private.set_renderer renderer;
      match Font.system ~size:14 () with
      | Error (`Msg message) -> failwith message
      | Ok font ->
          let image =
            sdl_exn "2x system text"
              (Font.cached_text font "Retina" (Font.Blended Color.white))
          in
          let logical_width, logical_height = Image.get_size image in
          let physical_width, physical_height =
            match Sdl.query_texture (Image.Private.get_texture image) with
            | Ok (_, _, dimensions) -> dimensions
            | Error (`Msg message) ->
                failwith ("2x text texture query: " ^ message)
          in
          if abs (physical_width - (2 * logical_width)) > 2
             || abs (physical_height - (2 * logical_height)) > 2
          then
            failwith
              "system text was not rasterized at backing-pixel density")

let output_u16 channel value =
  output_byte channel (value land 0xff);
  output_byte channel ((value lsr 8) land 0xff)

let output_u32 channel value =
  output_u16 channel (value land 0xffff);
  output_u16 channel ((value lsr 16) land 0xffff)

let write_silent_wav filename =
  let samples = 80 in
  let channel = open_out_bin filename in
  Fun.protect ~finally:(fun () -> close_out channel) (fun () ->
    output_string channel "RIFF";
    output_u32 channel (36 + (samples * 2));
    output_string channel "WAVEfmt ";
    output_u32 channel 16;
    output_u16 channel 1;
    output_u16 channel 1;
    output_u32 channel 8_000;
    output_u32 channel 16_000;
    output_u16 channel 2;
    output_u16 channel 16;
    output_string channel "data";
    output_u32 channel (samples * 2);
    for _ = 1 to samples do output_u16 channel 0 done)

let find_test_font () =
  [
    "/System/Library/Fonts/Supplemental/Arial.ttf";
    "/System/Library/Fonts/Supplemental/Courier New.ttf";
    "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf";
    "/usr/share/fonts/TTF/DejaVuSans.ttf";
  ]
  |> List.find_opt Sys.file_exists

let init (frame : Frame.t) =
  if frame.size <> (32, 32) then failwith "incorrect initial frame size";
  let window_renderer = Low.Window.get_renderer () in
  if Sdl.render_get_logical_size window_renderer <> frame.size then
    failwith "renderer logical size diverged from the sketch coordinate space";
  let output_size =
    sdl_exn "window drawable size"
      (Sdl.get_renderer_output_size window_renderer)
  in
  if frame.drawable_size <> output_size
     || frame.drawable_width <> fst output_size
     || frame.drawable_height <> snd output_size
  then failwith "frame drawable facts did not match the native render target";
  if frame.pixel_scale <> (1., 1.) then
    failwith "dummy renderer unexpectedly changed the backing scale";
  verify_two_x_renderer ();
  let empty_ui =
    Pxui.create ~x:0 ~y:0 ~width:240 ()
    |> Pxui.text_field ~name:"empty" ~label:"Empty" ~value:""
  in
  let empty_ui_canvas = Canvas.create_exn ~width:240 ~height:40 in
  Canvas.render empty_ui_canvas (Pxui.scene empty_ui);
  Canvas.destroy empty_ui_canvas;
  let canvas = Canvas.create_exn ~width:8 ~height:8 in
  Canvas.render canvas Scene.[
    clear Color.black;
    clip ~at:(2, 2) ~w:4 ~h:4 [
      rect ~at:(0, 0) ~w:8 ~h:8 ~fill:Color.red ();
    ];
  ];
  (match Canvas.pixel canvas ~x:3 ~y:3, Canvas.pixel canvas ~x:0 ~y:0 with
   | Some inside, Some outside
     when Color.equal inside Color.red && Color.equal outside Color.black -> ()
   | _ -> failwith "offscreen clipping or pixel readback failed");
  Canvas.map_pixels canvas (fun ~x:_ ~y:_ -> Color.invert);
  (match Canvas.pixel canvas ~x:0 ~y:0 with
   | Some color when Color.equal color Color.white -> ()
   | _ -> failwith "canvas pixel mapping failed");
  let nested_squares =
    Path.empty
    |> Path.move_to 0. 0.
    |> Path.line_to 7. 0.
    |> Path.line_to 7. 7.
    |> Path.line_to 0. 7.
    |> Path.close
    |> Path.move_to 2. 2.
    |> Path.line_to 5. 2.
    |> Path.line_to 5. 5.
    |> Path.line_to 2. 5.
    |> Path.close
  in
  Canvas.render canvas Scene.[
    clear Color.black;
    path ~fill:Color.red nested_squares;
  ];
  (match Canvas.pixel canvas ~x:1 ~y:1, Canvas.pixel canvas ~x:3 ~y:3 with
   | Some outer, Some hole
     when Color.equal outer Color.red && Color.equal hole Color.black -> ()
   | _ -> failwith "even-odd multi-contour path did not preserve its hole");
  Canvas.render canvas Scene.[
    clear Color.black;
    path ~fill_rule:Path.Non_zero ~fill:Color.red nested_squares;
  ];
  (match Canvas.pixel canvas ~x:3 ~y:3 with
   | Some color when Color.equal color Color.red -> ()
   | _ -> failwith "non-zero path fill did not honor contour winding");
  let source = Canvas.create_exn ~width:4 ~height:4 in
  let mask = Canvas.create_exn ~width:4 ~height:4 in
  Canvas.render source Scene.[clear Color.red];
  Canvas.render mask Scene.[
    clear Color.transparent;
    rect ~at:(0, 0) ~w:2 ~h:4 ~fill:Color.white ();
  ];
  Canvas.apply_mask ~source ~mask;
  (match Canvas.pixel source ~x:0 ~y:1, Canvas.pixel source ~x:3 ~y:1 with
   | Some visible, Some hidden when visible.a = 255 && hidden.a = 0 -> ()
   | _ -> failwith "canvas alpha mask did not compose source pixels");
  Canvas.destroy source;
  Canvas.destroy mask;
  let transformed = Canvas.create_exn ~width:16 ~height:16 in
  Canvas.render transformed Scene.[
    clear Color.black;
    translate 8 8 [
      rotate (Float.pi /. 4.) [
        rect ~at:(-4, -1) ~w:8 ~h:2 ~fill:Color.red ();
      ];
    ];
  ];
  (match
     Canvas.pixel transformed ~x:8 ~y:8,
     Canvas.pixel transformed ~x:6 ~y:10
   with
   | Some center, Some outside
     when Color.equal center Color.red && Color.equal outside Color.black -> ()
   | _ -> failwith "rotated rectangle did not transform its full geometry");
  Canvas.render transformed Scene.[
    clear Color.black;
    translate 8 8 [
      scale 2. 0.5 [
        circle ~at:(0, 0) ~radius:3 ~fill:Color.cyan ();
      ];
    ];
  ];
  (match
     Canvas.pixel transformed ~x:12 ~y:8,
     Canvas.pixel transformed ~x:8 ~y:11
   with
   | Some wide, Some outside
     when Color.equal wide Color.cyan && Color.equal outside Color.black -> ()
   | _ -> failwith "scaled circle did not transform into an ellipse");
  Canvas.render transformed Scene.[
    clear Color.black;
    circle ~at:(8, 8) ~radius:5 ~fill:Color.white ();
  ];
  if not
       (Array.exists
          (fun color -> color.Color.r > 0 && color.r < 255)
          (Canvas.pixels transformed))
  then failwith "filled 2D primitive produced only binary edge coverage";
  Canvas.destroy transformed;
  let depth_canvas = Canvas.create_exn ~width:64 ~height:64 in
  let triangle_mesh z =
    Mesh.create_exn
      [ Vec3.create (-1.5) (-1.5) z;
        Vec3.create 1.5 (-1.5) z;
        Vec3.create 0. 1.5 z ]
  in
  let camera =
    Camera.perspective ~at:(Vec3.create 0. 0. 5.) ~target:Vec3.zero ()
  in
  let scene3 =
    Scene3.create
      [ Scene3.mesh ~cull:Scene3.Cull_none
          ~material:(Material.unlit Color.red) (triangle_mesh 1.);
        Scene3.mesh ~cull:Scene3.Cull_none
          ~material:(Material.unlit Color.blue) (triangle_mesh 0.);
      ]
  in
  Canvas.render depth_canvas Scene.[
    clear Color.black;
    view3d ~camera scene3;
  ];
  (match Canvas.pixel depth_canvas ~x:32 ~y:32 with
   | Some color when Color.equal color Color.red -> ()
   | Some color ->
       failwith
         ("3D depth buffer did not preserve the nearer triangle: "
          ^ Color.to_string color)
   | None -> failwith "3D depth test sampled outside its canvas");
  let blend_depth =
    Scene3.depth_state ~comparison:Scene3.Always ~write:false ()
  in
  Canvas.render depth_canvas Scene.[
    clear Color.black;
    view3d ~camera
      (Scene3.create [
         Scene3.mesh ~cull:Scene3.Cull_none
           ~material:(Material.unlit (Color.rgb 10 20 30))
           (triangle_mesh 0.);
         Scene3.with_depth blend_depth [
           Scene3.with_blend Scene3.Add [
             Scene3.mesh ~cull:Scene3.Cull_none
               ~material:(Material.unlit (Color.rgba 100 0 0 128))
               (triangle_mesh 0.);
           ];
         ];
       ]);
  ];
  (match Canvas.pixel depth_canvas ~x:32 ~y:32 with
   | Some { Color.r = 60; g = 20; b = 30; _ } -> ()
   | Some color ->
       failwith
         ("Scene3 additive blending produced " ^ Color.to_string color)
   | None -> failwith "Scene3 blend test sampled outside its canvas");
  let checker =
    Texture.init ~width:64 ~height:64 (fun ~x ~y ->
      if (x + y) mod 2 = 0 then Color.white else Color.black)
    |> Texture.generate_mipmaps
  in
  Canvas.render depth_canvas Scene.[
    clear Color.black;
    view3d ~camera
      (Scene3.create [
         Scene3.plane ~cull:Scene3.Cull_none
           ~material:(Material.unlit Color.white)
           ~texture:(Scene3.textured ~filter:Texture.Trilinear checker)
           ~width:0.2 ~height:0.2 ();
       ]);
  ];
  (match Canvas.pixel depth_canvas ~x:32 ~y:32 with
   | Some { Color.r; g; b; _ }
     when r >= 120 && r <= 136 && g = r && b = r -> ()
   | Some color ->
       failwith
         ("automatic 3D mip LOD did not minify to gray: "
          ^ Color.to_string color)
   | None -> failwith "3D mip test sampled outside its canvas");
  let no_depth_write =
    Scene3.depth_state ~comparison:Scene3.Always ~write:false ()
  in
  let depth_override_scene =
    Scene3.create [
      Scene3.with_depth no_depth_write [
        Scene3.mesh ~cull:Scene3.Cull_none
          ~material:(Material.unlit Color.red) (triangle_mesh 1.);
      ];
      Scene3.mesh ~cull:Scene3.Cull_none
        ~material:(Material.unlit Color.blue) (triangle_mesh 0.);
    ]
  in
  let depth_override =
    Framebuffer3.render ~width:64 ~height:64 ~camera depth_override_scene
  in
  (match Framebuffer3.color_pixel depth_override ~x:32 ~y:32 with
   | Some color when Color.equal color Color.blue -> ()
   | _ ->
       failwith
         "disabled depth writes prevented a later farther surface from drawing");
  let fog_target =
    Framebuffer3.render ~width:64 ~height:64 ~camera
      (Scene3.create
         ~fog:(Fog3.linear ~color:Color.magenta ~start:0. ~end_:1.)
         [
           Scene3.mesh ~cull:Scene3.Cull_none
             ~material:(Material.unlit Color.red) (triangle_mesh 0.);
         ])
  in
  (match Framebuffer3.color_pixel fog_target ~x:32 ~y:32 with
   | Some color when Color.equal color Color.magenta -> ()
   | _ -> failwith "scene-wide per-fragment fog was not applied");
  let stencil_write =
    Scene3.stencil_state ~reference:1 ~write_mask:0xff
      ~on_pass:Scene3.Replace ()
  and stencil_test =
    Scene3.stencil_state ~comparison:Scene3.Equal ~reference:1
      ~write_mask:0 ()
  in
  let stencil_scene =
    Scene3.create ~ambient:Color.black [
      Scene3.with_depth no_depth_write [
        Scene3.with_stencil stencil_write [
          Scene3.mesh ~cull:Scene3.Cull_none
            ~material:(Material.unlit Color.transparent)
            (triangle_mesh 1.);
        ];
      ];
      Scene3.with_stencil stencil_test [
        Scene3.plane ~cull:Scene3.Cull_none
          ~material:(Material.unlit Color.green)
          ~width:4. ~height:4. ();
      ];
    ]
  in
  let stencil_target =
    Framebuffer3.render ~width:64 ~height:64 ~camera stencil_scene
  in
  (match
     Framebuffer3.color_pixel stencil_target ~x:32 ~y:32,
     Framebuffer3.color_pixel stencil_target ~x:15 ~y:32,
     Framebuffer3.stencil stencil_target ~x:32 ~y:32,
     Framebuffer3.stencil stencil_target ~x:15 ~y:32,
     Framebuffer3.depth stencil_target ~x:32 ~y:32,
     Framebuffer3.depth stencil_target ~x:2 ~y:2
   with
   | Some inside, Some outside, Some 1, Some 0,
     Some inside_depth, Some outside_depth
     when Color.equal inside Color.green
          && Color.equal outside Color.transparent
          && inside_depth < 1. && outside_depth = 1. -> ()
   | _ ->
       failwith
         "offscreen color/depth/stencil attachments did not preserve masking");
  let stencil_target_again =
    Framebuffer3.render ~width:64 ~height:64 ~camera stencil_scene
  in
  if Framebuffer3.depths stencil_target <> Framebuffer3.depths stencil_target_again
     || Framebuffer3.stencils stencil_target
        <> Framebuffer3.stencils stencil_target_again
     || Texture.pixels (Framebuffer3.color stencil_target)
        <> Texture.pixels (Framebuffer3.color stencil_target_again)
  then failwith "offscreen 3D attachments were not deterministic";
  let stencil_canvas =
    match Framebuffer3.to_canvas stencil_target with
    | Ok canvas -> canvas
    | Error message -> failwith message
  in
  (match Canvas.pixel stencil_canvas ~x:32 ~y:32 with
   | Some color when Color.equal color Color.green -> ()
   | _ -> failwith "Framebuffer3 color attachment did not compose as a Canvas");
  Canvas.destroy stencil_canvas;
  let post_source =
    Framebuffer3.render ~width:64 ~height:64 ~camera
      (Scene3.create [
         Scene3.plane ~cull:Scene3.Cull_none
           ~material:(Material.unlit Color.red)
           ~width:4. ~height:4. ();
       ])
  in
  let invert_shader =
    Shader3.create ~vertex:Shader3.default_vertex
      ~fragment:(fun (input : Shader3.fragment_input) ->
        let red, green, blue, alpha = Color.to_floats input.color in
        Shader3.output
          (Color.of_floats (1. -. red) (1. -. green) (1. -. blue) alpha))
      ()
  in
  let postprocessed =
    Framebuffer3.render ~width:64 ~height:64 ~camera
      (Scene3.create [
         Scene3.plane ~cull:Scene3.Cull_none ~shader:invert_shader
           ~texture:(Scene3.textured (Framebuffer3.color post_source))
           ~material:(Material.unlit Color.white)
           ~width:4. ~height:4. ();
       ])
  in
  (match Framebuffer3.color_pixel postprocessed ~x:32 ~y:32 with
   | Some color when Color.equal color Color.cyan -> ()
   | _ ->
       failwith
         "Framebuffer3 color attachment was not usable for post-processing");
  let shadow_light =
    Light.directional ~diffuse:Color.white ~ambient:Color.black
      ~specular:Color.black
      ~direction:(Vec3.create 0. 0. (-1.)) ()
  and shadow_camera =
    Camera.orthographic ~near:0.1 ~far:10. ~height:4.
      ~at:(Vec3.create 0. 0. 5.) ~target:Vec3.zero ()
  in
  let receiver =
    Scene3.plane ~cull:Scene3.Cull_none
      ~material:(Material.unlit Color.white)
      ~width:4. ~height:4. ()
  and occluder =
    Scene3.translate (Vec3.create 0. 0. 1.) [
      Scene3.plane ~cull:Scene3.Cull_none
        ~material:(Material.unlit Color.white)
        ~width:1. ~height:1. ();
    ]
  in
  let shadow_depth =
    Framebuffer3.render ~width:64 ~height:64 ~camera:shadow_camera
      (Scene3.create [receiver; occluder])
  in
  let shadow =
    Framebuffer3.shadow ~filter:Shadow3.Hard
      ~bias:0.0001 ~normal_bias:0.
      ~light:shadow_light ~camera:shadow_camera shadow_depth
  in
  let shadowed_receiver =
    Framebuffer3.render ~width:64 ~height:64 ~camera
      (Scene3.create ~ambient:Color.black
         ~lights:[shadow_light] ~shadows:[shadow] [
         Scene3.plane ~cull:Scene3.Cull_none
           ~material:
             (Material.create ~diffuse:Color.white ~ambient:Color.black
                ~specular:Color.black ())
           ~width:4. ~height:4. ();
       ])
  in
  (match
     Framebuffer3.color_pixel shadowed_receiver ~x:32 ~y:32,
     Framebuffer3.color_pixel shadowed_receiver ~x:16 ~y:32
   with
   | Some shadowed, Some lit
     when shadowed.r < 5 && shadowed.g < 5 && shadowed.b < 5
          && lit.r > 245 && lit.g > 245 && lit.b > 245 -> ()
   | _ -> failwith "captured shadow map did not shade its receiver");
  let clipping_camera =
    Camera.perspective ~near:1. ~far:10.
      ~at:Vec3.zero ~target:(Vec3.create 0. 0. (-1.)) ()
  in
  let crossing =
    Mesh.create_exn
      [ Vec3.create (-1.) (-1.) (-2.);
        Vec3.create 1. (-1.) (-2.);
        Vec3.create 0. 1. 0.5 ]
  in
  Canvas.render depth_canvas Scene.[
    clear Color.black;
    view3d ~camera:clipping_camera
      (Scene3.create [
         Scene3.mesh ~cull:Scene3.Cull_none
           ~material:(Material.unlit Color.green) crossing;
       ]);
  ];
  (match Canvas.pixel depth_canvas ~x:32 ~y:52 with
   | Some color when Color.equal color Color.green -> ()
   | _ -> failwith "3D triangle crossing the near plane was not clipped");
  let checker =
    Texture.create_exn ~width:2 ~height:2
      [Color.red; Color.green; Color.blue; Color.yellow]
  in
  let textured_plane =
    Scene3.plane
      ~material:(Material.unlit Color.white)
      ~texture:(Scene3.textured ~filter:Texture.Nearest checker)
      ~width:2. ~height:2. ()
  in
  Canvas.render depth_canvas Scene.[
    clear Color.black;
    view3d
      ~camera:(Camera.perspective
        ~at:(Vec3.create 0. 0. 3.) ~target:Vec3.zero ())
      (Scene3.create [textured_plane]);
  ];
  (match
     Canvas.pixel depth_canvas ~x:22 ~y:22,
     Canvas.pixel depth_canvas ~x:42 ~y:42
   with
   | Some upper_left, Some lower_right
     when Color.equal upper_left Color.red
          && Color.equal lower_right Color.yellow -> ()
   | _ ->
       failwith
         "3D mesh texture coordinates were not sampled in perspective");
  let black_texture =
    Texture.create_exn ~width:1 ~height:1 [Color.black]
    |> Scene3.textured ~filter:Texture.Nearest
  in
  let specular_material =
    Material.create ~diffuse:Color.black ~ambient:Color.black
      ~specular:Color.white ~shininess:32. ()
  and specular_light =
    Light.directional ~diffuse:Color.black ~ambient:Color.black
      ~specular:Color.white
      ~direction:(Vec3.create 0. 0. (-1.)) ()
  in
  let render_specular separate_specular =
    Canvas.render depth_canvas Scene.[
      clear Color.black;
      view3d ~camera
        (Scene3.create ~ambient:Color.black ~lights:[specular_light]
           ~separate_specular [
           Scene3.mesh ~cull:Scene3.Cull_none
             ~material:specular_material ~texture:black_texture
             (triangle_mesh 0.);
         ]);
    ];
    match Canvas.pixel depth_canvas ~x:32 ~y:32 with
    | Some color -> color
    | None -> failwith "separate-specular sample was outside its canvas"
  in
  let combined = render_specular false
  and separate = render_specular true in
  if combined.r > 2 || combined.g > 2 || combined.b > 2
     || separate.r < 100 || separate.g < 100 || separate.b < 100
  then
    failwith
      ("separate specular did not bypass texture modulation: "
       ^ Color.to_string combined ^ " / " ^ Color.to_string separate);
  let transparent_triangle color z =
    Scene3.mesh ~cull:Scene3.Cull_none
      ~material:(Material.unlit color) (triangle_mesh z)
  in
  let red = transparent_triangle (Color.rgba 255 0 0 128) 1.
  and blue = transparent_triangle (Color.rgba 0 0 255 128) 0. in
  let render_order nodes =
    Canvas.render depth_canvas Scene.[
      clear Color.black;
      view3d ~camera (Scene3.create nodes);
    ];
    match Canvas.pixel depth_canvas ~x:32 ~y:32 with
    | Some color -> color
    | None -> failwith "transparent 3D sample was outside the canvas"
  in
  let front_first = render_order [red; blue]
  and back_first = render_order [blue; red] in
  if not (Color.equal front_first back_first)
     || front_first.r < 115 || front_first.r > 140
     || front_first.b < 50 || front_first.b > 75
  then
    failwith
      ("transparent 3D surfaces were not sorted back-to-front: "
       ^ Color.to_string front_first ^ " / " ^ Color.to_string back_first);
  Canvas.render depth_canvas Scene.[
    clear Color.black;
    view3d ~camera
      (Scene3.create ~samples:4 [
         Scene3.mesh ~cull:Scene3.Cull_none
           ~material:(Material.unlit Color.red) (triangle_mesh 1.);
       ]);
  ];
  if not
       (Array.exists
          (fun color -> color.Color.r > 0 && color.r < 255)
          (Canvas.pixels depth_canvas))
  then failwith "3D multisample antialiasing produced only binary coverage";
  let split_shader =
    Shader3.create ~varying_count:1
      ~vertex:(fun (input : Shader3.vertex_input) ->
        let output = Shader3.default_vertex input in
        { output with varyings = [input.position.x] })
      ~fragment:(fun (input : Shader3.fragment_input) ->
        match input.varyings with
        | [horizontal] ->
            Shader3.output
              (if horizontal < 0. then Color.red else Color.blue)
        | _ -> failwith "shader varying count changed during rasterization")
      ()
  in
  Canvas.render depth_canvas Scene.[
    clear Color.black;
    view3d ~camera
      (Scene3.create [
         Scene3.mesh ~cull:Scene3.Cull_none ~shader:split_shader
           ~material:(Material.unlit Color.white) (triangle_mesh 1.);
       ]);
  ];
  (match
     Canvas.pixel depth_canvas ~x:25 ~y:36,
     Canvas.pixel depth_canvas ~x:39 ~y:36
   with
   | Some left, Some right
     when Color.equal left Color.red && Color.equal right Color.blue -> ()
   | _ ->
       failwith
         "programmable vertex varyings or fragment colors were not rendered");
  let discard_shader =
    Shader3.create
      ~vertex:Shader3.default_vertex
      ~fragment:(fun _ -> Shader3.discard)
      ()
  in
  Canvas.render depth_canvas Scene.[
    clear Color.black;
    view3d ~camera
      (Scene3.create [
         Scene3.mesh ~cull:Scene3.Cull_none ~shader:discard_shader
           ~material:(Material.unlit Color.red) (triangle_mesh 1.);
         Scene3.mesh ~cull:Scene3.Cull_none
           ~material:(Material.unlit Color.blue) (triangle_mesh 0.);
       ]);
  ];
  (match Canvas.pixel depth_canvas ~x:32 ~y:32 with
   | Some color when Color.equal color Color.blue -> ()
   | _ -> failwith "discarded shader fragments still updated color or depth");
  let far_depth_shader =
    Shader3.create
      ~vertex:Shader3.default_vertex
      ~fragment:(fun input -> Shader3.output ~depth:0.999 input.color)
      ()
  in
  Canvas.render depth_canvas Scene.[
    clear Color.black;
    view3d ~camera
      (Scene3.create [
         Scene3.mesh ~cull:Scene3.Cull_none ~shader:far_depth_shader
           ~material:(Material.unlit Color.red) (triangle_mesh 1.);
         Scene3.mesh ~cull:Scene3.Cull_none
           ~material:(Material.unlit Color.blue) (triangle_mesh 0.);
       ]);
  ];
  (match Canvas.pixel depth_canvas ~x:32 ~y:32 with
   | Some color when Color.equal color Color.blue -> ()
   | _ -> failwith "fragment shader depth output did not affect depth testing");
  let geometry_shader =
    Shader3.create
      ~vertex:Shader3.default_vertex
      ~geometry:(fun (input : Shader3.geometry_input) ->
        match input.primitive with
        | Shader3.Point center ->
            let x, y, z, w = center.clip_position in
            let at dx dy =
              {
                center with
                clip_position = x +. (dx *. w), y +. (dy *. w), z, w;
              }
            in
            [
              Shader3.Triangle
                (at (-0.35) (-0.35), at 0.35 (-0.35), at 0. 0.35);
            ]
        | _ -> [])
      ~fragment:(fun _ -> Shader3.output Color.green)
      ()
  in
  let point_mesh = Mesh.create_exn ~mode:Mesh.Points [Vec3.zero] in
  Canvas.render depth_canvas Scene.[
    clear Color.black;
    view3d ~camera
      (Scene3.create [
         Scene3.mesh ~cull:Scene3.Cull_none ~shader:geometry_shader
           ~material:(Material.unlit Color.white) point_mesh;
       ]);
  ];
  let geometry_pixels =
    Canvas.pixels depth_canvas
    |> Array.fold_left
         (fun count color ->
           if Color.equal color Color.green then count + 1 else count)
         0
  in
  (match Canvas.pixel depth_canvas ~x:32 ~y:32 with
   | Some center
     when Color.equal center Color.green && geometry_pixels > 100 -> ()
   | _ ->
       failwith
         "geometry shader did not expand a point into a rasterized triangle");
  Canvas.render depth_canvas Scene.[
    clear Color.black;
    view3d ~camera
      (Scene3.create ~samples:9 [
         Scene3.with_raster (Scene3.raster_state ~point_size:7. ()) [
           Scene3.mesh ~material:(Material.unlit Color.white) point_mesh;
         ];
       ]);
  ];
  let point_pixels = Canvas.pixels depth_canvas in
  let point_coverage =
    point_pixels
    |> Array.fold_left
         (fun coverage color ->
           coverage +. (float_of_int color.Color.r /. 255.))
         0.
  in
  let point_has_partial =
    Array.exists
      (fun color -> color.Color.r > 0 && color.r < 255)
      point_pixels
  in
  if abs_float (point_coverage -. 49.) > 1. || not point_has_partial then
    failwith
      (Printf.sprintf
         "Scene3 point size or antialiased coverage changed: %.3f/%b"
         point_coverage point_has_partial);
  let line_mesh =
    Mesh.create_exn ~mode:Mesh.Lines
      [Vec3.create (-1.) 0. 0.; Vec3.create 1. 0. 0.]
  in
  Canvas.render depth_canvas Scene.[
    clear Color.black;
    view3d ~camera
      (Scene3.create ~samples:9 [
         Scene3.with_raster (Scene3.raster_state ~line_width:5. ()) [
           Scene3.mesh ~material:(Material.unlit Color.white) line_mesh;
         ];
       ]);
  ];
  let covered_rows =
    List.init 64 Fun.id
    |> List.fold_left
         (fun coverage y ->
           match Canvas.pixel depth_canvas ~x:32 ~y with
           | Some color ->
               coverage +. (float_of_int color.Color.r /. 255.)
           | None -> coverage)
         0.
  in
  if covered_rows < 4.5 then
    failwith "Scene3 line width did not widen rasterized line coverage";
  Canvas.destroy depth_canvas;
  let filename = Filename.temp_file "prismel-canvas-" ".png" in
  Fun.protect
    ~finally:(fun () -> if Sys.file_exists filename then Sys.remove filename)
    (fun () ->
      match Canvas.save_png canvas filename with
      | Ok () ->
          if (Unix.stat filename).st_size = 0 then
            failwith "canvas PNG was empty";
          let assets = Assets.create ~watch:true () in
          let first = Assets.image_exn assets filename in
          let second = Assets.image_exn assets filename in
          if first != second || Assets.image_count assets <> 1 then
            failwith "asset cache duplicated an image resource";
          let replacement = Canvas.create_exn ~width:4 ~height:4 in
          Canvas.render replacement Scene.[clear Color.blue];
          (match Canvas.save_png replacement filename with
           | Ok () -> ()
           | Error message -> failwith message);
          Canvas.destroy replacement;
          let now = Unix.gettimeofday () +. 2. in
          Unix.utimes filename now now;
          (match Assets.refresh assets with
           | Ok [_] -> ()
           | Ok _ -> failwith "hot asset refresh missed a changed image"
           | Error errors -> failwith (String.concat "; " errors));
          if Assets.image_exn assets filename != first
             || Image.get_size first <> (4, 4)
          then failwith "hot image reload did not preserve borrowed identity";
          (match Assets.preload assets
             [Assets.Image_file filename; Assets.Image_file "missing.png"] with
           | Error [_] -> ()
           | _ -> failwith "asset preload did not aggregate errors");
          Assets.destroy assets;
          let parallel_assets = Assets.create () in
          (match Assets.preload_parallel parallel_assets
             [Assets.Image_file filename; Assets.Image_file "missing.png"] with
           | Error [_] when Assets.image_count parallel_assets = 1 -> ()
           | _ ->
               failwith
                 "parallel preload did not join decoding or aggregate errors");
          Assets.destroy parallel_assets
      | Error message -> failwith message);
  let wav = Filename.temp_file "prismel-audio-" ".wav" in
  Fun.protect
    ~finally:(fun () -> if Sys.file_exists wav then Sys.remove wav)
    (fun () ->
      write_silent_wav wav;
      let assets = Assets.create () in
      let sample = Assets.sample_exn assets wav in
      let same_sample = Assets.sample_exn assets wav in
      if sample != same_sample || Assets.sample_count assets <> 1 then
        failwith "asset cache duplicated an audio sample";
      (match Audio.Sample.play ~volume:0. sample with
       | Ok channel -> Audio.Sample.stop channel
       | Error message -> failwith message);
      Assets.destroy assets;
      let tone =
        match Audio.Sample.synth ~sample_rate:8_000 ~volume:0.
            ~waveform:Audio.Sample.Sine ~frequency:440. ~duration:0.01 () with
        | Ok sample -> sample
        | Error message -> failwith message
      in
      Audio.Sample.destroy tone);
  (match find_test_font () with
   | None -> ()
   | Some path ->
       let font =
         match Font.load path 12 with
         | Ok font -> font
         | Error (`Msg message) -> failwith message
       in
       let render () =
         match
           Font.cached_text ~wrap:120 ~align:Font.Center font
             "cached text\nstays borrowed" (Font.Blended Color.white)
         with
         | Ok image -> image
         | Error (`Msg message) -> failwith message
       in
       let first = render () in
       let second = render () in
       if first != second || Font.cache_count font <> 1 then
         failwith "font cache duplicated a rendered text texture";
       Canvas.render canvas Scene.[
         clear Color.black;
         font_text font ~at:(0, 0) ~wrap:8 ~align:Font.Center "A";
       ];
       if Font.cache_count font <> 2 then
         failwith "font cache did not distinguish offscreen renderers";
       Font.set_style font [Font.Bold];
       if Font.cache_count font <> 0 then
         failwith "font style change did not invalidate rendered text";
       let empty_image =
         match Font.render_text font "" (Font.Blended Color.white) with
         | Ok image -> image
         | Error (`Msg message) -> failwith message
       in
       Image.destroy empty_image;
       List.iter
         (fun mode ->
           match Font.render_wrapped font "" mode 24 with
           | Ok [image] -> Image.destroy image
           | Ok images ->
               List.iter Image.destroy images;
               failwith "empty wrapped text returned an unexpected image count"
           | Error (`Msg message) -> failwith message)
         [ Font.Solid Color.white;
           Font.Shaded (Color.white, Color.black);
           Font.Blended Color.white ];
       for index = 0 to 269 do
         match
           Font.Private.cached_text font (string_of_int index)
             (Font.Blended Color.white)
         with
         | Ok _ -> ()
         | Error (`Msg message) -> failwith message
       done;
       if Font.cache_count font <> 256 then
         failwith "dynamic labels escaped the renderer-local font cache bound";
       Font.destroy font;
       (match Font.load_dpi path 12 144 96 with
        | Error _ -> ()
        | Ok font ->
            Font.destroy font;
            failwith "non-uniform DPI silently ignored an unsupported axis");
       let dpi_font =
         match Font.load_dpi path 12 144 144 with
         | Ok font -> font
         | Error (`Msg message) -> failwith message
       in
       let dpi_image =
         match Font.cached_text dpi_font "DPI" (Font.Blended Color.white) with
         | Ok image -> image
         | Error (`Msg message) -> failwith message
       in
       let logical_width, logical_height = Image.get_size dpi_image in
       let physical_width, physical_height =
         match Sdl.query_texture (Image.Private.get_texture dpi_image) with
         | Ok (_, _, dimensions) -> dimensions
         | Error (`Msg message) -> failwith message
       in
       if abs (physical_width - (2 * logical_width)) > 2
          || abs (physical_height - (2 * logical_height)) > 2
       then failwith "Font.load_dpi did not honor its explicit uniform DPI";
       Font.destroy dpi_font);
  Canvas.destroy canvas;
  Sketch.resize ~width:40 ~height:30;
  Input.reset ~mouse:(10, 10);
  push_mouse_motion 13 14;
  push_mouse_motion 20 25;
  push_mouse_button Sdl.Event.mouse_button_down 20 25;
  push_mouse_button Sdl.Event.mouse_button_up 20 25;
  push_mouse_button ~button:9 Sdl.Event.mouse_button_down 20 25;
  push_mouse_button ~button:9 Sdl.Event.mouse_button_up 20 25;
  0

let update state (frame : Frame.t) =
  if frame.dt <> 0.125
     || frame.time <> (float_of_int frame.count *. 0.125)
     || frame.fps <> 8.
  then failwith "fixed sketch clock was not deterministic";
  if frame.count = 1 then begin
    if frame.size <> (40, 30)
       || Sdl.render_get_logical_size (Low.Window.get_renderer ()) <> (40, 30)
    then failwith "window resize did not update frame and renderer together";
    let resize_count =
      List.fold_left
        (fun count -> function
          | Event.WindowResized (40, 30) -> count + 1
          | _ -> count)
        0 frame.events
    in
    if resize_count <> 1 then
      failwith "one SDL resize produced duplicate or missing public events";
    if frame.mouse <> (20, 25) || frame.mouse_delta <> (10, 15) then
      failwith "SDL mouse events did not produce logical accumulated input";
    let pointer_events =
      List.filter
        (function
          | Event.MouseMoved _
          | Event.MousePressed _
          | Event.MouseReleased _ -> true
          | _ -> false)
        frame.events
    in
    match pointer_events with
    | [ Event.MouseMoved (13, 14);
        Event.MouseMoved (20, 25);
        Event.MousePressed (Input.LeftButton, (20, 25));
        Event.MouseReleased (Input.LeftButton, (20, 25)) ] -> ()
    | _ -> failwith "SDL pointer event order or coordinates changed"
  end;
  if frame.count = 2 && frame.mouse_delta <> (0, 0) then
    failwith "mouse delta was nonzero on the quiet frame";
  state + 1

let view state (frame : Frame.t) =
  Scene.[
    clear Color.black;
    rect ~at:(2, 2) ~w:12 ~h:10 ~fill:Color.red ();
    circle ~at:frame.mouse ~radius:(4 + state) ~fill:Color.blue ();
    translate 4 4 [
      line ~from_:(0, 0) ~to_:(10, 10) ~color:Color.white ();
    ];
  ]

let () =
  if not (Sketch.is_headless ()) then
    failwith "headless smoke test was not launched with HEADLESS enabled";
  let final_state =
    Sketch.run_state
      ~max_frames:2
      ~config:{ Sketch.default_config with
        width = 32;
        height = 32;
        title = "headless smoke";
        domains = Some 2;
        clock = Sketch.Fixed 0.125;
      }
      ~init ~update ~view ()
  in
  if final_state <> 2 then
    failwith "functional headless sketch did not complete two frames";
  let make_temp_dir () =
    let path = Filename.temp_file "prismel-frames-" "" in
    Sys.remove path;
    Unix.mkdir path 0o700;
    path
  in
  let first_dir = make_temp_dir () in
  let second_dir = make_temp_dir () in
  let filenames =
    List.init 3 (fun index -> Printf.sprintf "shot-%06d.png" index)
  in
  let cleanup directory =
    List.iter
      (fun name ->
        let path = Filename.concat directory name in
        if Sys.file_exists path then Sys.remove path)
      filenames;
    if Sys.file_exists directory then Unix.rmdir directory
  in
  Fun.protect
    ~finally:(fun () -> cleanup first_dir; cleanup second_dir)
    (fun () ->
      let render directory domains =
        let visual_mesh =
          Parallel.run ~domains (fun () ->
            Mesh.sphere ~segments:24 ~rings:12 ~radius:0.85 ())
        in
        let visual_camera =
          Camera.perspective ~at:(Vec3.create 0. 0. 3.) ~target:Vec3.zero ()
        in
        Sketch.export
          ~config:{ Sketch.default_config with
            width = 16;
            height = 16;
            domains = Some domains;
          }
          ~fps:10 ~prefix:"shot" ~directory ~frames:3
          (fun frame ->
            if frame.dt <> 0.1
               || frame.time <> (float_of_int frame.count *. 0.1)
            then failwith "export did not use deterministic fixed timing";
            Scene.[
              clear Color.black;
              view3d ~camera:visual_camera
                (Scene3.create [
                   Scene3.mesh ~cull:Scene3.Cull_none
                     ~material:(Material.unlit Color.cyan) visual_mesh;
                 ]);
              square ~at:(frame.count, 2) ~size:4 ~fill:Color.white ();
              text ~at:(1, 8) ~size:6 "R";
            ])
      in
      render first_dir 1;
      render second_dir 4;
      List.iter
        (fun name ->
          let first = Filename.concat first_dir name in
          let second = Filename.concat second_dir name in
          if not (Sys.file_exists first) || (Unix.stat first).st_size = 0 then
            failwith "frame export did not create a non-empty PNG";
          if Digest.file first <> Digest.file second then
            failwith
              "one-domain and multi-domain visual exports produced different PNGs")
        filenames);
  Preview.show Scene.[
    clear Color.black;
    circle ~at:(8, 8) ~radius:4 ~fill:Color.cyan ();
  ];
  if not (Preview.is_open ()) then
    failwith "REPL preview did not open a persistent session";
  Preview.stop ();
  if Preview.is_open () then failwith "REPL preview did not stop"
