open Ogpu.Types

let get = function Ok value -> value | Error error -> failwith (Ogpu.Error.to_string error)
let get_metal = function Ok value -> value | Error error -> failwith error.Metal.message

let () =
  let before = get_metal (Metal.Release_queue.stats ()) in
  match Runtime_next.create ~width:4 ~height:4 () with
  | Error _ -> print_endline "runtime-next scene2 retained argument: skipped (no Metal device)"
  | Ok runtime ->
      let vertices = Bytes.make (3 * 68) '\000' in
      let indices = Bytes.make 12 '\000' in
      let put index x y u v =
        let offset = index * 68 in
        Bytes.set_int64_le vertices offset (Int64.bits_of_float x);
        Bytes.set_int64_le vertices (offset + 8) (Int64.bits_of_float y);
        Bytes.set_int32_le vertices (offset + 48) Int32.minus_one;
        Bytes.set_int64_le vertices (offset + 52) (Int64.bits_of_float u);
        Bytes.set_int64_le vertices (offset + 60) (Int64.bits_of_float v)
      in
      put 0 (-1.) (-1.) 0. 0.;
      put 1 3. (-1.) 1. 0.;
      put 2 (-1.) 3. 0. 1.;
      Bytes.set_int32_le indices 4 1l;
      Bytes.set_int32_le indices 8 2l;
      let mesh : Scene_execution.mesh =
        { key = "scene2-retained-argument"; vertices; vertex_count = 3; indices; index_count = 3 }
      in
      let state : Scene_execution.state =
        { viewport = 0, 0, 4, 4; scissor = 0, 0, 4, 4;
          cull = Ogpu.Render_pass.Cull_none; depth_compare = Ogpu.Render_pass.Always;
          depth_write = false; depth_load = Ogpu.Render_pass.Load; depth_clear = 1.;
          transform_uniforms = None; stencil_state = None;
          stencil_load = Ogpu.Render_pass.Load; stencil_clear = 0 }
      in
      let sampler : sampler_descriptor =
        { label = Some "scene2-retained-nearest"; min_filter = Nearest; mag_filter = Nearest;
          mip_filter = No_mip; address_u = Clamp_to_edge; address_v = Clamp_to_edge;
          lod_min = 0.; lod_max = 0.; max_anisotropy = 1 }
      in
      let texture : Scene_execution.sampled_texture =
        { key = "scene2-retained-pixel";
          levels = [| { width = 1; height = 1; bytes = Bytes.of_string "\x11\x22\x33\xff" } |];
          sampler }
      in
      let draw = Scene_execution.Scene2_textured, Ogpu.Pipeline.Replace, Some texture,
        None, 1, { Scene_execution.mesh; state } in
      let first_uploaded = ref None in
      for frame = 1 to 20 do
        if not (get (Runtime_next.render_sampled_resources runtime [draw])) then
          failwith "scene2 retained argument frame was not presented";
        let pixels = get (Runtime_next.read_pixels runtime ~bytes_per_row:16) in
        if Bytes.sub pixels 0 4 <> Bytes.of_string "\x11\x22\x33\xff" then
          failwith "scene2 retained argument exact pixel mismatch";
        if frame = 1 then first_uploaded := Some (Runtime_next.stats runtime).uploaded_bytes
      done;
      let uploaded = (Runtime_next.stats runtime).uploaded_bytes in
      if uploaded <= 0L then failwith "scene2 retained argument fixture was not uploaded";
      if Some uploaded <> !first_uploaded then
        failwith "scene2 retained argument stable draw was re-expanded or re-uploaded";
      let retained = Runtime_next.stats runtime in
      if retained.retained_plan_builds <> 1L || retained.retained_plan_misses <> 1L
         || retained.retained_plan_hits <> 19L || retained.retained_plan_executions <> 20L
         || retained.retained_plan_evictions <> 0L || retained.retained_plan_entries <> 1
         || retained.retained_plan_capacity <> 256 then
        failwith "scene2 retained argument counters are not exact";
      let settled_release = ref None in
      let peak_live = ref 0 in
      let peak_pending = ref 0 in
      for frame = 1 to 1000 do
        let rgba = if frame land 1 = 0 then "\x11\x22\x33\xff" else "\x99\x55\x22\xff" in
        let changing : Scene_execution.sampled_texture =
          { key = "image:managed-churn:1";
            levels = [| { width = 1; height = 1; bytes = Bytes.of_string rgba } |];
            sampler }
        in
        let changing_draw = Scene_execution.Scene2_textured, Ogpu.Pipeline.Replace,
          Some changing, None, 1, { Scene_execution.mesh; state } in
        if not (get (Runtime_next.render_sampled_resources runtime [changing_draw])) then
          failwith "managed-image churn frame was not presented";
        let pixels = get (Runtime_next.read_pixels runtime ~bytes_per_row:16) in
        if Bytes.sub pixels 0 4 <> Bytes.of_string rgba then
          failwith "managed-image churn exact pixel mismatch";
        if frame = 1 || frame mod 100 = 0 then begin
          let current = get_metal (Metal.Release_queue.stats ()) in
          if frame = 1 then settled_release := Some (current.live_handles, current.pending);
          peak_live := max !peak_live current.live_handles;
          peak_pending := max !peak_pending current.pending
        end
      done;
      let churn = Runtime_next.stats runtime in
      if churn.retained_plan_builds <> 2L || churn.retained_plan_misses <> 2L
         || churn.retained_plan_hits <> 1018L || churn.retained_plan_executions <> 1020L
         || churn.retained_plan_evictions <> 0L || churn.retained_plan_entries <> 2 then
        failwith "managed-image churn rebuilt its retained render plan";
      if Int64.sub churn.uploaded_bytes uploaded <> 256000L then
        failwith "managed-image churn upload cardinality is not exact";
      let settled_live, settled_pending = Option.get !settled_release in
      if !peak_live <> settled_live || !peak_pending <> settled_pending then
        failwith "managed-image churn grew Metal release state";
      let plain_mesh = { mesh with Scene_execution.key = "scene2-retained-plain" } in
      let plain_draw = Scene_execution.Scene2, Ogpu.Pipeline.Replace, None,
        None, 1, { Scene_execution.mesh = plain_mesh; state } in
      let textured_draw = Scene_execution.Scene2_textured, Ogpu.Pipeline.Alpha,
        Some texture, None, 1, { Scene_execution.mesh; state } in
      for _frame = 1 to 600 do
        if not (get (Runtime_next.render_sampled_resources runtime
          [plain_draw; textured_draw])) then
          failwith "mixed canonical Scene2 frame was not presented"
      done;
      let pixels = get (Runtime_next.read_pixels runtime ~bytes_per_row:16) in
      if Bytes.sub pixels 0 4 <> Bytes.of_string "\x11\x22\x33\xff" then
        failwith "mixed canonical Scene2 exact pixel mismatch";
      let mixed = Runtime_next.stats runtime in
      if mixed.retained_plan_builds <> 3L || mixed.retained_plan_misses <> 3L
         || mixed.retained_plan_hits <> 1617L || mixed.retained_plan_executions <> 1620L
         || mixed.retained_plan_evictions <> 0L || mixed.retained_plan_entries <> 3 then
        failwith "mixed plain/textured Scene2 did not retain one stable plan";
      for frame = 0 to 159 do
        let identity = frame mod 80 in
        let mesh =
          { mesh with
            Scene_execution.key = Printf.sprintf "scene2-plan-churn-%02d" identity }
        in
        if not (get (Runtime_next.render runtime [{ Scene_execution.mesh; state }])) then
          failwith "80-identity retained-plan frame was not presented"
      done;
      let cycled = Runtime_next.stats runtime in
      if cycled.retained_plan_builds <> Int64.add mixed.retained_plan_builds 80L
         || cycled.retained_plan_misses <> Int64.add mixed.retained_plan_misses 80L
         || cycled.retained_plan_hits <> Int64.add mixed.retained_plan_hits 80L
         || cycled.retained_plan_executions <> Int64.add mixed.retained_plan_executions 160L
         || cycled.retained_plan_evictions <> mixed.retained_plan_evictions
         || cycled.retained_plan_entries <> mixed.retained_plan_entries + 80
         || cycled.retained_plan_capacity <> 256 then
        failwith "80 mesh identities thrashed the aligned retained-plan cache";
      get (Runtime_next.destroy runtime);
      ignore (get_metal (Metal.Release_queue.drain ()));
      let after = get_metal (Metal.Release_queue.stats ()) in
      if after.live_handles <> before.live_handles then
        failwith "scene2 retained argument live-handle delta";
      print_endline "runtime-next scene2 retained argument: indexed expansion + 1000 managed-image generations + 600 mixed plain/textured frames, exact pixels, bounded release state, zero delta"
