(* Run unchanged for the before/after comparison; prepare copies 10k points
   for each of two objects while only object 1's transform changes. *)
open Prismel
open Procedural
module Cook = Prismel_editor.Private.Cook

let frame : Frame.t = {
  width = 100; height = 100; size = 100, 100;
  drawable_width = 100; drawable_height = 100; drawable_size = 100, 100;
  pixel_scale = 1., 1.; time = 0.; dt = 0.; fps = 60.; count = 0;
  mouse = 0., 0.; mouse_delta = 0., 0.; keys = []; mouse_buttons = []; events = [] }

let measure () =
  let prepares = Atomic.make 0 and prepare_bytes = Atomic.make 0. in
  let prepare _ (output : Session.output) =
    let before = Gc.allocated_bytes () in
    let positions = Pdk.Geometry.positions output.geometry in
    let packed = Array.init (Pdk.Packed.Float3.length positions * 3) (fun component ->
      let x, y, z = Pdk.Packed.Float3.get positions (component / 3) in
      match component mod 3 with 0 -> x | 1 -> y | _ -> z) in
    Atomic.set prepare_bytes (Atomic.get prepare_bytes +. Gc.allocated_bytes () -. before);
    Atomic.incr prepares;
    Ok packed in
  let cook = ref (Cook.create ~prepare ~seed:0L ~grain:256 ~domains:1
    ~max_entries:16 ~max_payload_bytes:(64 * 1024 * 1024) () |> Result.get_ok) in
  Fun.protect ~finally:(fun () -> Cook.close !cook) (fun () ->
    let timeline = fst (Sketch_support.Timeline.stop (Sketch_support.Timeline.create ())) in
    let source = Sop.grid ~columns:100 ~rows:100 ~size:10. () in
    let network id graph = id, Edit_graph.of_graph graph, Node.id graph in
    let still = network 2 source in
    let step objects =
      let update = Cook.update !cook ~settings:Prismel_editor.Settings.none ~objects
        ~edit_error:None ~effects:Parameter.no_effects ~timeline_changes:[]
        ~timeline ~frame ~frame_request:None in
      cook := update.cook; update.prepared_changed in
    let complete objects =
      let deadline = Unix.gettimeofday () +. 10. in
      let rec poll () =
        if step objects then ()
        else if Unix.gettimeofday () >= deadline then failwith "cook benchmark timeout"
        else (Unix.sleepf 0.0001; poll ()) in
      poll () in
    complete [network 1 source; still];
    Atomic.set prepares 0; Atomic.set prepare_bytes 0.; Gc.full_major ();
    let before = Gc.allocated_bytes () and started = Unix.gettimeofday () in
    for iteration = 1 to 100 do
      let changed = Sop.transform (Mat4.translation (Vec3.create (float iteration) 0. 0.)) source in
      complete [network 1 changed; still]
    done;
    Printf.printf "2,10000,1,100,%.6f,%.0f,%d,%.0f\n%!"
      (Unix.gettimeofday () -. started) (Gc.allocated_bytes () -. before)
      (Atomic.get prepares) (Atomic.get prepare_bytes))

let () =
  print_endline "objects,points_per_object,kernel_domains,edits,elapsed_s,host_allocated_bytes,prepares,prepare_allocated_bytes";
  for _ = 1 to 3 do measure () done
