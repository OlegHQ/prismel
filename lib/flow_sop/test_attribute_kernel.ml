open Rdk
open Rdk_test_support
module E = Flow.Eval
module L = Flow_sop.Lower
module Edit = Procedural.Edit_graph
module Session = Procedural.Session
let flow_ok = function Ok x -> x | Error d -> failwith (Flow.Diagnostic.to_string d)
let factories = Sop_catalog.Editor.factories
let catalog = Flow_sop.Catalog.of_factories ~version:1 factories |> flow_ok
let source ?(columns = 33) ?(amp = "0.8") body = Printf.sprintf
  "(workspace kernel (graph g :context sop (let* [g (sop/grid :counts \"Point counts\" :connectivity \"Points\" :columns %d :rows 2) amp %s freq 0.16 result %s] result)))"
  columns amp body
let noise_body = "(sop/with_attr g :P (exact (map (fn [p n] (+ p (* n (* amp (noise3 (* p freq)))))) (sop/attr g :P) (sop/attr g :N))))"
let lower ?previous text =
  let forms = Flow.Syntax.parse text |> flow_ok in
  let compiled_ids = Option.map (fun (l : L.t) -> l.compiled_ids) previous
  and sites = Option.map (fun (l : L.t) -> l.sites) previous in
  match L.workspace ~factories ?compiled_ids ?sites forms with
  | Ok lowered -> lowered
  | Error d -> failwith (text ^ "\n" ^ Flow.Diagnostic.to_string d)
let compiled (l : L.t) =
  let graph = List.hd l.graphs in
  Edit.compile_node graph.network.geometry ~node_id:(Option.get graph.root) |> get_string_ok
let context ~domains time = Procedural.Context.create ~domains ~time ~grain:257 () |> get_string_ok
let session () = Session.create ~max_entries:32 ~max_payload_bytes:(64 * 1024 * 1024) |> get_string_ok
let cook session ~domains ~time node = Session.cook session ~context:(context ~domains time) node
let geometry = function Ok (output : Session.output) -> (Result.get_ok (Procedural.Payload.geometry output.payload))
  | Error d -> failwith (Procedural.Diagnostic.error_to_string d)
let reference (l : L.t) node =
  let n = Array.find_opt (fun (n : E.node) -> n.kind = "sop/with_attr") l.plan.nodes |> Option.get in
  let values = List.assoc "values" n.args in
  let sources = match List.assoc "geometry" n.args with E.Deferred (_, id) ->
    id :: List.filter ((<>) id) (Flow_sop.Attribute_kernel.sources values) | _ -> assert false in
  Flow_sop.Attribute_kernel.node ~reference:true ~source:"reference"
    ~name:"P" ~values ~sources (Procedural.Node.inputs node)
let stages program = Array.fold_left (fun count (node : Flow_ir.node) -> match node.kind with
  | Kernel {body = Packed_map p; _} -> max count (Flow_ir.Packed.stage_count p)
  | _ -> count) 0 (Flow_ir.Executor.graph program).nodes

