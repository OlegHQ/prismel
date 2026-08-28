open Prismel

module Orchestrator = Runtime_next_orchestrator

type configuration = {
  target : Orchestrator.target;
  logical_width : int;
  logical_height : int;
  drawable_width : int;
  drawable_height : int;
  frames : int;
  dt : float;
}

type 'model result = {
  model : 'model;
  last_frame : Frame.t;
  pixels : bytes;
}

let frame ~configuration ~count =
  let width = configuration.logical_width
  and height = configuration.logical_height
  and drawable_width = configuration.drawable_width
  and drawable_height = configuration.drawable_height in
  {
    Frame.width;
    height;
    size = (width, height);
    drawable_width;
    drawable_height;
    drawable_size = (drawable_width, drawable_height);
    pixel_scale =
      (float drawable_width /. float width, float drawable_height /. float height);
    time = float count *. configuration.dt;
    dt = configuration.dt;
    fps = 1. /. configuration.dt;
    count;
    mouse = (0, 0);
    mouse_delta = (0, 0);
    keys = [];
    mouse_buttons = [];
    events = [];
  }

let validate configuration =
  if configuration.frames <= 0 then Error "frames must be positive"
  else if not (Float.is_finite configuration.dt) || configuration.dt <= 0. then
    Error "dt must be finite and positive"
  else if configuration.logical_width <= 0 || configuration.logical_height <= 0
       || configuration.drawable_width <= 0
       || configuration.drawable_height <= 0 then
    Error "dimensions must be positive"
  else Ok ()

let run_state ~configuration ~init ~update ~view ~prepare ?regions:_ ?after_frame
    ?on_stop () =
  match validate configuration with
  | Error message ->
      Error
        (Ogpu.Error.make "Prismel_runtime_next_sketch.run_state"
           Ogpu.Error.Invalid_argument message)
  | Ok () ->
      let runtime_configuration : Orchestrator.configuration =
        {
          target = configuration.target;
          logical_width = configuration.logical_width;
          logical_height = configuration.logical_height;
          drawable_width = configuration.drawable_width;
          drawable_height = configuration.drawable_height;
        }
      in
      match Orchestrator.create runtime_configuration with
      | Error _ as error -> error
      | Ok runtime ->
          let initial_frame = frame ~configuration ~count:0 in
          let model = ref None
          and last_frame = ref initial_frame in
          let run () =
            model := Some (init initial_frame);
            let rec loop count =
              if count > configuration.frames then Ok ()
              else
                let current_frame = frame ~configuration ~count in
                let current_model = Option.get !model in
                model := Some (update current_model current_frame);
                last_frame := current_frame;
                let scene = view (Option.get !model) current_frame in
                match prepare current_frame scene with
                | Error _ as error -> error
                | Ok draws ->
                    match Orchestrator.render runtime draws with
                    | Error _ as error -> error
                    | Ok _ ->
                        begin
                          match after_frame with
                          | None -> loop (count + 1)
                          | Some callback ->
                              match Orchestrator.capture runtime
                                  ~bytes_per_row:
                                    (configuration.drawable_width * 4) with
                              | Error _ as error -> error
                              | Ok pixels ->
                                  callback current_frame pixels;
                                  loop (count + 1)
                        end
            in
            match loop 1 with
            | Error _ as error -> error
            | Ok () ->
                Result.map
                  (fun pixels ->
                    { model = Option.get !model; last_frame = !last_frame;
                      pixels })
                  (Orchestrator.capture runtime
                     ~bytes_per_row:(configuration.drawable_width * 4))
          in
          Fun.protect
            ~finally:(fun () ->
              let stop_error =
                try
                  Option.iter
                    (fun stop -> Option.iter stop !model)
                    on_stop;
                  None
                with error -> Some error
              in
              ignore (Orchestrator.destroy runtime);
              Option.iter raise stop_error)
            run

let run_selected ~logical_width ~logical_height ~drawable_width
    ~drawable_height ~frames ~dt ~init ~update ~view ~prepare
    ?regions ?after_frame ?on_stop () =
  match Orchestrator.selected () with
  | Error message ->
      Error
        (Ogpu.Error.make "Prismel_runtime_next_sketch.run_selected"
           Ogpu.Error.Invalid_argument message)
  | Ok target ->
      run_state
        ~configuration:{ target; logical_width; logical_height; drawable_width;
          drawable_height; frames; dt }
        ~init ~update ~view ~prepare ?regions ?after_frame ?on_stop ()

let test () =
  let vertices = Bytes.make 48 '\000' in
  let set index x y =
    let offset = index * 16 in
    Bytes.set_int64_le vertices offset (Int64.bits_of_float x);
    Bytes.set_int64_le vertices (offset + 8) (Int64.bits_of_float y)
  in
  set 0 0. 0.; set 1 4. 0.; set 2 0. 4.;
  let indices = Bytes.make 12 '\000' in
  Bytes.set_int32_le indices 4 1l;
  Bytes.set_int32_le indices 8 2l;
  let mesh : Scene_execution.mesh =
    { key = "private-sketch"; vertices; vertex_count = 3; indices;
      index_count = 3 }
  in
  let draw : Scene_execution.draw =
    { mesh; state = { viewport = (0, 0, 4, 4); scissor = (0, 0, 4, 4);
        cull = Ogpu.Render_pass.Cull_none;
        depth_compare = Ogpu.Render_pass.Always; depth_write = false;
        depth_load = Ogpu.Render_pass.Clear; depth_clear = 1.;
        transform_uniforms = None; stencil_state = None;
        stencil_load = Ogpu.Render_pass.Clear; stencil_clear = 0 } }
  in
  let stopped = ref None in
  let configuration =
    { target = Orchestrator.Native; logical_width = 4; logical_height = 4;
      drawable_width = 4; drawable_height = 4; frames = 600;
      dt = 1. /. 60. }
  in
  let result =
    match run_state ~configuration ~init:(fun frame -> frame.count)
        ~update:(fun model frame -> model + frame.count)
        ~view:(fun _ frame -> [ Scene.clear Color.black;
                                Scene.point ~at:(frame.count mod 4, 0) () ])
        ~prepare:(fun frame _scene ->
          if frame.events <> [] || frame.mouse_delta <> (0, 0) then
            failwith "finite headless frame synthesized input";
          Ok [ draw ])
        ~on_stop:(fun model -> stopped := Some model) () with
    | Ok result -> result
    | Error error -> failwith (Ogpu.Error.to_string error)
  in
  if result.last_frame.count <> 600
     || result.last_frame.time <> 10.
     || result.last_frame.pixel_scale <> (1., 1.) then
    failwith "private Sketch frame semantics drift";
  if Bytes.get_int32_be result.pixels 0 <> 0x4080bfffl then
    failwith "private Sketch loop did not render exact packed pixels";
  if !stopped <> Some result.model then
    failwith "private Sketch cleanup did not retain final model";
  print_endline
    "private runtime-next Sketch loop: headless frame600 exact pixels/cleanup passed"

let () =
  match Sys.getenv_opt "PRISMEL_TEST_RUNTIME_NEXT_SKETCH" with
  | Some "1" -> test ()
  | _ -> ()
