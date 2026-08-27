open Prismel

module Loop = Prismel_runtime_next_sketch
module Orchestrator = Runtime_next_orchestrator

type fixture = Basic | Canvas_readback | Scene3 | Widget

let vertices points =
  let bytes = Bytes.make (List.length points * 16) '\000' in
  List.iteri (fun index (x, y) ->
      let offset = index * 16 in
      Bytes.set_int64_le bytes offset (Int64.bits_of_float x);
      Bytes.set_int64_le bytes (offset + 8) (Int64.bits_of_float y)) points;
  bytes

let indices values =
  let bytes = Bytes.make (List.length values * 4) '\000' in
  List.iteri (fun index value ->
      Bytes.set_int32_le bytes (index * 4) (Int32.of_int value)) values;
  bytes

let draw fixture extent =
  let edge = float extent in
  let points, index_values =
    match fixture with
    | Basic -> [ 0., 0.; edge, 0.; 0., edge ], [ 0; 1; 2 ]
    | Canvas_readback ->
        [ 0., 0.; edge /. 2., 0.; 0., edge /. 2. ], [ 0; 1; 2 ]
    | Scene3 ->
        [ edge, 0.; edge, edge; 0., edge ], [ 0; 1; 2 ]
    | Widget ->
        [ 0., 0.; edge, 0.; edge, edge; 0., edge ],
        [ 0; 1; 2; 0; 2; 3 ]
  in
  let mesh : Scene_execution.mesh =
    { key = (match fixture with Basic -> "basic" | Canvas_readback -> "canvas"
        | Scene3 -> "scene3" | Widget -> "widget");
      vertices = vertices points; vertex_count = List.length points;
      indices = indices index_values; index_count = List.length index_values }
  in
  { Scene_execution.mesh;
    state = { viewport = (0, 0, extent, extent);
      scissor = (0, 0, extent, extent);
      cull = Ogpu.Render_pass.Cull_none;
      depth_compare = Ogpu.Render_pass.Always; depth_write = false;
      depth_load = Ogpu.Render_pass.Clear; depth_clear = 1.;
      transform_uniforms = None; stencil_state = None;
      stencil_load = Ogpu.Render_pass.Clear; stencil_clear = 0 } }

let scene = function
  | Basic -> [ Scene.clear Color.black;
               Scene.triangle (0, 0) (4, 0) (0, 4) ~fill:Color.white () ]
  | Canvas_readback -> [ Scene.clear Color.transparent;
                         Scene.rect ~at:(0, 0) ~w:2 ~h:2 ~fill:Color.white () ]
  | Scene3 -> [ Scene.clear Color.black ]
  | Widget -> [ Scene.clear Color.black;
                Scene.rect ~at:(0, 0) ~w:4 ~h:4 ~fill:Color.dark_gray ();
                Scene.text ~at:(1, 1) ~color:Color.white "OK" ]

let digest bytes = Digest.to_hex (Digest.bytes bytes)

let run fixture extent =
  let checkpoints = Hashtbl.create 4 and stop_count = ref 0 in
  let configuration : Loop.configuration =
    { target = Orchestrator.Headless; logical_width = extent;
      logical_height = extent; drawable_width = extent;
      drawable_height = extent; frames = 600; dt = 1. /. 60.;
      web_configuration = None }
  in
  let result =
    match Loop.run_state ~configuration ~init:(fun _ -> 0)
        ~update:(fun model _ -> model + 1)
        ~view:(fun _ _ -> scene fixture)
        ~prepare:(fun _ _ -> Ok [ draw fixture extent ])
        ~after_frame:(fun frame pixels ->
          if List.mem frame.Frame.count [ 1; 2; 60; 600 ] then
            Hashtbl.add checkpoints frame.count (digest pixels))
        ~on_stop:(fun _ -> incr stop_count) () with
    | Ok result -> result
    | Error error -> failwith (Ogpu.Error.to_string error)
  in
  if result.model <> 600 || !stop_count <> 1 then
    failwith "parity fixture lifecycle/cleanup count drift";
  let hashes = List.map (Hashtbl.find checkpoints) [ 1; 2; 60; 600 ] in
  begin match hashes with
  | first :: rest when List.for_all (( = ) first) rest
                     && first = digest result.pixels -> first
  | _ -> failwith "parity frame checkpoint hash drift"
  end

let test () =
  let hashes =
    [ Basic, run Basic 4; Canvas_readback, run Canvas_readback 4;
      Scene3, run Scene3 4; Widget, run Widget 4 ]
  in
  let expected =
    [ Basic, "183be222f2a9499335f80e49bab17f24";
      Canvas_readback, "6669327647bf796bcc136e62a62f7c95";
      Scene3, "52462b7485ced3177c5f7bf2fda8a7ae";
      Widget, "c28fb438cfaf0381adc6b8dddec9d6cf" ]
  in
  if hashes <> expected then failwith "frozen representative pixel hashes drift";
  let resized = run Basic 8 in
  if resized <> "a07e462221d8a87c5d83ad9a18411a44" then
    failwith "frozen resized framebuffer hash drift";
  print_endline
    "runtime-next parity: Basic/Canvas/Scene3/PXUI frames1/2/60/600+resize passed"

let () =
  match Sys.getenv_opt "PRISMEL_TEST_RUNTIME_NEXT_PARITY" with
  | Some "1" -> test ()
  | _ -> ()