let () =
  let text = "(workspace field (graph g :context sop
    (sop/iso_surface :field (fn [p] (- (length p) (+ 1 t)))
      :resolution [64 64 64] :min [-2 -2 -2] :max [2 2 2] :iso 0)))" in
  let lowered = lower text in
  let call = Array.find_opt (fun (n : E.node) -> n.kind = "sop/iso_surface")
      lowered.plan.nodes |> Option.get in
  let fn = match List.assoc "field" call.args with E.Fn fn -> fn | _ -> assert false in
  (* Independent index decomposition pins all 65^3 positions and x-fast order. *)
  let positions = Array.init (65 * 65 * 65 * 3) (fun j ->
    let i = j / 3 in
    let index = match j mod 3 with 0 -> i mod 65 | 1 -> (i / 65) mod 65 | _ -> i / (65*65) in
    -2. +. float_of_int index *. (4. /. 64.)) in
  let values = E.Private.map_function ~signature:Flow.Ty.{params = [Vec3]; result = Float}
      fn [E.Vec3_array positions] |> flow_ok in
  let program = Flow_sop.Attribute_kernel.prepare ~sources:[] [] values |> flow_ok in
  let ir = Flow_ir.Executor.graph program in
  let packed = match ir.nodes.(ir.roots.(0)).kind with
    | Flow_ir.Kernel {body = Packed_map packed; _} -> packed | _ -> assert false in
  assert (Flow_ir.Packed.static_count packed = Some (65 * 65 * 65));
  List.iter (fun time ->
    let live = Frame_input.at_time time in
    let expected = Array.init (65 * 65 * 65) (fun i ->
      let x = positions.(3*i) and y = positions.(3*i+1) and z = positions.(3*i+2) in
      sqrt ((x *. x +. y *. y) +. z *. z) -. (1. +. time)) in
    let reference = Flow_ir.Executor.force ~reference:true program ~live |> flow_ok in
    assert (reference = E.Float_array expected);
    let dense = Iso_surface.extract_dense ~resolution:(64,64,64)
        ~min:(Rays_math.Vec3.create (-2.) (-2.) (-2.)) ~max:(Rays_math.Vec3.create 2. 2. 2.)
        ~iso:0. ~field:(Iso_surface.Field.custom (fun p ->
          sqrt ((p.(0) *. p.(0) +. p.(1) *. p.(1)) +. p.(2) *. p.(2)) -. (1. +. time))) ()
      |> get_ok |> geometry_bytes in
    List.iter (fun domains ->
      let actual = Rays_math.Parallel.run ~domains (fun () ->
        Flow_ir.Packed.force packed ~live |> flow_ok) in
      assert (actual = reference);
      let cook_session = session () in
      Fun.protect ~finally:(fun () -> Session.close cook_session) (fun () ->
        assert (geometry_bytes (cook cook_session ~domains ~time (compiled lowered) |> geometry) = dense));
      let reference_lowered = L.workspace ~factories ~reference:true
          (Flow.Syntax.parse text |> flow_ok) |> flow_ok in
      let cook_session = session () in
      Fun.protect ~finally:(fun () -> Session.close cook_session) (fun () ->
        assert (geometry_bytes (cook cook_session ~domains ~time (compiled reference_lowered) |> geometry) = dense)))
      [1;8]) [0.;0.25];
  let forms = Flow.Syntax.parse text |> flow_ok in
  let checked, diagnostics = Flow.Workspace.check ~ops:Flow_sop.Operators.all catalog forms in
  assert (diagnostics = []);
  let pane = Flow_graph.Projection.of_graph catalog (Option.get checked) "g" in
  let surface = List.find (fun (n : Flow_graph.Projection.node) -> n.head = "sop/iso_surface") pane.nodes in
  assert (List.exists (fun (row : Flow_graph.Projection.row) -> row.label = "field") surface.rows);
  let zone = List.find (fun (n : Flow_graph.Projection.node) ->
    Option.fold ~none:false ~some:(fun (z : Flow_graph.Projection.zone) -> z.kind = Fn) n.zone) pane.nodes in
  assert (List.exists (fun (r : Flow_graph.Projection.rail_row) -> r.name = "p" && r.ty = Some Flow.Ty.Vec3)
    (Option.get zone.zone).rail);
  let calls = L.field_calls ~live:(Frame_input.at_time 0.25)
      ~resolve:(fun v -> Ok v) lowered in
  let forced_calls = ref 0 in
  let bulk_calls path outer = List.map (fun (offset, count, at) ->
    offset, count, (fun k -> incr forced_calls; at k)) (calls path outer) in
  let probe = Flow_graph.Probe.make ~live:(Frame_input.at_time 0.25) ~bulk_calls lowered.evaluated in
  let counts = Flow_graph.Probe.counts probe pane ~probe:(fun _ -> 0) in
  let count = match List.assoc_opt zone.path counts with
    | Some count -> count
    | None -> let scope, iter = E.Private.function_scope fn |> Option.get in
        failwith (Printf.sprintf "field probe: projection %s, function %s/%s, counts %s"
          (String.concat "/" zone.path) (String.concat "/" scope)
          (String.concat "," (List.map string_of_int iter))
          (String.concat ";" (List.map (fun (p,n) -> String.concat "/" p ^ ":" ^ string_of_int n) counts))) in
  assert (count = 65*65*65);
  let k = 16001 in
  let x = positions.(3*k) and y = positions.(3*k+1) and z = positions.(3*k+2) in
  let sample = sqrt ((x *. x +. y *. y) +. z *. z) -. 1.25 in
  assert (Flow_graph.Probe.at probe (zone.path @ [":p"]) ~probes:[k] = Some (Value (E.Vec3 (x,y,z))));
  assert (Flow_graph.Probe.at probe (zone.path @ ["@result"]) ~probes:[k] = Some (Value (E.Float sample)));
  assert (!forced_calls = 1);
  let body = Flow_graph.Projection.find pane (zone.path @ ["@result"]) |> Option.get in
  ignore (Flow_graph.Probe.footer probe body ~probes:[k]);
  assert (!forced_calls <= 65);
  let forced = !forced_calls in
  ignore (Flow_graph.Probe.footer probe body ~probes:[k]);
  assert (!forced_calls = forced);
  ignore (Flow_graph.Flow_edit.apply_checked ~ops:Flow_sop.Operators.all catalog forms
    (Set_arg {node = surface.path; key = Kw "resolution"; sub = [];
      value = Flow.Syntax.parse "[8 9 7]" |> flow_ok |> List.hd}) |> flow_ok);
  print_endline "field SOP: complete grid kernel/reference/domain/mesh parity and graph gestures pass"

