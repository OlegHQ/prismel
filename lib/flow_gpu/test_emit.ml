let () =
  List.iter (fun name ->
    assert (Flow.Op.find ~extra:Flow_ir.Operators.all name Flow.Context.value<>None)) Flow_gpu.Emit.names;
  assert (Flow_gpu.Emit.names=Flow.Packed_ops.names);
  List.iter (fun name ->
    let body=match name with
      | "noise3" -> "(noise3 [x t 0])"
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
    assert (List.length msl.interface=Array.length msl.input_widths+2+
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
  print_endline "GPU emitter: shared operations, golden arithmetic/select/seeded fBm and typed ordered-loop refusals passed"
