module E = Flow.Eval
module I = Flow_ir
module L = Flow_sop.Lower
module N = Flow_sop.Network
module S = Procedural.Session
let ok = function Ok x -> x | Error d -> failwith (Flow.Diagnostic.to_string d)
let string_ok = function Ok x -> x | Error d -> failwith d
let rec functions = function
  | E.Fn f -> E.Record ["body", E.Text (Option.fold ~none:"named" ~some:(fun (params, (body : Flow.Workspace.term)) ->
        Marshal.to_string (params, Flow.Lisp.flat body.form) [Marshal.No_sharing])
        (E.Private.function_body f)); "captures", functions (E.Record (E.Private.function_bindings f))]
  | List xs -> E.List (Array.map functions xs)
  | Record fields -> E.Record (List.map (fun (n,v) -> n,functions v) fields)
  | Struct (name, ty, fields) -> E.Struct (name, ty, List.map (fun (n,v) -> n,functions v) fields)
  | value -> value
let key value = Flow.Value.key_of ~residual:E.Private.residual_id (functions value)
let equal a b = match a, b with
  | Ok a, Ok b -> key a = key b
  | Error a, Error b -> Flow.Diagnostic.to_string a = Flow.Diagnostic.to_string b
  | _ -> false
let values (e : E.t) = List.map snd e.results @ e.states
  @ Array.fold_right (fun (n : E.node) acc -> List.map snd n.args @ acc) e.plan.nodes []
  @ Array.fold_right (fun (i : E.instance) acc -> i.result :: List.map snd i.inputs @ acc) e.plan.instances []
  @ List.concat_map (fun (_, records) -> List.map snd records) e.records
let signature (e : E.t) =
  Array.map (fun (n : E.node) -> n.id, n.kind, n.ty, n.site, n.iter, n.inst, List.map (fun (n,v) -> n,key v) n.args) e.plan.nodes,
  Array.map (fun (i : E.instance) -> i.graph, i.default, i.inputs |> List.map (fun (n,v) -> n,key v), key i.result) e.plan.instances,
  List.map (fun (n,v) -> n,key v) e.results, List.map key e.states,
  List.map (fun (p, vs) -> p,List.map (fun (it,v) -> it,key v) vs) e.records

(* Native qualification oracle: original CPU doubles, original 68-byte ABI.
   The production mirror never feeds this packing path. *)
let legacy_vertices mesh =
  let view = Rays.Mesh.Private.view mesh in
  let mesh = match view.normals, view.mode with
    | None, (Rays.Mesh.Triangles | Triangle_strip | Triangle_fan) -> Rays.Mesh.recalculate_normals mesh
    | _ -> mesh in
  let view = Rays.Mesh.Private.view mesh in
  let bytes = Bytes.make (Array.length view.vertices * 68) '\000' in
  Array.iteri (fun index (position : Rays.Vec3.t) ->
    let normal = Option.fold ~none:(Rays.Vec3.create 0. 0. 1.)
      ~some:(fun normals -> normals.(index)) view.normals in
    let put offset value = Bytes.set_int64_le bytes (index * 68 + offset) (Int64.bits_of_float value) in
    put 0 position.x; put 8 position.y; put 16 position.z;
    put 24 normal.x; put 32 normal.y; put 40 normal.z;
    let color = Option.fold ~none:Rays.Color.white ~some:(fun colors -> colors.(index)) view.colors in
    Bytes.set_int32_le bytes (index * 68 + 48) (Int32.of_int
      ((color.r lsl 24) lor (color.g lsl 16) lor (color.b lsl 8) lor color.a));
    Option.iter (fun coordinates -> let uv : Rays.Vec2.t = coordinates.(index) in
      put 52 uv.x; put 60 uv.y) view.tex_coords) view.vertices;
  bytes