let () =
  (* Non-dyadic, off-centre samples expose accidental multiply/add contraction. *)
  let positions = Array.init (130 * 257 * 3 * 3) (fun j ->
    let i = j / 3 in
    match j mod 3 with
    | 0 -> Float.fma (float_of_int (i mod 130)) (5. /. 129.) (-2.)
    | 1 -> Float.fma (float_of_int ((i / 130) mod 257)) (3.5 /. 256.) (-1.5)
    | _ -> Float.fma (float_of_int (i / (130 * 257))) (2.7 /. 2.) (-1.)) in
  let prepare expression =
    let lowered = lower ("(workspace rounding (graph g :context sop
      (sop/iso_surface :field (fn [p] " ^ expression ^ ") :resolution [129 256 2]
        :min [-2 -1.5 -1] :max [3 2 1.7])))") in
    let call = Array.find_opt (fun (n : E.node) -> n.kind = "sop/iso_surface")
      lowered.plan.nodes |> Option.get in
    let fn = match List.assoc "field" call.args with E.Fn fn -> fn | _ -> assert false in
    let values = E.Private.map_function ~signature:Flow.Ty.{params = [Vec3]; result = Float}
      fn [E.Vec3_array positions] |> flow_ok in
    Flow_sop.Attribute_kernel.prepare ~sources:[] [] values |> flow_ok in
  let derived = prepare "(- (length (- p [0.2 -0.3 0.1])) (+ 0.8 t))"
  and primitives = prepare "(let* [q (- p [0.2 -0.3 0.1])]
    (- (sqrt (+ (+ (* q.x q.x) (* q.y q.y)) (* q.z q.z))) (+ 0.8 t)))" in
  let same_bits actual expected = match actual, expected with
    | E.Float_array actual, E.Float_array expected ->
        assert (Array.length actual = Array.length expected);
        Array.iteri (fun i value ->
          if Int64.bits_of_float value <> Int64.bits_of_float expected.(i) then
            failwith (Printf.sprintf "field length rounding differs at sample %d: %.17g / %.17g"
              i value expected.(i))) actual
    | _ -> assert false in
  List.iter (fun time ->
    let live = Frame_input.at_time time in
    let expected = Flow_ir.Executor.force ~reference:true primitives ~live |> flow_ok in
    same_bits (Flow_ir.Executor.force ~reference:true derived ~live |> flow_ok) expected;
    List.iter (fun domains -> Rays_math.Parallel.run ~domains (fun () ->
      List.iter (fun program ->
        same_bits (Flow_ir.Executor.force program ~live |> flow_ok) expected)
        [derived; primitives])) [1;8]) [0.;0.25];
  print_endline "field length: asymmetric lattice matches primitive/scalar/packed float64 bits"

let () =
  let text = "(workspace probe (graph g :context sop
    (let* [field (fn [p] p.x)
           preview (map field (array/vec3 2 [1 0 0]))
           a (sop/iso_surface :field field :resolution [1 1 1])
           b (sop/iso_surface :field field :resolution [2 1 1])]
      (sop/merge a b))))" in
  let lowered = lower text in
  let forms = Flow.Syntax.parse text |> flow_ok in
  let workspace, ds = Flow.Workspace.check ~ops:Flow_sop.Operators.all catalog forms in
  assert (ds = []);
  let pane = Flow_graph.Projection.of_graph catalog (Option.get workspace) "g" in
  let calls = L.field_calls ~live:(Frame_input.at_time 0.) ~resolve:(fun v -> Ok v) lowered in
  let selectors = calls ["g";"field"] [] in
  assert (List.map (fun (offset,count,_) -> offset,count) selectors = [0,8; 8,12]);
  let probe = Flow_graph.Probe.make ~bulk_calls:calls lowered.evaluated in
  assert (List.assoc ["g";"field"] (Flow_graph.Probe.counts probe pane ~probe:(fun _ -> 0)) = 22);
  List.iter (fun (k,expected) ->
    assert (Flow_graph.Probe.at probe ["g";"field";"@result"] ~probes:[k]
      = Some (Value (E.Float expected)))) [0,1.; 1,1.; 2,(-2.); 9,2.; 10,(-2.); 21,2.];
  assert (Flow_graph.Probe.at probe ["g";"field";"@result"] ~probes:[22] = None)

