open Prismel
open Procedural

let bright color = color.Color.r > 140 && color.g > 140 && color.b > 140

let count_bright canvas (x, y, width, height) =
  let count = ref 0 in
  for py = max 0 y to min (Canvas.height canvas - 1) (y + height - 1) do
    for px = max 0 x to min (Canvas.width canvas - 1) (x + width - 1) do
      match Canvas.pixel canvas ~x:px ~y:py with
      | Some color when bright color -> incr count
      | Some _ | None -> ()
    done
  done;
  !count

let init (_frame : Frame.t) =
  let source = Sop.box ~label:"Readable source" () in
  let moved = Sop.transform ~label:"Readable transform"
      (Mat4.translation (Vec3.create 1. 0. 0.)) source in
  let graph = Sop.merge ~label:"Readable output" [source; moved] in
  let graph_view = Pxui_graph.create ~width:800 ~height:520 graph in
  let canvas = Canvas.create_exn ~width:800 ~height:520 in
  Canvas.render canvas (Pxui_graph.scene graph_view);
  List.iter (fun node ->
    let x, y, width, _ = node.Pxui_graph.bounds in
    let title_region = x + 7, y + 4, max 1 (width - 34), 24 in
    if count_bright canvas title_region < 6 then
      failwith (Printf.sprintf "graph tile %S title was covered or unreadable"
        node.label)) (Pxui_graph.node_views graph_view);
  if Array.length Sys.argv > 1 then
    Canvas.save_png canvas Sys.argv.(1) |> Result.get_ok;
  Canvas.destroy canvas;
  Sketch.quit ();
  ()

let () =
  ignore (Sketch.run_state
    ~config:{ Sketch.default_config with width = 800; height = 520;
      title = "PXUI graph render smoke" }
    ~init ~update:(fun () _ -> ()) ~view:(fun () _ -> Scene.empty) ())
