let array = function Flow.Eval.Float_array values | Vec2_array values | Vec3_array values
  | Vec4_array values -> values | _ -> assert false
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
              let actual_value=Test_program.ok (Flow_gpu.Run.readback output)
              and expected_value=Test_program.ok (Flow_ir.Packed.force program ~live) in
              assert (Flow.Value.ty_of actual_value = Flow.Value.ty_of expected_value);
              let actual=array actual_value and expected=array expected_value in
              let maximum=ref 0. in
              Array.iteri (fun index value -> maximum:=max !maximum (abs_float(value-.expected.(index)))) actual;
              Printf.printf "%s,%d,max_abs_error=%.9g\n%!" name count !maximum;
              (* Native rows, Apple M1 (performance-log "P5 native calibration"):
                 noise 8.82e-7 at 1,024 and 9.89e-5 at 65,536 elements. *)
              if name<>"noise" then assert (!maximum=0.) else assert (!maximum<=2e-4);
              let created=Flow_gpu.Run.Private.buffer_creations runner in
              ignore (Test_program.ok (Flow_gpu.Run.dispatch runner values));
              assert (Flow_gpu.Run.Private.buffer_creations runner=created)))
            (Test_program.fixtures count @ Test_program.vector_fixtures count)) [1024;65536];
        let hidden=Test_program.compile
          "(map (fn [x] (if (> (+ x t) 0) 0 (* (* (+ x t) 1e20) (* (+ x t) 1e20)))) (array/range 1024))"in
        let msl=Test_program.ok(Flow_gpu.Emit.kernel hidden)in
        let runner=Flow_gpu.Run.create gpu pipelines msl in
        Fun.protect ~finally:(fun()->Flow_gpu.Run.close runner)(fun()->
          let live=Frame_input.at_time 1. in
          assert(Array.for_all((=)0.)(array(Test_program.ok(Flow_ir.Packed.force hidden ~live))));
          let inputs=Test_program.ok(Flow_ir.Packed.Private.prepare hidden ~live)in
          assert(match Flow_gpu.Run.dispatch runner inputs with
            |Error diagnostic->diagnostic.Flow.Diagnostic.code="E_KERNEL"|Ok _->false)));
        print_endline "GPU run: emitted kernels match the CPU tier within the recorded native noise tolerance"
      end)