let () =
  let lowered = lower "(workspace probe_state (graph g :context sop
    (let* [total (state [s 0.0] (+ s 1.0))
           field (fn [p] (+ p.x total))]
      (sop/iso_surface :field field :resolution [1 1 1]))))" in
  let state = E.create_state () in
  let before = E.state_stamp state in
  let calls = L.field_calls ~state ~live:(Frame_input.at_time 1.) ~resolve:(fun v -> Ok v) lowered in
  let probe = Flow_graph.Probe.make ~state ~live:(Frame_input.at_time 1.) ~bulk_calls:calls lowered.evaluated in
  assert (Flow_graph.Probe.at probe ["g";"field";"@result"] ~probes:[0] = Some (Value (E.Float (-1.))));
  assert (E.state_stamp state = before)

let () =
  (* Real Lisp lowering, not a hand-built Readback IR: GPU callbacks run before
     worker cooking, and workers receive only an owned exact CPU snapshot. *)
  let count=2048 and calls=ref 0 and reads=ref 0 and time=ref 0. in
  let backend:Flow_ir.Gpu.backend={cost=(fun _ ~count:_->Some 0.);
    prepare=(fun _->assert(Domain.is_main_domain());Ok {
      run=(fun inputs->assert(Domain.is_main_domain());assert(inputs.count=count);
        incr calls;Ok {identity=1;count;width=3;stamp=Int64.of_int !calls;gpu_seconds=None});
      readback=(fun _->assert(Domain.is_main_domain());incr reads;
        Ok(E.Vec3_array(Array.init(count*3)(fun j->if j mod 3=0 then float(j/3)+. !time else 0.))))})} in
  let body wrap="(sop/with_attr g :P ("^wrap^
    "(map (fn [i] [(+ i t) 0 0]) (array/range 2048))))" in
  let exact=lower(source ~columns:1024 (body "exact ")) in
  let network=(List.hd exact.graphs).network in
  let lane=Flow_sop.Value_lane.create() in
  List.iter(fun t->time:=t;
    let resolved=Flow_ir.Gpu.with_backend backend(fun()->
      Flow_sop.Value_lane.resolve lane ~time:t network |> flow_ok) in
    let node=Edit.compile_node resolved.geometry ~node_id:(Option.get(List.hd exact.graphs).root)
      |>get_string_ok in
    List.iter(fun domains->let session=session()in
      Fun.protect ~finally:(fun()->Session.close session)(fun()->
        let positions=cook session ~domains ~time:t node |> geometry |>Geometry.positions in
        for i=0 to count-1 do assert(Packed.Float3.get positions i=(float i+.t,0.,0.))done)) [1;8]) [0.;0.5];
  assert(!calls=2 && !reads=2);
  let unmeasured={backend with cost=(fun _ ~count:_->None)}in
  ignore(Flow_ir.Gpu.with_backend unmeasured(fun()->Flow_sop.Value_lane.resolve
    (Flow_sop.Value_lane.create()) ~time:0.75 network)|>flow_ok);
  assert(!calls=2);
  time:=0.75;
  ignore(Flow_ir.Gpu.with_backend ~policy:Flow_ir.Gpu.Qualification unmeasured(fun()->
    Flow_sop.Value_lane.resolve (Flow_sop.Value_lane.create()) ~time:0.75 network)|>flow_ok);
  assert(!calls=3 && !reads=3);
  let baseline= !calls in
  let cpu=Flow_sop.Value_lane.create()in
  ignore(Flow_sop.Value_lane.resolve cpu ~time:1. network |>flow_ok);
  let reference=L.workspace ~factories ~reference:true
    (Flow.Syntax.parse(source ~columns:1024(body "exact "))|>flow_ok)|>flow_ok in
  ignore(Flow_ir.Gpu.with_backend backend(fun()->Flow_sop.Value_lane.resolve
    (Flow_sop.Value_lane.create()) ~time:1. (List.hd reference.graphs).network)|>flow_ok);
  assert(!calls=baseline);
  let unwrapped=Flow.Syntax.parse(source ~columns:1024
    "(sop/with_attr g :P (map (fn [i] [(+ i t) 0 0]) (array/range 2048)))") |> flow_ok in
  (match Flow.Workspace.check ~ops:Flow_sop.Operators.all catalog unwrapped with
    |None, ds->assert(List.exists(fun(d:Flow.Diagnostic.t)->d.code="E_APPROX_SINK")ds)
    |_->assert false)
