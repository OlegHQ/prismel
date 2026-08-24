open Metal

let get = function
  | Ok value -> value
  | Error error -> failwith (Format.asprintf "%a" pp_error error)

let reject = function Error _ -> () | Ok _ -> failwith "expected rejection"

let () =
  let dimensions = get (Tensor.Extents.create [| 4L; 8L |]) in
  let strides = get (Tensor.Extents.create [| 8L; 1L |]) in
  if Tensor.Extents.rank dimensions <> 2
     || get (Tensor.Extents.extent dimensions 1) <> 8L
  then failwith "tensor extents changed";
  reject (Tensor.Extents.extent dimensions 2);
  reject (Tensor.Extents.create [| 4L; 0L |]);
  let descriptor =
    get (Tensor.Descriptor.create
      ~data_type:Data_type.mtl_data_type_float
      ~dimensions ~strides)
  in
  get (Tensor.Descriptor.set_options descriptor ~storage:Buffer.Shared
    ~cpu_cache:Heap.Default_cache
    ~hazard_tracking:Heap.Default_hazard_tracking ~usage:0L);
  reject (Tensor.Extents.destroy dimensions);
  get (Tensor.Descriptor.destroy descriptor);
  get (Tensor.Extents.destroy dimensions);
  get (Tensor.Extents.destroy strides);
  let device = get (Device.system_default ()) in
  let buffer = get (Buffer.create device ~length:256L ~storage:Buffer.Shared) in
  (match Tensor.of_buffer buffer ~data_type:Data_type.mtl_data_type_float
           ~dimensions:[| 4L; 8L |] ~strides:[| 8L; 1L |] ~offset:0L with
   | Error { kind=Unsupported; _ } -> ()
   | Error error -> failwith (Format.asprintf "%a" pp_error error)
   | Ok tensor ->
       if Tensor.buffer tensor != buffer || Tensor.offset tensor <> 0L
          || Tensor.dimensions tensor <> [| 4L; 8L |]
       then failwith "tensor ownership graph changed";
       ignore (get (Tensor.gpu_resource_id tensor));
       ignore (get (Tensor.usage tensor));
       reject (Buffer.destroy buffer);
       get (Tensor.destroy tensor));
  get (Buffer.destroy buffer);
  get (Device.destroy device)
