let ok = function Ok value -> value | Error error -> failwith error
let error = function Error _ -> () | Ok _ -> failwith "expected FunctionHandle rejection"

let () =
  let open Binding_function_handle_safe_package in
  validate_handoff ();
  let owner = { token = 7; destroyed = false } in
  let source = Bytes.of_string "kernel_main" in
  let handle = ok (create ~native_kind:Function_handle ~device:owner ~function_type:Kernel
    ~gpu_resource_id:Int64.min_int ~name:(Bytes.unsafe_to_string source)) in
  Bytes.fill source 0 (Bytes.length source) 'x';
  let retained_owner = ok (device handle) in
  if retained_owner.token <> owner.token || ok (function_type handle) <> Kernel
     || ok (gpu_resource_id handle) <> Int64.min_int || ok (name handle) <> "kernel_main"
  then failwith "function-handle scalar/identity snapshot";
  error (create ~native_kind:Other_handle ~device:owner ~function_type:Kernel ~gpu_resource_id:0L ~name:"x");
  error (create ~native_kind:Function_handle ~device:{ owner with destroyed = true }
    ~function_type:Kernel ~gpu_resource_id:0L ~name:"x");
  error (create ~native_kind:Function_handle ~device:owner ~function_type:Kernel
    ~gpu_resource_id:0L ~name:(String.make 1 (Char.chr 0xc0)));
  destroy handle; destroy handle;
  error (device handle); error (function_type handle); error (gpu_resource_id handle); error (name handle);
  Printf.printf
    "FunctionHandle safe package: callable8 scalar4/ownership4 kind/device/UTF-8/lifetime/resource-ID passed\n%!"