let () =
  assert (Result.is_error (Flow_sop.Attribute_kernel.prepare ~sources:[0] [] E.No_geo));
  List.iter (fun (other, expected_stages) ->
    let body = "(let* [other " ^ other ^
      " a (map (fn [p] (+ p [t 0 0])) (sop/attr g :P))" ^
      " b (map (fn [p] (* p (+ t 1))) (sop/attr other :P))]" ^
      " (sop/with_attr g :P (exact (map (fn [left right] (+ left right)) a b))))" in
    let l = lower (source ~columns:1025 body) in
    let node = compiled l in
    let call = Array.find_opt (fun (n : E.node) -> n.kind = "sop/with_attr") l.plan.nodes |> Option.get in
    let values = List.assoc "values" call.args in
    let main = match List.assoc "geometry" call.args with E.Deferred (_, id) -> id | _ -> assert false in
    let sources = main :: List.filter ((<>) main) (Flow_sop.Attribute_kernel.sources values) in
    let inputs = Procedural.Node.inputs node in
    let prepare inputs = Flow_sop.Attribute_kernel.prepare ~sources inputs values |> flow_ok in
    assert (stages (Flow_ir.Executor.compile values |> flow_ok) = 1);
    let program = prepare inputs in
    assert (stages program = expected_stages);
    if expected_stages = 3 && List.length inputs > 1 then begin
      let change field = List.mapi (fun i node -> if i = 0 then node else
        Procedural.Node.Private.with_facts (field (Procedural.Node.facts node)) node) inputs in
      assert (stages (prepare (change (fun facts -> {facts with topology = Changed}))) = 1);
      assert (stages (prepare (change (fun facts -> {facts with elementwise = None}))) = 1);
      assert (stages (prepare (change (fun facts -> {facts with elementwise = Primitives}))) = 3)
    end;
    let session = session () in
    Fun.protect ~finally:(fun () -> Session.close session) (fun () ->
      let source_geometries = List.map (fun input -> cook session ~domains:1 ~time:0. input |> geometry) inputs in
      let resolve = Flow_sop.Attribute_kernel.resolve ~geometry:(fun id ->
        Option.bind (List.find_index ((=) id) sources) (fun index -> List.nth_opt source_geometries index)) in
      List.iter (fun time ->
        let live = Frame_input.at_time time in
        let expected = E.Private.force_reference ~resolve values ~live |> flow_ok in
        List.iter (fun domains -> Rays_math.Parallel.run ~domains (fun () ->
          let actual = Flow_ir.Executor.force ~resolve program ~live |> flow_ok in
          assert (Marshal.to_string actual [Marshal.No_sharing] = Marshal.to_string expected [Marshal.No_sharing])))
          [1;8]) [0.;0.125;1.25;7.]))
    ["g", 3; "(sop/transform g :translate [0 0 1])", 3;
     "(sop/grid :counts \"Point counts\" :connectivity \"Points\" :columns 1025 :rows 2)", 1;
     "(sop/scatter (sop/grid) :count 2050 :seed 9)", 1]
