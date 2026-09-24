open Metal

let get = function
  | Ok value -> value
  | Error error -> failwith (Format.asprintf "%a" pp_error error)

let expect_kind kind = function
  | Error error when error.kind = kind -> ()
  | Error error -> failwith (Format.asprintf "unexpected error: %a" pp_error error)
  | Ok _ -> failwith "expected function-constant rejection"

let execute device function_ =
  let queue = get (Command_queue.create device) in
  let pipeline = get (Compute_pipeline.create function_) in
  let output = get (Buffer.create ~device ~length:4L ~storage:Buffer.Shared ()) in
  let command = get (Command_buffer.create queue ()) in
  let encoder = get (Compute_encoder.create command) in
  get (Compute_encoder.set_pipeline encoder pipeline);
  get (Compute_encoder.set_buffers encoder ~start:0 [Some output,0L,4L]);
  get (Compute_encoder.dispatch_threadgroups encoder ~threadgroups:(1,1,1)
         ~threadgroup:(1,1,1));
  get (Compute_encoder.end_encoding encoder);
  get (Command_buffer.commit command);
  get (Command_buffer.wait_until_completed command);
  let result = Bytes.get_int32_le (get (Buffer.read_bytes output ~offset:0L ~length:4)) 0 in
  get (Command_buffer.destroy command);
  get (Buffer.destroy output);
  get (Compute_pipeline.destroy pipeline);
  get (Command_queue.destroy queue);
  result

let () =
  match Device.system_default () with
  | Error _ -> print_endline "metal function constants safe: skipped"
  | Ok device ->
      let source =
        "constant int first [[function_constant(0)]];\n" ^
        "constant int second [[function_constant(1)]];\n" ^
        "kernel void constant_copy(device int *out [[buffer(0)]]) {\n" ^
        "  out[0] = first * 100 + second;\n}\n"
      in
      let library = get (Library.compile_source ~device source) in
      let values = get (Function.Constant_values.create ()) in
      let payload = Bytes.make 8 '\000' in
      Bytes.set_int32_le payload 0 7l;
      Bytes.set_int32_le payload 4 11l;
      expect_kind Invalid_argument
        (Function.Constant_values.set_index values ~scalar:Int32 ~index:0L
           (Bytes.make 3 '\000'));
      expect_kind Invalid_argument
        (Function.Constant_values.set_range values ~scalar:Int32 ~start:0L
           ~count:2L (Bytes.make 4 '\000'));
      get (Function.Constant_values.set_range values ~scalar:Int32 ~start:0L
             ~count:2L payload);
      Bytes.fill payload 0 (Bytes.length payload) '\255';
      let function_ =
        get (Function.specialize_with_values ~library values "constant_copy")
      in
      (match get (Function.kind function_) with
       | Function.Kernel -> ()
       | _ -> failwith "specialized function changed stage");
      if execute device function_ <> 711l then
        failwith "function constants did not copy the original typed bytes";
      get (Function.destroy function_);
      get (Function.Constant_values.reset values);
      let reset_function =
        get (Function.specialize_with_values ~library values "constant_copy")
      in
      if execute device reset_function <> 0l then
        failwith "reset retained stale function constant bytes";
      get (Function.destroy reset_function);
      get (Function.Constant_values.destroy values);
      get (Library.destroy library);
      get (Device.destroy device);
      print_endline "metal function constants safe: ok"
