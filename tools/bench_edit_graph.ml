(* Cost of recompiling an editable SOP document on every slider-drag frame:
   one parameter change on a node of a long chain, then the compile work
   Prismel_editor's Cook.update performs for the root and displayed node. Reports
   dragging the first node (every downstream node changes) and the last one
   (everything upstream is unchanged). PRISMEL_EDIT_GRAPH_NODES sets the chain
   length, _FRAMES the drag frames per repeat; the best of 5 repeats prints. *)
open Procedural

let integer_env name default = match Sys.getenv_opt name with
  | None -> default | Some value -> max 1 (int_of_string value)

let nodes = integer_env "PRISMEL_EDIT_GRAPH_NODES" 400
let frames = integer_env "PRISMEL_EDIT_GRAPH_FRAMES" 100
let get = function Ok value -> value | Error message -> failwith message

let find key = List.find (fun factory -> Edit_graph.factory_key factory = key)
    Sop_catalog.Editor.factories

(* A factory with one required and one optional input, when the catalog has
   one: those nodes take the rebuild-through-factory path. *)
let optional_factory = List.find_opt (fun factory ->
  Edit_graph.factory_inputs factory = Edit_graph.[Required; Optional])
  Sop_catalog.Editor.factories

let document () =
  let box = find "box" and transform = find "transform" in
  let source = Edit_graph.instantiate box [] |> get in
  let document = Edit_graph.of_graph source in
  let rec chain index ids document =
    let previous = List.hd ids in
    if index = nodes then document, List.rev ids
    else
      let factory, inputs = match optional_factory with
        | Some factory when index mod 4 = 3 -> factory, [Some previous; None]
        | _ -> transform, [Some previous] in
      let input_nodes = List.map (Option.map (fun id ->
        Option.get (Edit_graph.find document ~node_id:id))) inputs in
      let node = Edit_graph.instantiate_optional factory input_nodes |> get in
      let document = Edit_graph.add_node ~factory
          ~inputs:(Array.of_list inputs) node document |> get in
      chain (index + 1) (Node.id node :: ids) document in
  let document, ids = chain 0 [Node.id source] document in
  let last = List.nth ids nodes in
  get (Edit_graph.set_root last document), List.nth ids 1, List.nth ids (nodes - 3)

(* [full] compiles the root and displayed node from scratch each frame;
   [incremental] is what Cook.update does: compile_all against the previous
   frame's result, then two lookups. *)
let drag ~incremental document ~dragged ~displayed =
  Gc.compact ();
  let root = Option.get (Edit_graph.root document) in
  let minor = Gc.minor_words () and start = Unix.gettimeofday () in
  ignore (List.init frames Fun.id |> List.fold_left (fun (document, previous) frame ->
    let document, _ = Edit_graph.apply_parameters document ~node_id:dragged
        ["translate_x", Parameter.Float_value (float_of_int frame /. 100.)]
      |> get in
    if incremental then begin
      let compiled = Edit_graph.compile_all ?previous document in
      ignore (get (Edit_graph.compiled_node compiled ~node_id:root));
      ignore (get (Edit_graph.compiled_node compiled ~node_id:displayed));
      document, Some compiled
    end else begin
      ignore (get (Edit_graph.compile document));
      ignore (get (Edit_graph.compile_node document ~node_id:displayed));
      document, None
    end) (document, if incremental then Some (Edit_graph.compile_all document) else None));
  (Unix.gettimeofday () -. start) *. 1000. /. float_of_int frames,
  (Gc.minor_words () -. minor) /. float_of_int frames

let () =
  let document, first, late = document () in
  let displayed = Option.get (Edit_graph.root document) in
  List.iter (fun (incremental, (name, dragged)) ->
    let runs = List.init 5 (fun _ -> drag ~incremental document ~dragged ~displayed) in
    let ms = List.fold_left (fun best (ms, _) -> Float.min best ms) infinity runs in
    Printf.printf
      "edit_graph %s drag %-5s nodes=%d frames=%d optional=%s %.3f ms/frame %.0f minor words/frame\n"
      (if incremental then "incremental" else "full       ") name nodes frames
      (match optional_factory with Some f -> Edit_graph.factory_key f | None -> "none")
      ms (snd (List.hd runs)))
    (List.concat_map (fun mode -> [mode, ("first", first); mode, ("late", late)])
      [false; true])