let () =
  let empty = Kernel.generate_point_ranges 0 (fun ~first:_ ~last:_ ~x:_ ~y:_ ~z:_ -> ()) in
  let empty_input = Procedural.Node.Private.make_geometry ~operation:"empty_fixture" ~version:1
    ~parameters:"" ~cook_mode:Procedural.Node.Generator
    ~dependencies:Procedural.Context.Dependencies.static ~inputs:[||]
    (fun ~node_id:_ _ _ -> Ok Procedural.Node.Private.{geometry=empty; diagnostics=[]; instances=None}) in
  let empty_write = Flow_sop.Attribute_kernel.node ~source:"empty"
    ~name:"P" ~values:(E.Struct ("sop/attr", Flow.Ty.Array Flow.Ty.Vec3,
      ["geometry", E.Deferred (Flow.Ty.geometry,0); "attribute", E.Text "P"]))
    ~sources:[0] [empty_input] in
  let output = Procedural.Node.Private.cook empty_write (context ~domains:8 0.) [|Procedural.Payload.Geometry empty|] in
  (match output with Ok output -> assert (geometry_bytes (Result.get_ok (Procedural.Payload.geometry output.payload)) = geometry_bytes empty)
    | Error d -> failwith (Procedural.Diagnostic.error_to_string d));
  let cancel = Cancel.create () in
  Cancel.cancel cancel;
  let cancelled = Procedural.Context.create ~cancel ~domains:1 () |> get_string_ok in
  (match Procedural.Node.Private.cook empty_write cancelled [|Procedural.Payload.Geometry empty|] with
   | Error d -> assert (d.code = "E_CANCELLED") | Ok _ -> assert false);
  List.iter (fun columns ->
    List.iter (fun amp ->
      let l = lower (source ~columns ~amp noise_body) in
      let node = compiled l and session = session () in
      Fun.protect ~finally:(fun () -> Session.close session) (fun () ->
        let ref_node = reference l node in
        List.iter (fun time ->
          let base = cook session ~domains:1 ~time (List.hd (Procedural.Node.inputs node)) |> geometry in
          let before = geometry_bytes base in
          let amplitude = if amp = "0.8" then 0.8 else 0.8 +. time *. 0.1 in
          let native = Deform.noise_displace ~mode:Deform.Normal_3d ~seed:0
            ~amplitude ~frequency:0.16 base |> get_ok in
          List.iter (fun domains -> Rays_math.Parallel.run ~domains (fun () ->
            let output = cook session ~domains ~time node |> geometry in
            assert (List.exists (fun (report : Flow_ir.execution) -> report.tier = Cpu_kernel)
              (Flow_ir.Profile.executions l.profile));
            let reference = cook session ~domains ~time ref_node |> geometry in
            assert (geometry_bytes (output
              |> Geometry.without_attribute ~owner:Attribute.Point "N"
              |> Geometry.without_attribute ~owner:Attribute.Vertex "N") = geometry_bytes native);
            assert (geometry_bytes output = geometry_bytes reference);
            assert (Geometry.topology output == Geometry.topology base))) [1;8];
          assert (geometry_bytes base = before)) [0.;0.125;1.25;7.]))
      ["0.8"; "(+ 0.8 (* t 0.1))"]) [1; 511; 512; 1025; 8193];
  let l = lower (source noise_body) in
  let disconnected = lower "(workspace w (graph g :context sop (sop/with_attr nil :P (array/vec3 4))))" in
  let graph = List.hd disconnected.graphs in
  assert (Result.is_error (Edit.compile_node graph.network.geometry ~node_id:(Option.get graph.root)));
  let named_body = "(let* [f (fn [p n] (+ p (* n (* amp (noise3 (* p freq))))))] (sop/with_attr g :P (exact (map f (sop/attr g :P) (sop/attr g :N)))))" in
  let named = lower (source ~columns:1025 named_body) in
  let call = Array.find_opt (fun (n : E.node) -> n.kind = "sop/with_attr") named.plan.nodes |> Option.get in
  let program = Flow_ir.Executor.compile (List.assoc "values" call.args) |> flow_ok in
  assert (Array.exists (fun (node : Flow_ir.node) -> node.tier = Cpu_kernel && node.rate = Static)
    (Flow_ir.Executor.graph program).nodes);
  let session = session () in
  Fun.protect ~finally:(fun () -> Session.close session) (fun () ->
    let node = compiled named in
    let a = cook session ~domains:1 ~time:0. node |> geometry in
    let b = cook session ~domains:8 ~time:0. (reference named node) |> geometry in
    assert (geometry_bytes a = geometry_bytes b);
    let first = cook session ~domains:1 ~time:0. (compiled l) |> geometry |> geometry_bytes in
    let changed = lower ~previous:l (source ~amp:"1.8" noise_body) in
    let second = cook session ~domains:1 ~time:0. (compiled changed) |> geometry |> geometry_bytes in
    assert (first <> second);
    List.iter (fun (body, code) ->
      let l = lower (source body) in
      match cook session ~domains:1 ~time:0. (compiled l) with
      | Error d -> assert (d.code = code)
      | Ok _ -> failwith ("accepted " ^ code))
      ["(sop/with_attr g :P (array/vec3 1))", "E_ATTR_COUNT";
       "(sop/with_attr g :P (sop/attr g :missing))", "E_ATTR_TYPE"];
    let l = lower (source "(sop/with_attr g :Cd (exact (map (fn [p] (* p 0.5)) (sop/attr g :P))))") in
    let output = cook session ~domains:8 ~time:0. (compiled l) |> geometry in
    let cd = Geometry.find_attribute ~owner:Attribute.Point "Cd" output |> Option.get in
    assert (Attribute.length cd = Geometry.point_count output);
    let l = lower (source "(let* [painted (sop/with_attr g :Cd (sop/attr g :P))] (sop/with_attr painted :P (sop/attr painted :Cd)))") in
    let output = cook session ~domains:1 ~time:0. (compiled l) |> geometry in
    assert (Geometry.find_attribute ~owner:Attribute.Point "Cd" output <> None);
    let l = lower (source ~amp:"(state [a 0.8] (+ a 0.1))" noise_body) in
    let graph = List.hd l.graphs and lane = Flow_sop.Value_lane.create () in
    List.iter (fun frame ->
      let time = float frame *. 0.125 in
      let live = { (Frame_input.at_time time) with frame } in
      let resolved = Flow_sop.Value_lane.resolve ~live lane ~time graph.network |> flow_ok in
      let node = Edit.compile_node resolved.geometry ~node_id:(Option.get graph.root) |> get_string_ok in
      let context = Procedural.Context.create ~input:live ~time ~frame:(Int64.of_int frame)
        ~domains:8 () |> get_string_ok in
      let output = Session.cook session ~context node |> geometry in
      let base = Session.cook session ~context (List.hd (Procedural.Node.inputs node)) |> geometry in
      let amplitude = List.fold_left (fun a _ -> a +. 0.1) 0.8 (List.init (frame + 1) Fun.id) in
      let native = Deform.noise_displace ~mode:Deform.Normal_3d ~seed:0 ~amplitude ~frequency:0.16 base |> get_ok in
      assert (geometry_bytes (Geometry.without_attribute ~owner:Attribute.Point "N" output) = geometry_bytes native))
      [0;1;2]);
  let forms = Flow.Syntax.parse (source noise_body) |> flow_ok in
  let bare = lower (source "(with_attr g :P (attr g :P))") in
  assert (Array.exists (fun (n : E.node) -> n.kind = "sop/with_attr") bare.plan.nodes);
  let reader = lower (source "(let* [arrays (map sop/attr (list g) (list \"P\"))] (sop/with_attr g :P (first arrays)))") in
  let s = Session.create ~max_entries:32 ~max_payload_bytes:(64 * 1024 * 1024) |> get_string_ok in
  Fun.protect ~finally:(fun () -> Session.close s) (fun () ->
    let node = compiled reader in
    let original = cook s ~domains:1 ~time:0. (List.hd (Procedural.Node.inputs node)) |> geometry in
    let copy = cook s ~domains:8 ~time:0. node |> geometry in
    assert (geometry_bytes original = geometry_bytes copy));
  let ws = match Flow.Workspace.check ~ops:Flow_sop.Operators.all catalog forms with
    | Some w, [] -> w | _ -> assert false in
  let pane = Flow_graph.Projection.of_graph catalog ws "g" in
  let result = Flow_graph.Projection.find pane ["g";"result"] |> Option.get in
  assert (List.map (fun (r : Flow_graph.Projection.row) -> r.label) result.rows = ["geometry";"attribute";"values"]);
  let fn = List.find (fun (node : Flow_graph.Projection.node) ->
    Option.fold ~none:false ~some:(fun (zone : Flow_graph.Projection.zone) -> zone.kind = Fn) node.zone)
      pane.nodes in
  let rails = (Option.get fn.zone).rail in
  assert (List.for_all (fun name -> List.exists (fun (rail : Flow_graph.Projection.rail_row) ->
    rail.name = name && rail.ty = Some Flow.Ty.Vec3) rails) ["p"; "n"]);
  let large = lower (source ~columns:8193 ~amp:"(+ 0.8 (* t 0.1))" noise_body) in
  let probe_session = Session.create ~max_entries:32 ~max_payload_bytes:(64 * 1024 * 1024) |> get_string_ok in
  Fun.protect ~finally:(fun () -> Session.close probe_session) (fun () ->
    let node = compiled large in
    let base = cook probe_session ~domains:8 ~time:1.25 (List.hd (Procedural.Node.inputs node)) |> geometry in
    let geometry_id = Array.find_opt (fun (n : E.node) -> n.kind = "sop/grid") large.plan.nodes
      |> Option.get |> fun n -> n.id in
    let reads = ref 0 in
    let resolve value = incr reads;
      Flow_sop.Attribute_kernel.resolve ~geometry:(fun id -> if id = geometry_id then Some base else None) value in
    let checked = match Flow.Workspace.check ~ops:Flow_sop.Operators.all catalog
      (Flow.Syntax.parse (source ~columns:8193 ~amp:"(+ 0.8 (* t 0.1))" noise_body) |> flow_ok) with
      | Some checked, ds when List.for_all (fun (d : Flow.Diagnostic.t) -> d.severity <> Error) ds -> checked
      | _, ds -> failwith (String.concat "\n" (List.map Flow.Diagnostic.to_string ds)) in
    let pane = Flow_graph.Projection.of_graph catalog checked "g" in
    let probe = Flow_graph.Probe.make ~time:1.25 ~resolve large.evaluated in
    assert (List.assoc fn.path
      (Flow_graph.Probe.counts probe pane ~probe:(fun _ -> 0)) = Geometry.point_count base);
    let body = Flow_graph.Projection.find pane (fn.path @ ["@result"]) |> Option.get in
    let before = geometry_bytes base in
    let footer = Flow_graph.Probe.footer probe body ~probes:[16001] in
    assert (footer.runs = Some (Geometry.point_count base));
    let expected = Deform.noise_displace ~mode:Deform.Normal_3d ~seed:0 ~amplitude:(0.8 +. 1.25 *. 0.1)
      ~frequency:0.16 base |> get_ok |> Geometry.positions |> fun p -> Packed.Float3.get p 16001 in
    let x, y, z = expected in
    assert (Flow_graph.Probe.at probe body.path ~probes:[16001] = Some (Flow_graph.Probe.Value (E.Vec3 (x, y, z))));
    assert (!reads = 2);
    ignore (Flow_graph.Probe.footer probe body ~probes:[16001]);
    assert (!reads = 2 && geometry_bytes base = before);
    let _, changed = Flow_graph.Flow_edit.apply_checked ~ops:Flow_sop.Operators.all catalog
      checked.source (Flow_graph.Flow_edit.Set_arg {node = body.path; key = Pos 0; sub = [];
        value = Flow.Syntax.make (Sym "n")}) |> flow_ok in
    let edited = E.static ~record:true changed |> flow_ok in
    let probe = Flow_graph.Probe.make ~time:1.25 ~resolve edited in
    assert ((Flow_graph.Probe.footer probe body ~probes:[16001]).value <> footer.value));
  let _, changed = Flow_graph.Flow_edit.apply_checked ~ops:Flow_sop.Operators.all catalog forms
    (Flow_graph.Flow_edit.Set_arg {node=["g";"result"]; key=Pos 1; sub=[];
      value=Flow.Syntax.make (Str "Cd")}) |> flow_ok in
  let pane = Flow_graph.Projection.of_graph catalog changed "g" in
  let result = Flow_graph.Projection.find pane ["g";"result"] |> Option.get in
  assert ((List.nth result.rows 1).expr |> Option.get |> Flow.Lisp.flat = "\"Cd\"");
  List.iter (fun (op : Flow.Op.t) ->
    assert (Flow.Op.validate [op] = None);
    let args = List.map (fun (name, ty) -> name, match ty with
      | Flow.Ty.Text -> E.Text "P" | Array _ -> E.Vec3_array [||]
      | _ -> E.Deferred (Flow.Ty.geometry,0)) op.signature.pos in
    op.check args;
    let result = op.body ~live:(Frame_input.at_time 0.)
      ~node:(fun _ _ -> E.Deferred (Flow.Ty.geometry,1)) args in
    assert (Flow.Ty.fits (Flow.Value.ty_of result) (op.out (List.map (fun (_,v) -> Flow.Value.ty_of v) args))))
    (List.filter (fun (op : Flow.Op.t) -> op.ctx = Flow.Context.sop) Flow_sop.Operators.all);
  print_endline "Cooked attribute kernel: native/reference/CPU parity, source ownership, cache invalidation, errors and graph edits passed"
