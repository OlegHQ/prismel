(* Workspace lowering and cook.
   dune exec tools/bench_workspace_lower.exe -- [cases-dir] [repeats]
   Per fixture: check / eval / lower+cook medians.  Then, for Bloom, Sunflower,
   Wave and Tree: cold and warm cook at Session capacity 32 and 512. *)
open Flow_sop

let factories = Sop_catalog.Editor.factories
let ok = function Ok v -> v | Error d -> failwith (Flow.Diagnostic.to_string d)
let now = Unix.gettimeofday
let median f repeats =
  let times = Array.init repeats (fun _ -> let t = now () in ignore (f ()); now () -. t) in
  Array.sort Float.compare times; times.(repeats / 2) *. 1000.

let median_alloc f repeats =
  let bytes = Array.init repeats (fun _ ->
    let before = Gc.allocated_bytes () in ignore (f ()); Gc.allocated_bytes () -. before) in
  Array.sort Float.compare bytes; bytes.(repeats / 2)

let report_live stage =
  Gc.full_major ();
  Printf.printf "%s: live %d bytes\n%!" stage
    ((Gc.stat ()).live_words * (Sys.word_size / 8))

let cook_graph ~session (graph : Lower.graph) =
  let compiled = Result.get_ok (Procedural.Edit_graph.compile_node
    graph.network.geometry ~node_id:(Option.get graph.root)) in
  let context = Result.get_ok (Procedural.Context.create ()) in
  match Procedural.Session.cook session ~context compiled with
  | Ok output -> output
  | Error e -> failwith (Procedural.Diagnostic.error_to_string e)

(* Fingerprint authored payloads, excluding allocation identities and derived caches. *)
let cook_hash geometry =
  let open Rdk in
  let encode value = Marshal.to_string value [Marshal.No_sharing] in
  let attribute attribute =
    let storage = match Attribute.storage attribute with
      | Float values -> encode values | Int values -> encode values | Text values -> encode values
      | Int_array values -> encode (Packed.Int_array.Private.view values)
      | Float_array values -> encode (Packed.Float_array.Private.view values)
      | Float2 values -> let v = Packed.Float2.Private.view values in encode (v.x, v.y)
      | Float3 values -> let v = Packed.Float3.Private.view values in encode (v.x, v.y, v.z)
      | Float4 values -> let v = Packed.Float4.Private.view values in encode (v.x, v.y, v.z, v.w) in
    Attribute.owner attribute, Attribute.name attribute, Attribute.kind_name attribute, storage in
  let group group = Group.owner group, Group.name group,
    Array.init (Group.length group) (fun i -> Group.mem i group), Group.ordered_elements group in
  let edge_group group = Edge_group.name group,
    Array.init (Edge_group.length group) (fun i -> Edge_group.mem i group) in
  let p = Packed.Float3.Private.view (Geometry.positions geometry) in
  Digest.to_hex (Digest.string (encode (p.x, p.y, p.z,
    Topology.Private.view (Geometry.topology geometry),
    List.map attribute (Geometry.attributes geometry), List.map group (Geometry.groups geometry),
    List.map edge_group (Geometry.edge_groups geometry))))

module Functions = Hashtbl.Make (struct
  type t = Flow.Eval.fn
  let equal a b = a == b
  let hash = Hashtbl.hash
end)

let residual_stats (eval : Flow.Eval.t) =
  let seen = Hashtbl.create 64 in
  let functions = Functions.create 16 and captures = ref [] in
  let bindings = ref 0 and read = ref 0 and views = ref [] in
  let rec visit = function
    | Flow.Eval.Residual residual ->
        let id = Flow.Eval.Private.residual_id residual in
        if not (Hashtbl.mem seen id) then begin
          Hashtbl.add seen id ();
          let view = Flow.Eval.Private.residual_view residual in
          views := view :: !views;
          let names = Flow.Eval.Private.free_names view.term in
          bindings := !bindings + List.length view.bindings;
          read := !read + List.fold_left (fun n (name, _) -> n + if List.mem name names then 1 else 0) 0 view.bindings;
          List.iter (fun (_, value) -> visit value) view.bindings
        end
    | List values -> Array.iter visit values
    | Record fields | Struct (_, _, fields) -> List.iter (fun (_, value) -> visit value) fields
    | Fn fn when not (Functions.mem functions fn) ->
        Functions.add functions fn ();
        let bindings = Flow.Eval.Private.function_bindings fn in
        if bindings <> [] then captures := bindings :: !captures;
        List.iter (fun (_, value) -> visit value) bindings
    | _ -> () in
  List.iter (fun (_, value) -> visit value) eval.results;
  Array.iter (fun (node : Flow.Eval.node) -> List.iter (fun (_, value) -> visit value) node.args) eval.plan.nodes;
  List.iter (fun (_, records) -> List.iter (fun (_, value) -> visit value) records) eval.records;
  (* One serialization preserves shared captures and includes nested residuals
     and function closures. These bytes are measured, never loaded or exported. *)
  let bytes = if !views = [] then 0 else String.length (Marshal.to_string !views [Marshal.Closures]) in
  let closure_bindings = List.fold_left (fun count bindings -> count + List.length bindings) 0 !captures in
  let closure_bytes = if !captures = [] then 0 else String.length (Marshal.to_string !captures [Marshal.Closures]) in
  Hashtbl.length seen, !bindings, !read, bytes, Functions.length functions, closure_bindings, closure_bytes