let compare_float32 runtime id mesh scene =
  let native result = Result.map_error Ogpu.Error.to_string result |> string_ok in
  let staged = Rays.Scene.Private.stage_native ~width:320 ~height:240 scene
    |> string_ok in
  let current = List.concat_map (fun (prepared : Scene_execution.prepared_scene3) ->
    Array.to_list prepared.entries) staged.scene3 in
  let vertices = legacy_vertices mesh in
  let legacy = List.map (fun (entry : Scene_execution.sampled_draw) ->
    let uniforms = Bytes.copy (Option.get entry.draw.state.transform_uniforms) in
    Bytes.set_int32_le uniforms (82 * 4) 0l;
    let attributes_key = fst (Option.get entry.vertex_attributes) in
    {entry with vertex_attributes = None; draw = {
      mesh = {entry.draw.mesh with key = entry.draw.mesh.key ^ ":f64-oracle:" ^ attributes_key; vertices};
      state = {entry.draw.state with transform_uniforms = Some uniforms}}}) current in
  let render entries =
    ignore (native (Runtime.render_sampled_resources ~clear:(0.,0.,0.,1.) runtime entries));
    native (Runtime.read_pixels runtime ~bytes_per_row:1280) in
  let before = render legacy and after = render current in
  let maximum = ref 0 and changed = ref 0 in
  for pixel = 0 to Bytes.length after / 4 - 1 do
    let different = ref false in
    for channel = 0 to 3 do
      let index = pixel * 4 + channel in
      let difference = abs (Char.code (Bytes.get before index) - Char.code (Bytes.get after index)) in
      maximum := max !maximum difference;
      if difference <> 0 then different := true
    done;
    if !different then incr changed
  done;
  Printf.printf "Scene3 f64/f32 %s: maximum channel difference %d, changed pixels %d/%d\n%!"
    id !maximum !changed (Bytes.length after / 4)

let picture ?compare (output : S.output) =
  let geometry = Result.get_ok (Procedural.Payload.geometry output.payload) in
  let mesh = Rdk_rays.Rays_mesh.to_mesh geometry |> Result.map_error Rdk.Error.to_string |> string_ok in
  let positions = Rdk.Packed.Float3.Private.view (Rdk.Geometry.positions geometry) in
  let lo = Array.make 3 infinity and hi = Array.make 3 neg_infinity in
  Array.iteri (fun axis values -> Array.iter (fun v -> lo.(axis) <- min lo.(axis) v; hi.(axis) <- max hi.(axis) v) values)
    [|positions.x; positions.y; positions.z|];
  let center = if positions.x = [||] then Rays.Vec3.zero else
    Rays.Vec3.create ((lo.(0) +. hi.(0)) *. 0.5) ((lo.(1) +. hi.(1)) *. 0.5) ((lo.(2) +. hi.(2)) *. 0.5) in
  let radius = if positions.x = [||] then 1. else max 1. (Array.fold_left max 0. (Array.mapi (fun i v -> v -. lo.(i)) hi)) in
  let camera = Rays.Camera.perspective ~far:(radius *. 100.)
    ~at:(Rays.Vec3.add center (Rays.Vec3.create (radius *. 1.4) (radius *. 1.1) (radius *. 1.8))) ~target:center () in
  let material = Rays.Material.unlit Rays.Color.white in
  let node = match output.instances with None -> Rays.Scene3.mesh ~material ~cull:Rays.Scene3.Cull_none mesh
    | Some transforms -> Rays.Scene3.instances_array ~material ~cull:Rays.Scene3.Cull_none mesh transforms in
  let scene = [Rays.Scene.clear Rays.Color.black; Rays.Scene.view3d ~camera (Rays.Scene3.create [node])] in
  Option.iter (fun compare -> compare mesh scene) compare;
  scene

