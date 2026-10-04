(* Frame time with 1, 2 and 4 path-traced viewports, each over a root of its own (one slot each),
   in a real window (the tracer needs the Metal device).  The focused viewport renders every
   frame; the budget lets the others take turns.
   The wall time is vsync-bound while the GPU keeps up; the cost shows in the GPU time the tracer
   reports per published frame, so run one pane count per process with the profile on and sum it:
     PRISMEL_PATHTRACER_PROFILE=1 dune exec tools/bench_traced_panes.exe -- 300 4 2>&1 \
       | awk '/gpu_ms/ { sum += $3 } /traced panes/ { print } END { print sum / 300, "gpu ms/frame" }'
   Without a pane count it runs 1, 2 and 4.  [frames] defaults to 300. *)
open Prismel
module E = Prismel_editor.Editor3

let scene_graph name eye = Printf.sprintf {|  (graph %s :context scene
    (let* [cam (scene/camera :name "cam" :eye %s)
           all (scene/merge (ref set) cam)
           root (scene/root all :camera cam :renderer "Path traced" :width 1280 :height 720 :max_spp 100000 :bounces 16)]
      root))
|} name eye

let workspace panes =
  let eyes = [| "[0 1 8]"; "[5 2 6]"; "[-5 2 6]"; "[0 6 6]" |] in
  let source = Buffer.create 2048 in
  Buffer.add_string source {|(workspace traced_panes
  (graph g :context sop (sop/box))
  (graph set :context scene (scene/merge (scene/geometry (ref g) :name "body")))
|};
  for i = 0 to panes - 1 do Buffer.add_string source (scene_graph (Printf.sprintf "s%d" i) eyes.(i)) done;
  let view i = Printf.sprintf "(ui/viewport (ref s%d))" i in
  let layout = match panes with
    | 1 -> view 0
    | 2 -> Printf.sprintf "(ui/split-at \"horizontal\" 0.5 %s %s)" (view 0) (view 1)
    | _ -> Printf.sprintf "(ui/split-at \"horizontal\" 0.5 (ui/split-at \"vertical\" 0.5 %s %s) (ui/split-at \"vertical\" 0.5 %s %s))"
        (view 0) (view 1) (view 2) (view 3) in
  Printf.bprintf source "  (graph editor :context editor (ui/workspace %s)))" layout;
  Prismel_editor.Workspace.load (Buffer.contents source) |> Result.get_ok

let run panes frames =
  let spent = ref 0. and started = ref 0. and finished = ref 0. in
  let warm = 30 in
  ignore (Sketch.run_state ~max_frames:(frames + warm)
    ~config:{ Sketch.default_config with width = 1280; height = 800; title = "traced panes" }
    ~init:(fun _ -> E.create ~workspace:(workspace panes) ~domains:1 ~await:true ~seed:42L
      ~presets:(Filename.temp_dir "prismel-traced-panes" "")
      ~prepare:(fun _ output -> Pdk_prismel.Prismel_mesh.to_mesh output.Procedural.Session.geometry
        |> Result.map_error Pdk.Error.to_string)
      ~scene3:(fun _ mesh -> Scene3.create [ Scene3.mesh mesh ]) () |> Result.get_ok)
    ~update:(fun e (frame : Frame.t) ->
      let t = Unix.gettimeofday () in
      if frame.count = warm then started := t;
      let e = E.update e frame in
      if frame.count > warm then spent := !spent +. (Unix.gettimeofday () -. t);
      e)
    ~view:E.scene
    ~after_present:(fun e (frame : Frame.t) ->
      if frame.count = frames + warm then finished := Unix.gettimeofday ();
      E.after_present e frame)
    ~on_stop:E.close ());
  Printf.printf "%d traced panes: %.3f ms/frame in update, %.3f ms/frame wall (%.1f fps)\n%!" panes
    (!spent *. 1000. /. float frames) ((!finished -. !started) *. 1000. /. float frames)
    (float frames /. (!finished -. !started))

let () =
  let frames = if Array.length Sys.argv > 1 then int_of_string Sys.argv.(1) else 300 in
  let counts = if Array.length Sys.argv > 2 then [ int_of_string Sys.argv.(2) ] else [ 1; 2; 4 ] in
  List.iter (fun panes -> run panes frames) counts