let inspect_mode mode dir =
  let catalog = ok (Editor_document.Contexts.catalog ~version:Manifest.version factories) in
  print_endline (if mode = "--eval" then "fixture,eval_ms,eval_bytes" else if mode = "--nodes" then
    "fixture,node_id,operation,input_points,output_points,seconds,cache_hit" else
    "fixture,residuals,captured_bindings,read_bindings,view_bytes,functions,closure_bindings,closure_bytes");
  Sys.readdir dir |> Array.to_list |> List.sort String.compare |> List.iter (fun file ->
    if Filename.check_suffix file ".lisp" then begin
      let name = Filename.chop_suffix file ".lisp" in
      let forms = ok (Flow.Syntax.parse (In_channel.with_open_bin (Filename.concat dir file) In_channel.input_all)) in
      if mode = "--eval" then begin
        let workspace = match Flow.Workspace.check catalog forms with Some ws, _ -> ws | _ -> failwith "check" in
        ignore (ok (Flow.Eval.static workspace));
        Printf.printf "%s,%.6f,%.0f\n%!" name
          (median (fun () -> ok (Flow.Eval.static workspace)) 31)
          (median_alloc (fun () -> ok (Flow.Eval.static workspace)) 7)
      end else if mode = "--residuals" then begin
        let workspace = match Flow.Workspace.check catalog forms with Some ws, _ -> ws | _ -> failwith "check" in
        let count, captured, read, bytes, functions, closure_bindings, closure_bytes =
          residual_stats (ok (Flow.Eval.static ~record:true workspace)) in
        Printf.printf "%s,%d,%d,%d,%d,%d,%d,%d\n%!" name count captured read bytes functions closure_bindings closure_bytes
      end else begin
        let graph = List.hd (ok (Lower.workspace ~extra:Editor_document.Contexts.descriptors ~factories forms)).graphs in
        let session = Result.get_ok (Procedural.Session.create ~max_entries:512 ~max_payload_bytes:(256 * 1024 * 1024)) in
        Fun.protect ~finally:(fun () -> Procedural.Session.close session) (fun () ->
          ignore (cook_graph ~session graph);
          Procedural.Session.node_timings session |> List.iter (fun (sample : Procedural.Session.node_timing) ->
            Printf.printf "%s,%d,%s,%d,%d,%.9f,%b\n%!" name sample.node_id sample.operation
              sample.input_points sample.points sample.seconds sample.cache_hit))
      end
    end)

