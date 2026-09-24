open Metal

let get = function
  | Ok value -> value
  | Error error -> failwith (Format.asprintf "%a" pp_error error)

let member name members =
  List.find_opt (fun (value : Reflection.member) -> value.name = name) members

let () =
  match Device.system_default () with
  | Error _ -> print_endline "argument8 safe: skipped"
  | Ok device ->
      let source =
        "#include <metal_stdlib>\nusing namespace metal;\n" ^
        "struct Inner { float4 color; };\n" ^
        "struct Args { device uint *pointer; Inner values[2]; };\n" ^
        "kernel void argument8(device Args &args [[buffer(0)]], " ^
        "uint i [[thread_position_in_grid]]) { " ^
        "args.pointer[i] = uint(args.values[0].color.x); }\n"
      in
      let library = get (Library.compile_source ~device source) in
      let function_ = get (Function.find ~library "argument8") in
      let pipeline = get (Compute_pipeline.create ~reflection:true function_) in
      let bindings =
        match Compute_pipeline.bindings pipeline with
        | Some bindings -> bindings
        | None -> failwith "requested argument reflection was absent"
      in
      let binding =
        match List.find_opt (fun (value : Binding.t) -> value.index = 0L) bindings with
        | Some value -> value
        | None -> failwith "argument buffer binding was absent"
      in
      let snapshot =
        match Binding.reflection binding with
        | Some value -> value
        | None -> failwith "argument buffer nested reflection was absent"
      in
      get (Compute_pipeline.destroy pipeline);
      get (Function.destroy function_);
      get (Library.destroy library);
      let snapshot =
        match snapshot with
        | Reflection.Pointer { element = Some nested; _ } -> nested
        | value -> value
      in
      (match snapshot with
       | Reflection.Struct members ->
           (match member "pointer" members, member "values" members with
            | Some { reflected_type = Some (Reflection.Pointer pointer); _ },
              Some { reflected_type = Some (Reflection.Array array); _ } ->
                if array.length <> 2L || array.stride <= 0L
                   || pointer.alignment <= 0L || pointer.data_size <= 0L
                then failwith "copied pointer/array reflection metadata mismatch";
                (match array.element with
                 | Some (Reflection.Struct nested) when List.length nested = 1 -> ()
                 | _ -> failwith "nullable nested structure reflection mismatch")
            | _ -> failwith "struct members changed after native owners died")
       | _ -> failwith "argument buffer reflection root was not a structure");
      get (Device.destroy device);
      print_endline "argument8 safe: copied immutable recursive reflection ok"
