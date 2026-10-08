let array = function Flow.Eval.Float_array values | Vec3_array values -> values | _ -> assert false
let () = match Rays_execution.acquire_gpu () with
  | Error error -> Format.eprintf "%a@." Rays_execution.pp_error error; exit 2
  | Ok gpu -> Fun.protect ~finally:(fun () -> Rays_execution.release_gpu gpu) (fun () ->
      if not (Ogpu.Caps.has (Ogpu.Backend.capabilities (Rays_execution.gpu_device gpu)) Compute_pipeline) then
        print_endline "SKIP: backend lacks Compute_pipeline"
      else begin
        let pipelines=Flow_gpu.Pipelines.create ~clock:Unix.gettimeofday (Rays_execution.gpu_device gpu) in
        Fun.protect ~finally:(fun () -> Flow_gpu.Pipelines.close pipelines) (fun () ->
          List.iter (fun count -> List.iter (fun (name,program) ->
            let msl=Test_program.ok (Flow_gpu.Emit.kernel program) in
            let compiled=Test_program.ok (Flow_gpu.Pipelines.get pipelines msl) in
            assert (Test_program.ok (Flow_gpu.Pipelines.get pipelines msl)==compiled);
            let runner=Flow_gpu.Run.create gpu pipelines msl in
            Fun.protect ~finally:(fun () -> Flow_gpu.Run.close runner) (fun () ->
              let live=Frame_input.at_time 1. in
              let values=Test_program.ok (Flow_ir.Packed.Private.prepare program ~live) in
              let output=Test_program.ok (Flow_gpu.Run.dispatch runner values) in
              let actual=array (Test_program.ok (Flow_gpu.Run.readback output))
              and expected=array (Test_program.ok (Flow_ir.Packed.force program ~live)) in
              let maximum=ref 0. in
              Array.iteri (fun index value -> maximum:=max !maximum (abs_float(value-.expected.(index)))) actual;
              Printf.printf "%s,%d,max_abs_error=%.9g\n%!" name count !maximum;
              if name<>"noise" then assert (!maximum=0.);
              let created=Flow_gpu.Run.Private.buffer_creations runner in
              ignore (Test_program.ok (Flow_gpu.Run.dispatch runner values));
              assert (Flow_gpu.Run.Private.buffer_creations runner=created)))
            (Test_program.fixtures count)) [1024;65536]);
        (* Native noise tolerance must come from the measured row, not a guess. *)
        failwith "Noise GPU tolerance qualification remains required: record native max_abs_error before accepting it."
      end)