let branch_mode mode repeats =
  let placement=if Array.length Sys.argv>3 then Sys.argv.(3) else "auto" in
  if not(List.mem placement ["auto";"learned";"forced";"off"]) then
    invalid_arg "branch placement must be auto, learned, forced or off";
  let text = if mode = "--branches" then {|(workspace branches
    (graph g :context sop
      (let* [a (-> (sop/grid :columns 999 :rows 999 :size 100.0)
                   (sop/noise_displace :seed 1 :amplitude 0.8 :frequency 0.16)
                   (sop/noise_displace :seed 2 :amplitude 0.8 :frequency 0.16))
             b (-> (sop/grid :columns 999 :rows 999 :size 100.0)
                   (sop/noise_displace :seed 3 :amplitude 0.8 :frequency 0.16)
                   (sop/noise_displace :seed 4 :amplitude 0.8 :frequency 0.16))]
        (sop/merge a b))))|} else {|(workspace loops
    (graph g :context sop
      (let* [source (sop/merge (for [i (range 64)]
                      (sop/curve (list [(* i 2.0) 0.0 0.0] [(+ (* i 2.0) 1.0) 0.0 0.0]))))
             elements (for [piece (sop/piece_list source)]
               (-> (sop/copy_to_points (sop/grid :columns 124 :rows 199 :size 1.0) piece)
                   (sop/noise_displace :seed 42 :amplitude 0.8 :frequency 0.16)))]
        (sop/merge elements))))|} in
  let forms = ok (Flow.Syntax.parse text) in
  let graph = List.hd (ok (Lower.workspace ~extra:Editor_document.Contexts.descriptors ~factories forms)).graphs in
  let root = Result.get_ok (Procedural.Edit_graph.compile_node graph.network.geometry ~node_id:(Option.get graph.root)) in
  print_endline "fixture,placement,domains,repeats,points,median_s,caller_allocated_bytes,program_allocated_bytes,fanouts,hash";
  let expected = ref None in
  List.iter (fun domains ->
    let context = Result.get_ok (Procedural.Context.create ~domains ()) in
    Rays_math.Parallel.run ~domains (fun () -> ());
    let seconds = Array.make repeats 0. and allocated = Array.make repeats 0.
    and total_allocated=Array.make repeats 0. in
    let points = ref 0 and hash = ref "" and fanouts=ref 0 in
    for repeat = 0 to repeats - 1 do
      let session = Result.get_ok (Procedural.Session.create ~max_entries:512 ~max_payload_bytes:(256 * 1024 * 1024)) in
      Fun.protect ~finally:(fun () -> Procedural.Session.close session) (fun () ->
        Procedural.Session.Private.set_parallel_override session
          (match placement with "forced" -> Some true | "off" -> Some false | _ -> None);
        if placement="learned" then begin
          ignore(Result.get_ok(Procedural.Session.cook session ~context root));
          Procedural.Session.Private.clear_cache_keep_timings session
        end;
        let before_fanouts=Procedural.Session.Private.fanouts session in
        Gc.full_major ();
        let words (s:Gc.stat)=s.minor_words+.s.major_words-.s.promoted_words in
        let before_total=words(Gc.quick_stat()) in
        let before = Gc.allocated_bytes () and start = now () in
        let output = match Procedural.Session.cook session ~context root with
          | Ok output -> output | Error error -> failwith (Procedural.Diagnostic.error_to_string error) in
        seconds.(repeat) <- now () -. start;
        allocated.(repeat) <- Gc.allocated_bytes () -. before;
        Gc.minor();
        total_allocated.(repeat)<-(words(Gc.quick_stat())-.before_total)*.float(Sys.word_size/8);
        fanouts:=Procedural.Session.Private.fanouts session-before_fanouts;
        points := Rdk.Geometry.point_count (Result.get_ok (Procedural.Payload.geometry output.payload));
        hash := cook_hash (Result.get_ok (Procedural.Payload.geometry output.payload));
        if repeat=repeats-1 && Sys.getenv_opt "RAYS_BRANCH_NODE_TIMES"=Some "1" then
          List.iter(fun(sample:Procedural.Session.node_timing) ->
            Printf.eprintf "node,%s,%d,%d,%s,%d,%d,%.9f\n%!" placement domains sample.node_id
              sample.operation sample.input_points sample.points sample.seconds)
            (Procedural.Session.node_timings session);
        match !expected with None -> expected := Some !hash | Some prior -> assert (prior = !hash))
    done;
    Array.sort Float.compare seconds; Array.sort Float.compare allocated;
    Array.sort Float.compare total_allocated;
    Printf.printf "%s,%s,%d,%d,%d,%.9f,%.0f,%.0f,%d,%s\n%!" (String.sub mode 2 (String.length mode - 2))
      placement domains repeats !points seconds.(repeats / 2) allocated.(repeats / 2)
      total_allocated.(repeats/2) !fanouts !hash) [1; 8]

