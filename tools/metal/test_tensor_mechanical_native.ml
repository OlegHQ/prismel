let selectors =
  [ "method:-[MTLTensor bufferOffset]", "tensor_buffer_offset"
  ; "method:-[MTLTensor dataType]", "tensor_data_type"
  ; "method:-[MTLTensor gpuResourceID]", "tensor_gpu_resource_id"
  ; "method:-[MTLTensor usage]", "tensor_usage"
  ; "method:-[MTLTensorDescriptor cpuCacheMode]", "tensor_descriptor_cpu_cache_mode"
  ; "method:-[MTLTensorDescriptor dataType]", "tensor_descriptor_data_type"
  ; "method:-[MTLTensorDescriptor hazardTrackingMode]", "tensor_descriptor_hazard_tracking_mode"
  ; "method:-[MTLTensorDescriptor resourceOptions]", "tensor_descriptor_resource_options"
  ; "method:-[MTLTensorDescriptor setCpuCacheMode:]", "tensor_descriptor_set_cpu_cache_mode"
  ; "method:-[MTLTensorDescriptor setDataType:]", "tensor_descriptor_set_data_type"
  ; "method:-[MTLTensorDescriptor setHazardTrackingMode:]", "tensor_descriptor_set_hazard_tracking_mode"
  ; "method:-[MTLTensorDescriptor setResourceOptions:]", "tensor_descriptor_set_resource_options"
  ; "method:-[MTLTensorDescriptor setStorageMode:]", "tensor_descriptor_set_storage_mode"
  ; "method:-[MTLTensorDescriptor setUsage:]", "tensor_descriptor_set_usage"
  ; "method:-[MTLTensorDescriptor storageMode]", "tensor_descriptor_storage_mode"
  ; "method:-[MTLTensorDescriptor usage]", "tensor_descriptor_usage"
  ; "method:-[MTLTensorExtents extentAtDimensionIndex:]", "tensor_extents_extent"
  ; "method:-[MTLTensorExtents rank]", "tensor_extents_rank"
  ]

let read path = In_channel.with_open_bin path In_channel.input_all
let contains text needle =
  let n = String.length needle in
  let rec loop i = i + n <= String.length text
    && (String.sub text i n = needle || loop (i + 1))
  in loop 0

let () =
  if Array.length Sys.argv <> 5 then invalid_arg "expected generated/native/raw paths";
  let generated = read Sys.argv.(1) and bridge = read Sys.argv.(2)
  and raw_ml = read Sys.argv.(3) and raw_mli = read Sys.argv.(4) in
  if List.length selectors <> 18
     || List.length (List.sort_uniq String.compare (List.map fst selectors)) <> 18
  then failwith "Tensor mechanical18 selector drift";
  List.iter (fun (selector, raw_name) ->
    let native = "caml_prismel_metal_" ^ raw_name in
    if not (contains generated selector && contains bridge native
            && contains raw_ml native && contains raw_mli native)
    then failwith ("Tensor mechanical ABI missing: " ^ selector)) selectors;
  if not (contains bridge "static_assert(std::is_same_v") then
    failwith "Tensor native qualifier assertions missing";
  Printf.printf "Tensor mechanical18 selector/raw/native closure is exact\n"
