open Metal

let get = function
  | Ok value -> value
  | Error error -> failwith (Format.asprintf "%a" pp_error error)

let expect kind = function
  | Error error when error.kind = kind -> ()
  | Error error -> failwith (Format.asprintf "unexpected error: %a" pp_error error)
  | Ok _ -> failwith "expected function-descriptor rejection"

let () =
  match Device.system_default () with
  | Error _ -> print_endline "function-descriptor4 safe: skipped"
  | Ok device ->
      let source =
        "#include <metal_stdlib>\nusing namespace metal;\n" ^
        "kernel void descriptor_kernel(device uint *out [[buffer(0)]]) { out[0] = 4; }\n"
      in
      let library = get (Library.compile_source ~device source) in
      let archive = get (Binary_archive.create device) in
      let archives = ref [archive] in
      let descriptor =
        get (Function.descriptor ~binary_archives:!archives ~constants:[]
               "descriptor_kernel")
      in
      archives := [];
      if Function.descriptor_name descriptor <> "descriptor_kernel"
         || Function.descriptor_is_intersection descriptor
         || List.length (Function.descriptor_binary_archives descriptor) <> 1
      then failwith "function descriptor did not retain its copied archive list";
      expect Parent_has_dependents (Binary_archive.destroy archive);
      let function_ = get (Function.create ~library descriptor) in
      (match get (Function.kind function_) with
       | Function.Kernel -> ()
       | _ -> failwith "descriptor-created function changed stage");
      get (Function.destroy function_);
      get (Function.destroy_descriptor descriptor);
      if not (Function.descriptor_destroyed descriptor) then
        failwith "destroyed descriptor remained live";
      expect Destroyed (Function.create ~library descriptor);
      get (Binary_archive.destroy archive);
      let intersection =
        get (Function.descriptor ~intersection:true ~constants:[]
               "intersection_name")
      in
      if not (Function.descriptor_is_intersection intersection)
         || Function.descriptor_binary_archives intersection <> []
      then failwith "intersection descriptor metadata mismatch";
      get (Function.destroy_descriptor intersection);
      get (Library.destroy library);
      get (Device.destroy device);
      print_endline "function-descriptor4 safe: archive ownership/create/intersection ok"