let image_render_mode () =
  let module Image=Runtime_resources.Image in
  let env name default=Option.fold ~none:default ~some:int_of_string(Sys.getenv_opt name)in
  let repeats=env "RAYS_IMAGE_RENDER_REPEATS" 7 and frames=env "RAYS_IMAGE_RENDER_FRAMES" 20
  and warmups=env "RAYS_IMAGE_RENDER_WARMUPS" 10 in
  let baseline=Sys.getenv_opt "RAYS_IMAGE_RENDER_BASELINE"=Some "1"in
  if repeats<7 || frames<2 || warmups<10 then
    invalid_arg "image/render needs seven trials, at least two frames and ten warmups";
  let allocation()=let s=Gc.stat()in
    (s.minor_words+.s.major_words-.s.promoted_words)*.float(Sys.word_size/8)in
  let mesh=Rays.Mesh.plane ~width:2. ~height:2.()in
  let camera=Rays.Camera.orthographic ~height:2. ~at:(Rays.Vec3.create 0. 0. 2.)
    ~target:Rays.Vec3.zero()in
  Printf.eprintf "image_render_counters,size,domains,phase,repetition,frames,targets_created,targets_destroyed,captures,canvas_readbacks,image_readbacks\n%!";
  List.iter(fun size->
    let text=Printf.sprintf "(workspace rendered
      (graph drawing :context draw
        (draw/merge (draw/background \"#102030\")
          (draw/rect [(* t %d) %d 0] [%d %d 0] :fill \"#a0b0c0\")))
      (graph img :context image (image/render (ref drawing) :width %d :height %d)))"
      (size/2)(size/4)(size/4)(size/4)size size in
    let doc=match Rays_editor.Workspace.load text with Ok doc->doc|Error ds->
      failwith(String.concat "; "(List.map Flow.Diagnostic.to_string ds))in
    let evaluated=Flow.Eval.static doc.checked |> ok in
    let value=List.assoc "img" evaluated.results and state=Flow.Eval.create_state()in
    Gc.full_major();
    let before=allocation()in let started=now()in
    let owner=Rays_editor.Editor3.create ~workspace:doc ~await:true ~domains:1
      ~prepare:(fun _ _->Ok()) ~scene3:(fun _ ()->Rays.Scene3.empty)() |> Result.get_ok in
    let canvas=Rays.Canvas.create ~width:size ~height:size |> Result.get_ok in
    let closed=ref false in
    let close()=if not !closed then begin closed:=true;
      Rays.Canvas.destroy canvas;Rays_editor.Editor3.close owner end in
    Fun.protect ~finally:close(fun()->
      let frame=ref 0 and last_live=ref(Frame_input.at_time 0.)in
      let source=ref None in
      let lookup_source()=
        let generation=Option.map Image.generation !source in
        Rays_editor.Editor3.Private.with_images ~plan:evaluated.plan ~state ~live: !last_live owner
          (fun ~image ~texture:_->
            let resource=ok(image value) |> Rays.Image.Private.resource in
            Option.iter(fun previous->assert(previous==resource);
              assert(generation=Some(Image.generation resource))) !source;
            source:=Some resource)in
      let counters()=
        let created,destroyed,captures,readbacks=Rays_editor.Editor3.Private.image_render_stats owner in
        created,destroyed,captures,readbacks,Option.fold ~none:0 ~some:Image.Private.readbacks !source in
      let report_counters phase trial frames (a,b,c,d,e) (v,w,x,y,z)=
        Printf.eprintf "image_render_counters,%d,1,%s,%d,%d,%d,%d,%d,%d,%d\n%!"
          size phase trial frames (v-a)(w-b)(x-c)(y-d)(z-e)in
      let render time=
        let live={(Frame_input.at_time time)with size=(size,size);frame= !frame}in
        last_live:=live;
        incr frame;
        Rays_editor.Editor3.Private.with_images ~plan:evaluated.plan ~state ~live owner
          (fun ~image:_ ~texture->
            let texture=ok(texture value) |> Rays.Scene3.textured ~filter:Nearest in
            let scene3=Rays.Scene3.create ~ambient:Rays.Color.white
              [Rays.Scene3.mesh ~material:(Rays.Material.matte Rays.Color.white)
                ~cull:Cull_none ~texture mesh]in
            Rays.Canvas.render canvas Rays.Scene.[clear Rays.Color.black;view3d ~camera scene3])in
      let hash()=let image=Rays.Canvas.to_image canvas |> Result.get_ok in
        Fun.protect ~finally:(fun()->Rays.Image.destroy image)(fun()->
          let bytes=Rays.Image.Private.pixels image |> Result.get_ok in
          Rays_editor.Editor3.Private.with_images ~plan:evaluated.plan ~state ~live: !last_live owner
            (fun ~image ~texture:_->let source=ok(image value)in
              let source_bytes=Rays.Image.Private.pixels source |> Result.get_ok in
              assert(source_bytes=bytes));
          Bytes.to_string bytes |> Digest.string |> Digest.to_hex)in
      let stats()=Rays.Canvas.Private.native_stats canvas in
      let report phase trial count seconds bytes uploaded hash=
        Printf.printf "image_render,%d,%d,1,%s,%d,%d,%.9f,%.0f,%.0f,%s\n%!"
          size (size*size) phase trial count (seconds/.float count) (bytes/.float count)
          (Int64.to_float uploaded/.float count) hash in
      render 0.;
      let elapsed=now()-.started in let bytes=allocation()-.before in
      lookup_source();
      let cold_counters=counters()in
      report_counters "cold_owner_frame" 0 1 (0,0,0,0,0) cold_counters;
      let cold_hash=hash()in
      report_counters "cold_hash" 0 1 cold_counters (counters());
      report "cold_owner_frame" 0 1 elapsed bytes (stats()).uploaded_bytes cold_hash;
      for warmup=0 to warmups-1 do render(float warmup/.float frames)done;
      let expected=ref None and times=Array.make repeats 0. in
      for trial=0 to repeats-1 do
        Gc.full_major();
        lookup_source();let initial_counters=counters()in
        let initial=stats()in let before=allocation()in let started=now()in
        for frame=0 to frames-1 do render(float frame/.float frames)done;
        let elapsed=now()-.started in let bytes=allocation()-.before in
        let final=stats()in
        assert(Int64.sub final.frames initial.frames=Int64.of_int frames);
        let uploaded=Int64.sub final.uploaded_bytes initial.uploaded_bytes in
        if baseline then assert(uploaded>=Int64.of_int(frames*size*size*4));
        lookup_source();let final_counters=counters()in
        if not baseline then begin
          assert(initial_counters=final_counters);assert(uploaded=0L)
        end;
        report_counters "warm_display" trial frames initial_counters final_counters;
        let hash=hash()in assert(hash<>cold_hash);
        report_counters "warm_hash" trial 1 final_counters (counters());
        (match !expected with None->expected:=Some hash|Some prior->assert(prior=hash));
        times.(trial)<-elapsed/.float frames;
        report "warm_display" trial frames elapsed bytes uploaded hash
      done;
      Gc.full_major();
      let before_counters=counters()in
      let before=allocation()in let started=now()in close();
      let elapsed=now()-.started in let bytes=allocation()-.before in
      let created,destroyed=Rays_editor.Editor3.Private.image_stats owner in assert(created=destroyed);
      let targets_created,targets_destroyed,_,_,_=counters()in assert(targets_created=targets_destroyed);
      report_counters "teardown" 0 1 before_counters (counters());
      report "teardown" 0 1 elapsed bytes 0L "";
      Array.sort Float.compare times;
      Printf.eprintf "image/render size=%d domains=1 trials=%d frames=%d warmups=%d median_ms=%.6f\n%!"
        size repeats frames warmups (times.(repeats/2)*.1000.))) [512;1024;2048]

let image_mode () =
  print_endline "name,size,pixels,domains,phase,repetition,frames,time_s,bytes_all_domains_per_frame,uploaded_bytes_per_frame,hash";
  let allocated_bytes () = let stats = Gc.quick_stat () in
    (stats.minor_words +. stats.major_words -. stats.promoted_words) *. float (Sys.word_size / 8) in
  List.iter (fun size ->
    let expected = ref None in
    List.iter (fun domains ->
      let node = Procedural.Image_nodes.noise ~width:size ~height:size ~frequency:0.12 ~seed:31 () in
      let context = Procedural.Context.create ~domains () |> Result.get_ok in
      Rays_math.Parallel.run ~domains (fun () -> ());
      let times = Array.make 7 0. and allocations = Array.make 7 0. and hash = ref "" in
      for sample = 0 to 6 do
        let session = Procedural.Session.create ~max_entries:0 ~max_payload_bytes:0 |> Result.get_ok in
        Fun.protect ~finally:(fun () -> Procedural.Session.close session) (fun () ->
          Gc.full_major ();
          let bytes = allocated_bytes () and started = now () in
          let output = Procedural.Session.cook session ~context node |> Result.get_ok in
          times.(sample) <- now () -. started;
          Gc.minor ();
          allocations.(sample) <- allocated_bytes () -. bytes;
          let image = Procedural.Payload.image output.payload |> Result.get_ok in
          hash := Digest.to_hex (Digest.string (Marshal.to_string
            (Procedural.Image.width image, Procedural.Image.height image, Procedural.Image.Private.storage image)
            [Marshal.No_sharing]));
          match !expected with None -> expected := Some !hash | Some prior -> assert (prior = !hash))
      done;
      Array.sort Float.compare times; Array.sort Float.compare allocations;
      Printf.printf "image_noise,%d,%d,%d,cpu_cook_median,0,1,%.9f,%.0f,0,%s\n%!"
        size (size*size) domains times.(3) allocations.(3) !hash) [1;8])
    [128;512;1024];
  image_render_mode()

let image_map_mode () =
  let env name default = Option.fold ~none:default ~some:int_of_string (Sys.getenv_opt name) in
  let domains = env "RAYS_BENCH_DOMAINS" 8 and repeats = env "RAYS_BENCH_REPEATS" 7 in
  if domains <= 0 || repeats < 7 then invalid_arg "image/map needs positive domains and at least seven repetitions";
  let fn producer =
    let forms = Flow.Syntax.parse ("(workspace benchmark (graph img :context image "^producer^"))") |> ok in
    let workspace = match Flow.Workspace.check {Flow.Check.version=1;kinds=[]} forms with
      | Some w, _ -> w | _, ds -> failwith (String.concat "; " (List.map Flow.Diagnostic.to_string ds)) in
    let evaluated = Flow.Eval.static workspace |> ok in
    let node = Array.find_opt (fun (n:Flow.Eval.node) -> n.kind="image/map") evaluated.plan.nodes |> Option.get in
    match List.assoc "function" node.args with Flow.Eval.Fn fn -> fn | _ -> assert false in
  let allocation stats = (stats.Gc.minor_words +. stats.major_words -. stats.promoted_words) *. float (Sys.word_size/8) in
  let host_ok = function Ok x -> x | Error d -> failwith (Procedural.Diagnostic.error_to_string d) in
  let cook node time =
    let session = Procedural.Session.create ~max_entries:0 ~max_payload_bytes:0 |> Result.get_ok in
    Fun.protect ~finally:(fun () -> Procedural.Session.close session) (fun () ->
      let context = Procedural.Context.create ~domains ~time () |> Result.get_ok in
      let output = Procedural.Session.cook session ~context node |> host_ok in
      Procedural.Payload.image output.payload |> host_ok) in
  let hash image = Procedural.Image.Private.rgba8 image |> Option.get
    |> Bytes.to_string |> Digest.string |> Digest.to_hex in
  print_endline "fixture,size,pixels,domains,phase,repetition,time_s,bytes_all_domains,hash";
  Rays_math.Parallel.run ~domains (fun () -> ());
  List.iter (fun (name, body) ->
    let fn = fn body in
    List.iter (fun size ->
      Gc.full_major ();
      let before = Gc.stat () and started = now () in
      let prepared = Image_kernel.prepare ~identity:(Procedural.Node.Private.fresh_id ())
        ~width:size ~height:size ~fn ~sources:[] [] |> ok in
      let node = Image_kernel.node prepared in
      let image = cook node 0. in
      let elapsed = now () -. started in
      let bytes = allocation (Gc.stat ()) -. allocation before in
      Printf.printf "%s,%d,%d,%d,cold_prepare_cook,0,%.9f,%.0f,%s\n%!"
        name size (size*size) domains elapsed bytes (hash image);
      ignore (cook node 0.125);
      let times = Array.make repeats 0. in
      for repetition=0 to repeats-1 do
        let time = if name="gradient" then 0. else float (repetition+1)/.60. in
        Gc.full_major ();
        let before = Gc.stat () and started = now () in
        let image = cook node time in
        let elapsed = now () -. started in
        let bytes = allocation (Gc.stat ()) -. allocation before in
        times.(repetition)<-elapsed;
        Printf.printf "%s,%d,%d,%d,warm_cook,%d,%.9f,%.0f,%s\n%!"
          name size (size*size) domains repetition elapsed bytes (hash image)
      done;
      Array.sort Float.compare times;
      Printf.eprintf "image/map %s size=%d domains=%d trials=%d median_ms=%.6f\n%!"
        name size domains repeats (times.(repeats/2)*.1000.)) [512;1024;2048])
    ["gradient","(image/map (fn [uv] [uv.x uv.y 0.5 1]))";
     "live_capture","(let* [bias (* t 0.25)] (image/map (fn [uv] [(+ uv.x bias) uv.y 0.5 1])))"]

let field_mode () =
  let env name default = Option.fold ~none:default ~some:int_of_string (Sys.getenv_opt name) in
  let domains = env "RAYS_BENCH_DOMAINS" 8 and repeats = env "RAYS_BENCH_REPEATS" 7 in
  if repeats < 7 then invalid_arg "field benchmark requires at least seven repetitions";
  let forms = Flow.Syntax.parse "(workspace field (graph g :context sop
    (sop/iso_surface :field (fn [p] (- (length p) 1.0))
      :resolution [64 64 64] :min [-2 -2 -2] :max [2 2 2] :iso 0.0)))" |> ok in
  let lowered = Lower.workspace ~factories forms |> ok in
  let graph = List.hd lowered.graphs in
  let node = Procedural.Edit_graph.compile_node graph.network.geometry
      ~node_id:(Option.get graph.root) |> Result.get_ok in
  let context = Procedural.Context.create ~domains ~grain:16384 () |> Result.get_ok in
  let cook () =
    let session = Procedural.Session.create ~max_entries:0 ~max_payload_bytes:0 |> Result.get_ok in
    Fun.protect ~finally:(fun () -> Procedural.Session.close session) (fun () ->
      let before = Gc.stat () in
      let started = now () in
      let output = match Procedural.Session.cook session ~context node with
        | Ok output -> output | Error d -> failwith (Procedural.Diagnostic.error_to_string d) in
      let seconds = now () -. started in
      let after = Gc.stat () in
      let geometry = Procedural.Payload.geometry output.payload |> Result.get_ok in
      let bytes = float (Sys.word_size / 8) in
      let promoted = (after.promoted_words -. before.promoted_words) *. bytes
      and major = (after.major_words -. before.major_words) *. bytes in
      geometry, seconds, (after.minor_words -. before.minor_words) *. bytes +. major -. promoted,
      promoted, major) in
  Rays_math.Parallel.run ~domains (fun () -> ());
  let warm, _, _, _, _ = cook () in
  let expected = cook_hash warm in
  Gc.full_major ();
  print_endline "fixture,domains,repetition,rx,ry,rz,cells,samples,seconds,allocated_bytes_all_domains,promoted_bytes,major_bytes,points,vertices,primitives,hash";
  for repetition = 0 to repeats - 1 do
    let geometry, seconds, allocated, promoted, major = cook () in
    let hash = cook_hash geometry in
    assert (hash = expected);
    Printf.printf "field_sphere,%d,%d,64,64,64,262144,274625,%.9f,%.0f,%.0f,%.0f,%d,%d,%d,%s\n%!"
      domains repetition seconds allocated promoted major
      (Rdk.Geometry.point_count geometry) (Rdk.Geometry.vertex_count geometry)
      (Rdk.Geometry.primitive_count geometry) hash
  done

let () =
  if Array.to_list Sys.argv = [Sys.argv.(0); "--fields"] then begin field_mode (); exit 0 end;
  if Array.to_list Sys.argv = [Sys.argv.(0); "--images"] then begin image_mode (); exit 0 end;
  if Array.to_list Sys.argv = [Sys.argv.(0); "--image-map"] then begin image_map_mode (); exit 0 end;
  if Array.length Sys.argv > 1 && List.mem Sys.argv.(1) ["--branches"; "--loops"] then begin
    branch_mode Sys.argv.(1) (if Array.length Sys.argv > 2 then int_of_string Sys.argv.(2) else 3);
    exit 0
  end;
  if Array.length Sys.argv > 1 && List.mem Sys.argv.(1) ["--nodes"; "--residuals"; "--eval"] then begin
    inspect_mode Sys.argv.(1) (if Array.length Sys.argv > 2 then Sys.argv.(2) else "_build/default/specification/workspace/cases");
    exit 0
  end
let report_approx () =
  let rec files directory = Array.to_list (Sys.readdir directory) |> List.sort String.compare
    |> List.concat_map (fun name -> let path = Filename.concat directory name in
      if Sys.is_directory path then files path else if Filename.check_suffix name ".rays" then [path] else []) in
  let custom = ["examples/sop_gallery/gallery.rays", "examples/sop_gallery/main.exe";
    "sketches/voxel_wall/sketch.rays", "sketches/voxel_wall/main.exe"] in
  let paths = files "examples" @ files "sketches" @ ["specification/pxui-kit/kit.rays"] in
  List.iter (fun path -> if not (List.mem_assoc path custom) then begin
    let text = In_channel.with_open_bin path In_channel.input_all in
    let document = match Result.bind (Rays_editor.Source.read_imports ~file:path text)
        (fun imports -> Rays_editor.Workspace.load ~imports text) with
      | Ok document -> document
      | Error ds -> failwith (path ^ ": " ^ String.concat "\n" (List.map Flow.Diagnostic.to_string ds)) in
    Workspace_parity.report_approx ~name:path document
  end) paths;
  List.iter (fun (_, executable) ->
    let executable = Filename.concat "_build/default" executable in
    let pid = Unix.create_process executable [|executable; "--approx"|] Unix.stdin Unix.stdout Unix.stderr in
    if snd (Unix.waitpid [] pid) <> Unix.WEXITED 0 then failwith (executable ^ ": approximate path check failed")) custom;
  Printf.printf "Approximate path audit: %d files, including actual custom catalogs\n%!" (List.length paths)

let () =
  if Array.length Sys.argv > 1 && Sys.argv.(1) = "--approx" then (report_approx (); exit 0);
  let dir = if Array.length Sys.argv > 1 then Sys.argv.(1) else "_build/default/specification/workspace/cases" in
  let repeats = if Array.length Sys.argv > 2 then int_of_string Sys.argv.(2) else 21 in
  Printf.printf "domains available %d, repeats %d (medians, ms)\n"
    (Domain.recommended_domain_count ()) repeats;
  Printf.printf "catalog: %d factories, %d fields\n%!" (List.length factories)
    (List.fold_left (fun count factory -> count + List.length
      (Procedural.Edit_graph.factory_fields factory)) 0 factories);
  report_live "before workspace catalog";
  let catalog = ok (Editor_document.Contexts.catalog ~version:Manifest.version factories) in
  report_live "after workspace catalog";
  Printf.printf "%-11s %8s %8s %8s %8s %8s %6s %10s %s\n" "fixture" "check" "eval" "lower" "cook" "l+cook" "nodes" "eval B" "cook hash";
  let forms name = ok (Flow.Syntax.parse
    (In_channel.with_open_bin (Filename.concat dir (name ^ ".lisp")) In_channel.input_all)) in
  let all = List.filter_map (fun f ->
    if Filename.check_suffix f ".lisp" then Some (Filename.chop_suffix f ".lisp") else None)
    (List.sort compare (Array.to_list (Sys.readdir dir))) in
  List.iter (fun name ->
    let forms = forms name in
    let check () = match Flow.Workspace.check catalog forms with
      | Some ws, _ -> ws | None, _ -> failwith "check" in
    let ws = check () in
    let t_check = median check repeats in
    let t_eval = median (fun () -> ok (Flow.Eval.static ws)) repeats in
    let eval_bytes = median_alloc (fun () -> ok (Flow.Eval.static ws)) repeats in
    let lower () = ok (Lower.workspace ~extra:Editor_document.Contexts.descriptors ~factories forms) in
    let t_total = median lower repeats in
    let lowered = lower () in
    let graph = List.hd lowered.graphs in
    let nodes = List.fold_left (fun n (g : Lower.graph) ->
      n + List.length (Procedural.Edit_graph.inspect g.network.geometry)) 0 lowered.graphs in
    let cook () =
      let session = Result.get_ok (Procedural.Session.create ~max_entries:512
        ~max_payload_bytes:(256 * 1024 * 1024)) in
      ignore (cook_graph ~session graph); Procedural.Session.close session in
    let t_cook = median cook (max 3 (repeats / 3)) in
    let both () = let l = lower () in
      let g = List.hd l.graphs in
      let session = Result.get_ok (Procedural.Session.create ~max_entries:512
        ~max_payload_bytes:(256 * 1024 * 1024)) in
      ignore (cook_graph ~session g); Procedural.Session.close session in
    let t_both = median both (max 3 (repeats / 3)) in
    let fingerprint () =
      let session = Result.get_ok (Procedural.Session.create ~max_entries:512
        ~max_payload_bytes:(256 * 1024 * 1024)) in
      Fun.protect ~finally:(fun () -> Procedural.Session.close session)
        (fun () -> cook_hash (Result.get_ok (Procedural.Payload.geometry (cook_graph ~session graph).payload))) in
    let hash = fingerprint () in
    assert (hash = fingerprint ());
    Printf.printf "%-11s %8.3f %8.3f %8.3f %8.3f %8.3f %6d %10.0f %s\n%!" name t_check t_eval
      (t_total -. t_check -. t_eval) t_cook t_both nodes eval_bytes hash) all;
  print_endline "\nSession capacity: cold cook, then the same cook again (warm), per max_entries";
  Printf.printf "%-11s %8s %10s %10s %8s %8s %10s\n" "fixture" "entries" "cold ms" "warm ms" "retained" "evicted" "payload MB";
  List.iter (fun name ->
    let graph = List.hd (ok (Lower.workspace ~extra:Editor_document.Contexts.descriptors ~factories (forms name))).graphs in
    List.iter (fun entries ->
      Gc.compact ();
      let session = Result.get_ok (Procedural.Session.create ~max_entries:entries
        ~max_payload_bytes:(256 * 1024 * 1024)) in
      let t = now () in ignore (cook_graph ~session graph);
      let cold = (now () -. t) *. 1000. in
      let warm = median (fun () -> cook_graph ~session graph) 7 in
      let stats = Procedural.Session.stats session in
      Gc.full_major ();
      let memory = Gc.stat () in
      let megabytes words = float words *. float (Sys.word_size / 8) /. 1048576. in
      Printf.printf "%-11s %8d %10.3f %10.3f %8d %8d %10.2f  (live %.2f MB, heap %.2f MB, peak %.2f MB)\n%!" name entries cold warm
        stats.retained_entries stats.evictions
        (float stats.retained_payload_bytes /. 1048576.)
        (megabytes memory.live_words) (megabytes memory.heap_words)
        (megabytes memory.top_heap_words);
      Procedural.Session.close session) [32; 512])
    ["bloom"; "sunflower"; "wave"; "tree"]
