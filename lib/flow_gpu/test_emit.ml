let () =
  List.iter (fun name ->
    assert (Flow.Op.find ~extra:Flow_ir.Operators.all name Flow.Context.value<>None)) Flow_gpu.Emit.names;
  assert (Flow_gpu.Emit.names=Flow.Packed_ops.names);
  List.iter (fun body ->
    let program = Test_program.compile ("(map (fn [x] " ^ body ^ ") (array/range 1024))") in
    ignore (Test_program.ok (Flow_gpu.Emit.kernel program));
    List.iter (fun domains -> Rays_math.Parallel.run ~domains (fun () ->
      List.iter (fun time ->
        let live = Frame_input.at_time time in
        assert (Marshal.to_string (Flow_ir.Packed.force program ~live) [Marshal.No_sharing]
          = Marshal.to_string (Flow_ir.Packed.reference program ~live) [Marshal.No_sharing]))
        [0.; 0.125; 1.25; 7.])) [1;8])
    ["(cond (< x t) (+ x 1) (> x 5) (- x 1) :else (* x t))";
     "(case x 0 t 1 (+ t 1) :else (+ x t))";
     "(case x false t true (+ x t) :else 0)";
     "(case (> x t) 0 t 2 (+ x t) :else 0)"];
  List.iter (fun name ->
    let body=match name with
      | "noise3" -> "(noise3 [x t 0])"
      | "length" -> "(length [x t 0])"
      | "and" | "or" -> "(if (" ^ name ^ " (> x t) (< x 8)) x t)"
      | "not" -> "(if (not (> x t)) x t)"
      | "<" | "<=" | ">" | ">=" | "=" -> "(if (" ^ name ^ " x t) x t)"
      | name when Flow.Packed_ops.unary name<>None -> "(" ^ name ^ " (+ x t))"
      | name -> "(" ^ name ^ " x t)" in
    ignore (Test_program.ok (Flow_gpu.Emit.kernel
      (Test_program.compile ("(map (fn [x] " ^ body ^ ") (array/range 1024))")))))
    Flow_gpu.Emit.names;
  let writing=Array.to_list Sys.argv=[Sys.argv.(0);"--write-goldens"] in
  List.iter (fun (name,program) ->
    let msl=Test_program.ok (Flow_gpu.Emit.kernel program) in
    let path="goldens/" ^ name ^ ".metal" in
    if writing then Out_channel.with_open_bin path (fun channel -> output_string channel msl.source)
    else assert (In_channel.with_open_bin path In_channel.input_all=msl.source);
    assert (List.length msl.interface=Array.length msl.input_widths+3+
      (if msl.table_seeds=[||] then 0 else 1));
    assert (Ogpu.Shader.validate_bindings msl.interface=Ok ());
    let inputs=Test_program.ok (Flow_ir.Packed.Private.prepare program ~live:(Frame_input.at_time 1.)) in
    assert (inputs.count=1024);
    assert (Array.length inputs.frame=Array.length (Flow_ir.Packed.Private.view program).code))
    (Test_program.fixtures 1024);
  List.iter (fun source -> assert (Result.is_error (Flow_gpu.Emit.kernel (Test_program.compile source))))
    ["(sum [x (array/range 1024)] (+ x t))";
     "(for [x (array/range 32) y (array/range 32)] (+ (+ x y) t))";
     "(for [x (array/range 1024)] :skip [0] (+ x t))"];
  let uniform=Test_program.ok(Flow_gpu.Emit.kernel(Test_program.compile "(map (fn [x] t) (array/range 1024))"))in
  assert(List.length uniform.interface=3 && not(List.exists(fun(binding:Ogpu.Shader.binding)->binding.binding=0)uniform.interface));
  let hidden=Test_program.ok(Flow_gpu.Emit.kernel(Test_program.compile
    "(map (fn [x] (if (> x t) 0.0 (* x x))) (array/range 1024))"))in
  let lines=String.split_on_char '\n' hidden.source in
  List.iteri(fun index line->if String.starts_with ~prefix:"  float r" line then
    let slot=Scanf.sscanf line "  float r%d=" Fun.id in
    assert(List.nth lines(index+1)=Printf.sprintf
      "  if(!isfinite(r%d)) atomic_store_explicit(status,1u,memory_order_relaxed);" slot))lines;
  print_endline "GPU emitter: shared operations, golden arithmetic/select/seeded fBm and typed ordered-loop refusals passed"
