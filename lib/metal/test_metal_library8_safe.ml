open Metal

let get = function
  | Ok value -> value
  | Error error -> failwith (Format.asprintf "%a" pp_error error)

let () =
  match Device.system_default () with
  | Error _ -> print_endline "library8 safe: skipped"
  | Ok device ->
      let source =
        "#include <metal_stdlib>\nusing namespace metal;\n" ^
        "struct V { float4 p [[attribute(0)]]; };\n" ^
        "vertex float4 lib8_vertex(V in [[stage_in]]) { return in.p; }\n" ^
        "kernel void lib8_compute(device uint *out [[buffer(0)]]) { out[0]=8; }\n"
      in
      let library = get (Library.compile_source ~device source) in
      let vertex = get (Function.find ~library "lib8_vertex") in
      let metadata = get (Library_metadata.attributes vertex ~vertex:false) in
      let attribute =
        match List.find_opt
          (fun (value:Library_metadata.attribute) -> value.index = 0L) metadata with
        | Some value -> value | None -> failwith "stage input attribute absent"
      in
      if attribute.name <> Some "p" || not attribute.active then
        failwith "copied stage attribute metadata mismatch";
      get (Function.destroy vertex);
      if attribute.name <> Some "p" || attribute.index <> 0L then
        failwith "attribute snapshot depended on destroyed native owner";
      (match Library_metadata.function_reflection ~library "lib8_compute" with
       | Ok reflection when reflection.bindings <> [] -> ()
       | Ok _ -> failwith "macOS 26 function reflection was empty"
       | Error error when error.kind = Unsupported -> ()
       | Error error -> failwith (Format.asprintf "%a" pp_error error));
      let task = get (Library_function_task.start ~library Descriptor "lib8_compute") in
      get (Library_function_task.cancel task);
      get (Library_function_task.cancel task);
      (match Library_function_task.poll task with
       | Error error when error.kind = Destroyed -> ()
       | Error error -> failwith (Format.asprintf "%a" pp_error error)
       | Ok _ -> failwith "cancelled library task remained pollable");
      get (Library.destroy library);
      get (Device.destroy device);
      print_endline "library8 safe: copied metadata/capability/cancel lifecycle ok"
