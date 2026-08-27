open Prismel

module Loop = Prismel_runtime_next_sketch

type lifecycle = {
  refresh : Frame.t -> (unit, string list) result;
  before_target_destroy : unit -> unit;
}

let run_assets_state ~configuration ?root ?(watch=false) ~resources
    ~init ~update ~view ~prepare ?regions ?after_frame ?on_stop () =
  let assets = Assets.create ?root ~watch () in
  let stopped = ref false in
  let destroy_owned () =
    if not !stopped then begin
      stopped := true;
      List.iter (fun lifecycle -> lifecycle.before_target_destroy ()) resources;
      Assets.destroy assets
    end
  in
  let stop model =
    if not !stopped then begin
      stopped := true;
      Option.iter (fun callback -> callback assets model) on_stop;
      List.iter (fun lifecycle -> lifecycle.before_target_destroy ()) resources;
      Assets.destroy assets
    end
  in
  try
    let result = Loop.run_state ~configuration
      ~init:(fun frame -> init assets frame)
      ~update:(fun model frame ->
        List.iter (fun lifecycle ->
          match lifecycle.refresh frame with
          | Ok () -> ()
          | Error messages ->
              List.iter (fun message ->
                Printf.eprintf "Prismel runtime-next resource warning: %s\n%!"
                  message) messages) resources;
        begin
          match Assets.refresh assets with
          | Ok _ -> ()
          | Error messages ->
              List.iter (fun message ->
                Printf.eprintf "Prismel asset reload warning: %s\n%!" message)
                messages
        end;
        update assets model frame)
      ~view:(fun model frame -> view assets model frame)
      ~prepare ?regions ?after_frame ~on_stop:stop () in
    destroy_owned ();
    result
  with error ->
    destroy_owned ();
    raise error

type image_snapshot = { identity : int; mutable generation : int64;
  mutable rgba : bytes }
type font_cache = (int * string, bytes) Hashtbl.t

let test () =
  let image = { identity = 7; generation = 1L;
    rgba = Bytes.of_string "first" } in
  let font_cache = Hashtbl.create 4 in
  let canvas_live = ref true and audio_live = ref true
  and resource_destroy_count = ref 0 and owner_stop_count = ref 0
  and failed_generation = ref 0L in
  let lifecycle =
    { refresh = (fun frame ->
        begin match frame.Frame.count with
        | 1 ->
            image.generation <- Int64.succ image.generation;
            image.rgba <- Bytes.of_string "reloaded"
        | 2 -> failed_generation := image.generation
        | _ -> ()
        end;
        let density = if frame.count < 60 then 1 else 2 in
        let text = if frame.count = 2 then "" else "AV" in
        if text <> "" then Hashtbl.replace font_cache (density, text)
            (Bytes.of_string text);
        Ok ());
      before_target_destroy = (fun () ->
        if not !canvas_live || not !audio_live then
          failwith "resource destroyed more than once";
        canvas_live := false;
        audio_live := false;
        incr resource_destroy_count) }
  in
  let configuration : Loop.configuration =
    { target = Runtime_next_orchestrator.Headless; logical_width = 4;
      logical_height = 4; drawable_width = 4; drawable_height = 4;
      frames = 600; dt = 1. /. 60.; web_configuration = None }
  in
  let vertices = Bytes.make 48 '\000' in
  let set index x y =
    Bytes.set_int64_le vertices (index*16) (Int64.bits_of_float x);
    Bytes.set_int64_le vertices (index*16+8) (Int64.bits_of_float y) in
  set 0 0. 0.;set 1 4. 0.;set 2 0. 4.;
  let indices=Bytes.make 12 '\000'in Bytes.set_int32_le indices 4 1l;
  Bytes.set_int32_le indices 8 2l;
  let draw:Scene_execution.draw={mesh={key="resources";vertices;
    vertex_count=3;indices;index_count=3};state={viewport=(0,0,4,4);
    scissor=(0,0,4,4);cull=Ogpu.Render_pass.Cull_none;
    depth_compare=Ogpu.Render_pass.Always;depth_write=false;
    depth_load=Ogpu.Render_pass.Clear;depth_clear=1.;transform_uniforms=None;
    stencil_state=None;stencil_load=Ogpu.Render_pass.Clear;stencil_clear=0}}in
  let result = run_assets_state ~configuration ~watch:false
      ~resources:[lifecycle] ~init:(fun assets _ -> assets,0)
      ~update:(fun assets (borrowed,count) frame ->
        if assets != borrowed then failwith "borrowed Assets identity changed";
        if frame.count = 2 && image.generation <> !failed_generation then
          failwith "failed reload replaced retained Image generation";
        borrowed,count+1)
      ~view:(fun _ _ _ -> [Scene.clear Color.black])
      ~prepare:(fun _ _ -> Ok[draw])
      ~on_stop:(fun assets (borrowed,count) ->
        if assets != borrowed || count<>600 then failwith"borrowed Assets lifecycle";
        incr owner_stop_count)()in
  begin match result with Ok value when snd value.model=600->()|Ok _->
    failwith"resource loop model"|Error error->failwith(Ogpu.Error.to_string error)end;
  if image.identity <> 7 || image.generation <> 2L
     || image.rgba <> Bytes.of_string "reloaded"
     || Hashtbl.length font_cache <> 2 || !resource_destroy_count <> 1
     || !owner_stop_count <> 1 || !canvas_live || !audio_live then
    failwith "runtime-next resource snapshot/teardown contract";
  print_endline
    "runtime-next resources: image/font/canvas/audio/assets frame600 passed"

let () =
  match Sys.getenv_opt "PRISMEL_TEST_RUNTIME_NEXT_RESOURCES" with
  | Some "1" -> test ()
  | _ -> ()