let check ?directory ~factories ~name (workspace : Editor_document.Workspace_doc.t) =
  let catalog = Editor_document.Contexts.catalog ~version:Flow_sop.Manifest.version factories |> ok in
  let evaluated = E.static ~record:true ~inputs:workspace.inputs workspace.checked |> ok in
  let compiled = L.of_checked ~factories ~inputs:workspace.inputs workspace.checked |> ok
  and reference = L.of_checked ~reference:true ~factories ~inputs:workspace.inputs workspace.checked |> ok in
  if signature evaluated <> signature compiled.evaluated || signature evaluated <> signature reference.evaluated
    then failwith (name ^ ": static plan/instance/value/record mismatch");
  ignore (I.of_evaluation workspace.checked catalog evaluated |> I.optimize |> ok);
  let prepared = List.map (fun v -> v, I.Executor.compile v |> ok) (values evaluated) in
  let pixels = Option.map (fun directory ->
    if not (Sys.file_exists directory) then Unix.mkdir directory 0o755;
    let drawing = List.exists (fun (_,v) -> Flow.Value.ty_of v = Flow.Ty.drawing) evaluated.results in
    Rays.Canvas.create_exn ~width:(if drawing then 800 else 320) ~height:(if drawing then 600 else 240)) directory in
  let images = Hashtbl.create 32 and payloads = Hashtbl.create 32 in
  let mirror = try Option.bind pixels (fun _ ->
    if Sys.getenv_opt "RAYS_SCENE3_FLOAT32_COMPARE" <> Some "1" then None else
    let gpu = Rays_execution.acquire_gpu () |> Result.map_error
      (Format.asprintf "%a" Rays_execution.pp_error) |> string_ok in
    match Runtime.create_offscreen ~device:(Rays_execution.gpu_device gpu)
      ~logical_width:320 ~logical_height:240 ~width:320 ~height:240 () with
    | Ok runtime -> Some (gpu, runtime)
    | Error error -> Rays_execution.release_gpu gpu; failwith (Ogpu.Error.to_string error))
    with exn -> Option.iter Rays.Canvas.destroy pixels; raise exn in
  let compare table id value = match Hashtbl.find_opt table id with
    | None -> Hashtbl.add table id value | Some expected -> if value <> expected then failwith (name ^ ": " ^ id ^ " mismatch") in
  Fun.protect ~finally:(fun () -> Fun.protect ~finally:(fun () ->
    Option.iter (fun (gpu, runtime) -> Fun.protect ~finally:(fun () -> Rays_execution.release_gpu gpu)
      (fun () -> ignore (Runtime.destroy runtime))) mirror)
    (fun () -> Option.iter Rays.Canvas.destroy pixels)) (fun () ->
  List.iter (fun domains -> Rays.Parallel.run ~domains (fun () ->
    let ir_state = E.create_state () and ref_state = E.create_state () in
    let modes = [false, compiled, ir_state; true, reference, ref_state] |> List.map (fun (reference, (lowered : L.t), state) ->
      let lanes = List.map (fun (g : L.graph) -> g, Flow_sop.Value_lane.create ~state ()) lowered.graphs in
      let session = S.create ~max_entries:512 ~max_payload_bytes:(256 * 1024 * 1024) |> string_ok in
      S.set_volatile session (L.is_volatile lowered);
      reference, lowered, state, lanes, session) in
    Fun.protect ~finally:(fun () -> List.iter (fun (_,_,_,_,s) -> S.close s) modes) (fun () ->
    List.iteri (fun frame time ->
      let live = {(Frame_input.at_time time) with frame; dt = (if frame = 0 then 0. else time -. [|0.;0.125;1.25;7.|].(frame-1)); size = (800,600)} in
      let results = List.map (fun (reference, (lowered : L.t), state, lanes, session) ->
        let networks = List.map (fun ((g : L.graph), lane) -> g,
          (Flow_sop.Value_lane.resolve ~live lane ~time g.network |> ok).geometry) lanes in
        let context = Procedural.Context.create ~input:live ~time ~frame:(Int64.of_int frame) ~domains () |> string_ok in
        let cook network cid =
          let node = Procedural.Edit_graph.compile_node network ~node_id:cid |> string_ok in
          match S.cook session ~context node with Ok output -> output
            | Error d -> failwith (name ^ ": " ^ Procedural.Diagnostic.error_to_string d) in
        let sources = Hashtbl.create 8 in
        let geometry id = match Hashtbl.find_opt sources id with Some g -> Some g | None ->
          Option.bind (N.Int_map.find_opt id lowered.compiled) (fun cid ->
            Option.bind (List.find_opt (fun (_,network) -> Procedural.Edit_graph.find network ~node_id:cid <> None) networks)
              (fun (_,network) -> let g = (Result.get_ok (Procedural.Payload.geometry (cook network cid).payload)) in Hashtbl.add sources id g; Some g)) in
        let resolve = Flow_sop.Attribute_kernel.resolve ~geometry in
        let results = List.mapi (fun index (value, program) ->
          let result = if reference then E.Private.force_reference ~state ~resolve value ~live
            else I.Executor.force ~state ~resolve program ~live in
          let id = Printf.sprintf "value-%d-t%g" index time in
          let bytes = match result with Ok v -> "ok:" ^ key v | Error d -> "error:" ^ Flow.Diagnostic.to_string d in
          compare payloads id bytes;
          result) prepared in
        let cooked = List.filter_map (fun ((g : L.graph), network) -> Option.map (fun cid ->
          let output = cook network cid in
          let id = Printf.sprintf "%s-%d-t%g" g.name g.instance time in
          let bytes = match output.payload with
            | Procedural.Payload.Geometry geometry -> Rdk_test_support.geometry_bytes geometry
            | Image image -> Marshal.to_string (Procedural.Image.width image, Procedural.Image.height image,
                Procedural.Image.Private.storage image) [Marshal.No_sharing] in
          compare payloads ("geometry-" ^ id) (bytes ^ Marshal.to_string output.instances []);
          id, output) g.root) networks in
        (match pixels, directory with Some canvas, Some directory ->
          let render id scene =
            Rays.Canvas.render canvas scene;
            let bytes = Marshal.to_string (Rays.Canvas.pixels canvas) [Marshal.No_sharing] in
            compare images id bytes;
            if not reference && domains = 1 then Rays.Canvas.save_png canvas (Filename.concat directory (id ^ ".png")) |> string_ok in
          List.iter (fun (id, output) ->
            let compare = if not reference && domains = 1 && frame = 0 then
              Option.map (fun (_, runtime) -> compare_float32 runtime id) mirror else None in
            render id (picture ?compare output)) cooked;
          List.iter (fun (graph, value) -> if Flow.Value.ty_of value = Flow.Ty.drawing then begin
            let prepared = Sketch_support.Drawing.prepare ~states:evaluated.states evaluated.plan value |> ok in
            let scene = Sketch_support.Drawing.render_prepared ~state ~reference prepared ~live ~size:(800,600) |> ok in
            render (Printf.sprintf "%s-draw-t%g" graph time) scene
          end) evaluated.results
        | _ -> ()); results) modes in
      (match results with [a;b] -> if not (List.for_all2 equal a b) then failwith (name ^ ": IR/reference value mismatch") | _ -> assert false);
      if E.state_stamp ir_state <> E.state_stamp ref_state then failwith (name ^ ": fold state mismatch"))
      [0.;0.125;1.25;7.]))) [1;8]);
  Printf.printf "%s: %d nodes, %d instances, %d values, four times, domains 1/8%s\n%!" name
    (Array.length evaluated.plan.nodes) (Array.length evaluated.plan.instances) (List.length prepared)
    (if directory = None then ", cooked payloads equal" else ", cooked payloads and native geometry/drawing pixels equal")

let report_approx ~name (document : Editor_document.Workspace_doc.t) =
  let paths = Flow.Workspace.Paths.elements document.checked.approx in
  Printf.printf "%s: %d approximable [%s]\n%!" name (List.length paths)
    (String.concat "; " (List.map (String.concat "/") paths))
