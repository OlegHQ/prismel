let contains needle haystack =
  let n = String.length needle and h = String.length haystack in
  let rec loop i = i + n <= h && (String.sub haystack i n = needle || loop (i + 1)) in
  loop 0

let () =
  let output = Binding_struct_native_codegen.generate () in
  assert (List.length output.method_ids = 19);
  assert (List.length output.property_ids = 8);
  assert (List.length (List.sort_uniq String.compare output.method_ids) = 19);
  assert (not (contains "objc_msgSend" output.native));
  assert (contains "MTLSizeMake" output.native);
  assert (contains "MTLRegionMake3D" output.native);
  assert (contains "MTLResourceID" output.native);
  assert (contains "@available(macOS 26.0, *)" output.native);
  assert (contains "dispatchThreadgroups:argument_0 threadsPerThreadgroup:argument_1" output.native);
  assert (contains "external generated_struct_m_t_l_device_max_threads_per_threadgroup" output.raw_ml);
  assert (contains "Types.handle ->" output.raw_ml);
  assert (not (contains "Handle.t" output.raw_ml));
  Printf.printf "Metal struct native codegen emits 19 calls plus 8 property companions\n"
