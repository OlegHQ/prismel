open Metal

let fail format = Printf.ksprintf failwith format

let get = function
  | Ok value -> value
  | Error error -> fail "%s" (Format.asprintf "%a" pp_error error)

let expect_error kind = function
  | Error error when error.kind = kind -> error
  | Error error ->
      fail "expected a different error kind: %s"
        (Format.asprintf "%a" pp_error error)
  | Ok _ -> fail "operation unexpectedly succeeded"

let shader_source =
  {|
#include <metal_stdlib>
using namespace metal;

kernel void increment(device uint *values [[buffer(0)]],
                      uint index [[thread_position_in_grid]]) {
  values[index] += 1;
}
|}

let input_values () =
  let bytes = Bytes.create 16 in
  [| 1l; 41l; 99l; -2l |]
  |> Array.iteri (fun index value -> Bytes.set_int32_le bytes (index * 4) value);
  bytes

let align_up value alignment =
  let remainder = Int64.rem value alignment in
  if remainder = 0L then value
  else Int64.add value (Int64.sub alignment remainder)

let expected_values = [| 2l; 42l; 100l; Int32.minus_one |]

let check_values bytes =
  Array.iteri
    (fun index expected ->
      let actual = Bytes.get_int32_le bytes (index * 4) in
      if actual <> expected then
        fail "compute output %d: expected %ld, got %ld" index expected actual)
    expected_values

let settle_finalizers ~expected_live =
  let rec loop remaining =
    Gc.full_major ();
    ignore (get (Release_queue.drain ()));
    let stats = get (Release_queue.stats ()) in
    if stats.pending = 0 && stats.live_handles = expected_live then stats
    else if remaining = 0 then
      fail "Metal finalizers did not settle (%d pending, %d live; expected %d)"
        stats.pending stats.live_handles expected_live
    else loop (remaining - 1)
  in
  loop 8

let () =
  if Sys.os_type <> "Unix"
     || not (Sys.file_exists "/System/Library/Frameworks/Metal.framework")
  then Printf.printf "Metal conformance skipped on this platform\n%!"
  else begin
    if Provenance.sdk_version <> "26.5" then
      fail "unexpected generated SDK provenance %s" Provenance.sdk_version;
    let device = get (Device.system_default ()) in
    let all_devices = get (Device.all ()) in
    if all_devices = [] then fail "MTLCopyAllDevices returned no devices";
    let info = get (Device.info device) in
    if info.name = "" || info.registry_id = 0L then
      fail "default device identity is incomplete";
    if info.max_buffer_length < 16L then fail "device buffer limit is invalid";
    let before_finalizer = get (Release_queue.stats ()) in
    let allocate_unreleased_buffer () =
      ignore (get (Buffer.create ~device ~length:16L ~storage:Buffer.Shared ()))
    in
    allocate_unreleased_buffer ();
    let after_finalizer =
      settle_finalizers ~expected_live:before_finalizer.live_handles
    in
    if
      Int64.sub after_finalizer.total_created before_finalizer.total_created <> 1L
      || Int64.sub after_finalizer.total_released before_finalizer.total_released
         <> 1L
    then fail "custom-block finalization did not release exactly one Metal handle";
    ignore
      (expect_error Wrong_domain
         (Domain.spawn (fun () -> Device.info device) |> Domain.join));
    let buffer =
      get
        (Buffer.create ~device ~length:16L ~storage:Buffer.Shared
           ~label:"Metal conformance values" ())
    in
    if Buffer.cpu_cache_mode buffer <> Buffer.Default_cache
       || Buffer.hazard_tracking_mode buffer <> Buffer.Tracked
       || Buffer.heap_offset buffer <> None
    then fail "direct buffer resource properties are wrong";
    if get (Buffer.label buffer) <> Some "Metal conformance values" then
      fail "buffer label did not round-trip";
    get (Buffer.write_bytes buffer ~dst_offset:0L (input_values ()));
    let escaped_mapping = ref None in
    get
      (Buffer.with_mapping buffer ~offset:4L ~length:8 (fun mapping ->
         escaped_mapping := Some mapping;
         if get (Buffer.Mapping.length mapping) <> 8 then
           fail "mapped range length changed";
         ignore (expect_error Parent_has_dependents (Buffer.destroy buffer));
         ignore
           (expect_error Parent_has_dependents
              (Buffer.set_purgeable_state buffer Volatile));
         let mapped = get (Buffer.Mapping.read_bytes mapping ~offset:0 ~length:8) in
         if Bytes.get_int32_le mapped 0 <> 41l then
           fail "mapped range read the wrong buffer offset";
         Bytes.set_int32_le mapped 0 50l;
         get (Buffer.Mapping.write_bytes mapping ~dst_offset:0 mapped)));
    let escaped_mapping = Option.get !escaped_mapping in
    ignore
      (expect_error Destroyed
         (Buffer.Mapping.read_bytes escaped_mapping ~offset:0 ~length:1));
    let updated = get (Buffer.read_bytes buffer ~offset:4L ~length:4) in
    if Bytes.get_int32_le updated 0 <> 50l then
      fail "mapped range write did not update the Metal buffer";
    get (Buffer.write_bytes buffer ~dst_offset:0L (input_values ()));
    if get (Buffer.purgeable_state buffer) <> Nonvolatile then
      fail "new buffer is not nonvolatile";
    if get (Buffer.is_aliasable buffer) then
      fail "direct buffer unexpectedly reports aliasable";
    ignore (expect_error Invalid_state (Buffer.make_aliasable buffer));
    ignore (expect_error Parent_has_dependents (Device.destroy device));
    ignore
      (expect_error Invalid_argument
         (Buffer.read_bytes buffer ~offset:12L ~length:8));
    ignore
      (expect_error Invalid_argument
         (Buffer.read_bytes buffer ~offset:0L ~length:max_int));
    let private_buffer =
      get (Buffer.create ~device ~length:16L ~storage:Buffer.Private ())
    in
    ignore
      (expect_error Unsupported
         (Buffer.read_bytes private_buffer ~offset:0L ~length:4));
    get (Buffer.destroy private_buffer);
    let configured_buffer =
      get
        (Buffer.create ~device ~length:16L ~storage:Buffer.Shared
           ~cpu_cache:Buffer.Write_combined
           ~hazard_tracking:Buffer.Untracked ())
    in
    if Buffer.cpu_cache_mode configured_buffer <> Buffer.Write_combined
       || Buffer.hazard_tracking_mode configured_buffer <> Buffer.Untracked
    then fail "explicit buffer resource options did not round-trip";
    if get (Buffer.set_purgeable_state configured_buffer Volatile) <> Nonvolatile
    then fail "buffer volatile transition did not return its prior state";
    let volatile_state = get (Buffer.purgeable_state configured_buffer) in
    (match volatile_state with
     | Nonvolatile -> ()
     | Volatile | Empty ->
         ignore
           (expect_error Invalid_state
              (Buffer.read_bytes configured_buffer ~offset:0L ~length:4));
         let prior =
           get (Buffer.set_purgeable_state configured_buffer Nonvolatile)
         in
         if prior <> Volatile && prior <> Empty then
           fail "buffer restore did not report its discardable state");
    if get (Buffer.set_purgeable_state configured_buffer Empty) <> Nonvolatile
    then fail "buffer empty transition did not return nonvolatile";
    (match get (Buffer.purgeable_state configured_buffer) with
     | Nonvolatile -> ()
     | Volatile -> fail "empty buffer unexpectedly became volatile"
     | Empty ->
         ignore
           (expect_error Invalid_state
              (Buffer.write_bytes configured_buffer ~dst_offset:0L
                 (input_values ())));
         if
           get (Buffer.set_purgeable_state configured_buffer Nonvolatile)
           <> Empty
         then fail "empty buffer restore did not report discarded contents");
    get (Buffer.destroy configured_buffer);
    let texture_descriptor =
      Texture.descriptor_2d ~mipmapped:true ~storage:Buffer.Shared
        ~usage:[ Texture.Shader_read; Texture.Pixel_format_view ]
        ~label:"Metal conformance texture" ~format:Texture.Rgba8_unorm
        ~width:4 ~height:4 ()
    in
    let odd_mip_descriptor =
      Texture.descriptor_2d ~mipmapped:true ~format:Texture.R8_unorm ~width:3
        ~height:1 ()
    in
    if odd_mip_descriptor.mip_levels <> 2 then
      fail "non-power-of-two texture mip cardinality is wrong";
    let texture = get (Texture.create ~device texture_descriptor) in
    if (Texture.descriptor texture).mip_levels <> 3 then
      fail "2D texture mip cardinality is wrong";
    if (Texture.descriptor texture).hazard_tracking <> Texture.Tracked
       || Texture.heap_offset texture <> None
    then fail "direct texture resource properties are wrong";
    if get (Texture.purgeable_state texture) <> Nonvolatile
       || get (Texture.is_aliasable texture)
    then fail "direct texture resource state is wrong";
    if get (Texture.label texture) <> Some "Metal conformance texture" then
      fail "texture label did not round-trip";
    get (Texture.set_label texture "Metal renamed texture");
    if get (Texture.label texture) <> Some "Metal renamed texture" then
      fail "texture label mutation did not round-trip";
    let texture_bytes = Bytes.make 80 '\xee' in
    for row = 0 to 3 do
      for column_byte = 0 to 15 do
        Bytes.set_uint8 texture_bytes ((row * 20) + column_byte)
          ((row * 16) + column_byte)
      done
    done;
    let full_region : Texture.region =
      { x = 0; y = 0; z = 0; width = 4; height = 4; depth = 1 }
    in
    get
      (Texture.write_bytes texture ~region:full_region ~mip_level:0 ~slice:0
         ~bytes_per_row:20 ~bytes_per_image:80 texture_bytes);
    let texture_copy =
      get
        (Texture.read_bytes texture ~region:full_region ~mip_level:0 ~slice:0
           ~bytes_per_row:20 ~bytes_per_image:80)
    in
    for row = 0 to 3 do
      for column_byte = 0 to 15 do
        let offset = (row * 20) + column_byte in
        if Bytes.get_uint8 texture_copy offset <> Bytes.get_uint8 texture_bytes offset
        then fail "texture byte transfer changed active pixel data"
      done;
      for padding = 16 to 19 do
        if Bytes.get_uint8 texture_copy ((row * 20) + padding) <> 0 then
          fail "texture read exposed uninitialized row padding"
      done
    done;
    ignore
      (expect_error Invalid_argument
         (Texture.write_bytes texture ~region:full_region ~mip_level:0 ~slice:0
            ~bytes_per_row:15 ~bytes_per_image:60 texture_bytes));
    ignore
      (expect_error Invalid_argument
         (Texture.write_bytes texture ~region:full_region ~mip_level:0 ~slice:0
            ~bytes_per_row:20 ~bytes_per_image:80 (Bytes.create 79)));
    ignore
      (expect_error Invalid_argument
         (Texture.write_bytes texture ~region:full_region ~mip_level:0 ~slice:0
            ~src_offset:81 ~bytes_per_row:20 ~bytes_per_image:80 texture_bytes));
    ignore
      (expect_error Invalid_argument
         (Texture.read_bytes texture ~region:full_region ~mip_level:0 ~slice:0
            ~bytes_per_row:max_int ~bytes_per_image:max_int));
    let invalid_region : Texture.region =
      { full_region with x = 3; width = 2 }
    in
    ignore
      (expect_error Invalid_argument
         (Texture.read_bytes texture ~region:invalid_region ~mip_level:0 ~slice:0
            ~bytes_per_row:8 ~bytes_per_image:32));
    let mip_region : Texture.region =
      { x = 0; y = 0; z = 0; width = 2; height = 2; depth = 1 }
    in
    let mip_bytes = Bytes.init 16 (fun index -> Char.chr (index + 20)) in
    get
      (Texture.write_bytes texture ~region:mip_region ~mip_level:1 ~slice:0
         ~bytes_per_row:8 ~bytes_per_image:16 mip_bytes);
    if
      get
        (Texture.read_bytes texture ~region:mip_region ~mip_level:1 ~slice:0
           ~bytes_per_row:8 ~bytes_per_image:16)
      <> mip_bytes
    then fail "texture mip transfer did not round-trip";
    let texture_view =
      get
        (Texture.create_view texture ~format:Texture.Rgba8_unorm_srgb
           ~base_mip:0 ~mip_count:3 ~base_slice:0 ~slice_count:1
           ~label:"Metal sRGB view" ())
    in
    if get (Texture.label texture_view) <> Some "Metal sRGB view" then
      fail "texture-view label did not round-trip";
    if get (Texture.purgeable_state texture_view) <> Nonvolatile
       || get (Texture.is_aliasable texture_view)
    then fail "texture view did not share its base resource state";
    ignore
      (expect_error Invalid_state
         (Texture.set_purgeable_state texture_view Volatile));
    ignore
      (expect_error Parent_has_dependents
         (Texture.set_purgeable_state texture Volatile));
    ignore
      (expect_error Parent_has_dependents (Texture.make_aliasable texture));
    ignore
      (expect_error Invalid_argument
         (Texture.create_view texture ~format:Texture.Rgba16_float ~base_mip:0
            ~mip_count:1 ~base_slice:0 ~slice_count:1 ()));
    ignore
      (expect_error Invalid_argument
         (Texture.create_view texture ~format:Texture.Rgba8_unorm ~base_mip:3
            ~mip_count:1 ~base_slice:0 ~slice_count:1 ()));
    ignore (expect_error Parent_has_dependents (Texture.destroy texture));
    get (Texture.destroy texture_view);
    if get (Texture.set_purgeable_state texture Volatile) <> Nonvolatile then
      fail "texture volatile transition did not return its prior state";
    let texture_volatile = get (Texture.purgeable_state texture) in
    (match texture_volatile with
     | Nonvolatile -> ()
     | Volatile | Empty ->
         ignore
           (expect_error Invalid_state
              (Texture.read_bytes texture ~region:full_region ~mip_level:0
                 ~slice:0 ~bytes_per_row:20 ~bytes_per_image:80));
         let texture_prior =
           get (Texture.set_purgeable_state texture Nonvolatile)
         in
         if texture_prior <> Volatile && texture_prior <> Empty then
           fail "texture restore did not report its discardable state");
    ignore (expect_error Invalid_state (Texture.make_aliasable texture));
    let no_view_texture =
      get
        (Texture.create ~device
           (Texture.descriptor_2d ~storage:Buffer.Shared
              ~format:Texture.Rgba8_unorm ~width:1 ~height:1 ()))
    in
    ignore
      (expect_error Invalid_argument
         (Texture.create_view no_view_texture ~format:Texture.Rgba8_unorm
            ~base_mip:0 ~mip_count:1 ~base_slice:0 ~slice_count:1 ()));
    get (Texture.destroy no_view_texture);
    let private_texture =
      get
        (Texture.create ~device
           (Texture.descriptor_2d ~storage:Buffer.Private
              ~usage:[ Texture.Render_target ] ~format:Texture.Bgra8_unorm
              ~width:4 ~height:4 ()))
    in
    ignore
      (expect_error Unsupported
         (Texture.read_bytes private_texture ~region:full_region ~mip_level:0
            ~slice:0 ~bytes_per_row:16 ~bytes_per_image:64));
    get (Texture.destroy private_texture);
    let heap_buffer_layout =
      get
        (Heap.buffer_size_and_align ~device ~length:64L
           ~storage:Buffer.Private ())
    in
    let heap_texture_descriptor =
      Texture.descriptor_2d ~storage:Buffer.Private
        ~usage:[ Texture.Shader_read ] ~label:"Heap texture"
        ~format:Texture.Rgba8_unorm ~width:8 ~height:8 ()
    in
    let heap_texture_layout =
      get (Heap.texture_size_and_align ~device heap_texture_descriptor)
    in
    let heap_texture_offset =
      align_up heap_buffer_layout.size heap_texture_layout.alignment
    in
    let placement_size =
      Int64.add heap_texture_offset heap_texture_layout.size
    in
    let placement_heap =
      get
        (Heap.create ~device
           (Heap.make_descriptor ~kind:Heap.Placement
              ~label:"Metal placement heap" ~size:placement_size ()))
    in
    if get (Heap.label placement_heap) <> Some "Metal placement heap" then
      fail "heap label did not round-trip";
    get (Heap.set_label placement_heap "Metal renamed heap");
    if get (Heap.label placement_heap) <> Some "Metal renamed heap" then
      fail "heap label mutation did not round-trip";
    if get (Heap.purgeable_state placement_heap) <> Nonvolatile then
      fail "new heap is not nonvolatile";
    if get (Heap.set_purgeable_state placement_heap Volatile) <> Nonvolatile then
      fail "heap volatile transition did not return its prior state";
    let heap_volatile = get (Heap.purgeable_state placement_heap) in
    (match heap_volatile with
     | Nonvolatile -> ()
     | Volatile | Empty ->
         ignore
           (expect_error Invalid_state
              (Heap.create_buffer placement_heap ~offset:0L ~length:64L ()));
         let heap_prior =
           get (Heap.set_purgeable_state placement_heap Nonvolatile)
         in
         if heap_prior <> Volatile && heap_prior <> Empty then
           fail "heap restore did not report its discardable state");
    if get (Heap.set_purgeable_state placement_heap Empty) <> Nonvolatile then
      fail "heap empty transition did not return nonvolatile";
    (match get (Heap.purgeable_state placement_heap) with
     | Nonvolatile -> ()
     | Volatile -> fail "empty heap unexpectedly became volatile"
     | Empty ->
         if get (Heap.set_purgeable_state placement_heap Nonvolatile) <> Empty then
           fail "empty heap restore did not report discarded contents");
    let placement_info = get (Heap.info placement_heap) in
    if placement_info.size < placement_size
       || placement_info.storage <> Buffer.Private
       || placement_info.hazard_tracking <> Heap.Untracked
       || placement_info.kind <> Heap.Placement
    then fail "placement heap properties are wrong";
    ignore
      (expect_error Invalid_argument
         (Heap.max_available_size placement_heap ~alignment:3L));
    ignore
      (expect_error Invalid_argument
         (Heap.create_buffer placement_heap ~length:64L ()));
    ignore
      (expect_error Invalid_argument
         (Heap.create_buffer placement_heap ~offset:placement_info.size
            ~length:64L ()));
    let heap_buffer =
      get
        (Heap.create_buffer placement_heap ~offset:0L ~length:64L
           ~label:"Heap buffer" ())
    in
    if Buffer.heap_offset heap_buffer <> Some 0L
       || Buffer.storage_mode heap_buffer <> Buffer.Private
       || Buffer.hazard_tracking_mode heap_buffer <> Buffer.Untracked
    then fail "heap buffer properties are wrong";
    if not (get (Buffer.is_aliasable heap_buffer)) then
      fail "placement heap buffer did not report native aliasability";
    ignore
      (expect_error Invalid_state
         (Heap.create_buffer placement_heap ~offset:0L ~length:64L ()));
    let heap_texture =
      get
        (Heap.create_texture placement_heap ~offset:heap_texture_offset
           heap_texture_descriptor)
    in
    if Texture.heap_offset heap_texture <> Some heap_texture_offset
       || (Texture.descriptor heap_texture).hazard_tracking <> Texture.Untracked
    then fail "heap texture properties are wrong";
    if not (get (Texture.is_aliasable heap_texture)) then
      fail "placement heap texture did not report native aliasability";
    ignore (get (Heap.set_purgeable_state placement_heap Volatile));
    (match get (Heap.purgeable_state placement_heap) with
     | Nonvolatile -> ()
     | Volatile | Empty ->
         ignore
           (expect_error Invalid_state
              (Heap.create_texture placement_heap ~offset:heap_texture_offset
                 heap_texture_descriptor));
         ignore (expect_error Invalid_state (Buffer.make_aliasable heap_buffer));
         ignore (get (Heap.set_purgeable_state placement_heap Nonvolatile)));
    get (Buffer.make_aliasable heap_buffer);
    if not (get (Buffer.is_aliasable heap_buffer)) then
      fail "heap buffer did not become aliasable";
    ignore
      (expect_error Invalid_state
         (Buffer.with_mapping heap_buffer ~offset:0L ~length:1 (fun _ -> ())));
    let aliased_heap_buffer =
      get (Heap.create_buffer placement_heap ~offset:0L ~length:64L ())
    in
    get (Texture.make_aliasable heap_texture);
    if not (get (Texture.is_aliasable heap_texture)) then
      fail "heap texture did not become aliasable";
    ignore
      (expect_error Invalid_state
         (Texture.create_view heap_texture ~format:Texture.Rgba8_unorm
            ~base_mip:0 ~mip_count:1 ~base_slice:0 ~slice_count:1 ()));
    let aliased_heap_texture =
      get
        (Heap.create_texture placement_heap ~offset:heap_texture_offset
           heap_texture_descriptor)
    in
    ignore (expect_error Parent_has_dependents (Heap.destroy placement_heap));
    get (Texture.destroy aliased_heap_texture);
    get (Texture.destroy heap_texture);
    get (Buffer.destroy aliased_heap_buffer);
    get (Buffer.destroy heap_buffer);
    let reused_heap_buffer =
      get (Heap.create_buffer placement_heap ~offset:0L ~length:64L ())
    in
    get (Buffer.destroy reused_heap_buffer);
    get (Heap.destroy placement_heap);
    let automatic_heap =
      get
        (Heap.create ~device
           (Heap.make_descriptor ~label:"Metal automatic heap"
              ~size:heap_buffer_layout.size ()))
    in
    ignore
      (expect_error Invalid_argument
         (Heap.create_buffer automatic_heap ~offset:0L ~length:64L ()));
    let automatic_buffer =
      get (Heap.create_buffer automatic_heap ~length:64L ())
    in
    if Buffer.heap_offset automatic_buffer <> None then
      fail "automatic heap buffer reported a placement offset";
    let automatic_info = get (Heap.info automatic_heap) in
    ignore
      (expect_error Invalid_state
         (Heap.create_buffer automatic_heap
            ~length:(Int64.succ automatic_info.size) ()));
    get (Buffer.make_aliasable automatic_buffer);
    if not (get (Buffer.is_aliasable automatic_buffer)) then
      fail "automatic heap buffer did not become aliasable";
    let replacement_buffer =
      get (Heap.create_buffer automatic_heap ~length:64L ())
    in
    ignore
      (expect_error Invalid_state
         (Buffer.with_mapping automatic_buffer ~offset:0L ~length:1
            (fun _ -> ())));
    get (Buffer.destroy replacement_buffer);
    get (Buffer.destroy automatic_buffer);
    get (Heap.destroy automatic_heap);
    let shared_heap_layout =
      get
        (Heap.buffer_size_and_align ~device ~length:16L
           ~storage:Buffer.Shared ~cpu_cache:Heap.Write_combined
           ~hazard_tracking:Heap.Tracked ())
    in
    let shared_heap =
      get
        (Heap.create ~device
           (Heap.make_descriptor ~storage:Buffer.Shared
              ~cpu_cache:Heap.Write_combined ~hazard_tracking:Heap.Tracked
              ~size:shared_heap_layout.size ()))
    in
    let shared_heap_buffer =
      get (Heap.create_buffer shared_heap ~length:16L ())
    in
    if Buffer.storage_mode shared_heap_buffer <> Buffer.Shared
       || Buffer.cpu_cache_mode shared_heap_buffer <> Buffer.Write_combined
       || Buffer.hazard_tracking_mode shared_heap_buffer <> Buffer.Tracked
    then fail "configured shared heap resource properties are wrong";
    get
      (Buffer.with_mapping shared_heap_buffer ~offset:0L ~length:16
         (fun mapping ->
           ignore
             (expect_error Parent_has_dependents
                (Heap.set_purgeable_state shared_heap Volatile));
           get
             (Buffer.Mapping.write_bytes mapping ~dst_offset:0
                (input_values ()))));
    if
      get (Buffer.read_bytes shared_heap_buffer ~offset:0L ~length:16)
      <> input_values ()
    then fail "shared heap buffer transfer did not round-trip";
    get (Buffer.destroy shared_heap_buffer);
    get (Heap.destroy shared_heap);
    ignore
      (expect_error Unsupported
         (Heap.create ~device
            (Heap.make_descriptor ~storage:Buffer.Managed ~size:4096L ())));
    ignore
      (expect_error Invalid_argument
         (Heap.create ~device (Heap.make_descriptor ~size:0L ())));
    ignore
      (expect_error Invalid_argument
         (Heap.create ~device
            (Heap.make_descriptor ~label:"invalid\000label" ~size:4096L ())));
    ignore
      (expect_error Native_error
         (Heap.create ~device
            (Heap.make_descriptor ~label:"\255" ~size:4096L ())));
    ignore
      (expect_error Invalid_argument
         (Texture.create ~device { texture_descriptor with width = 0 }));
    ignore
      (expect_error Invalid_argument
         (Texture.create ~device { texture_descriptor with mip_levels = 9 }));
    ignore
      (expect_error Invalid_argument
         (Texture.create ~device
            { texture_descriptor with
              kind = Texture.Texture_1d
            ; height = 2
            ; mip_levels = 1
            }));
    ignore
      (expect_error Invalid_argument
         (Texture.create ~device
            { texture_descriptor with sample_count = 2; mip_levels = 1 }));
    ignore
      (expect_error Invalid_argument
         (Texture.create ~device
            { texture_descriptor with
              usage = [ Texture.Shader_read; Texture.Shader_read ]
            }));
    ignore
      (expect_error Invalid_argument
         (Texture.create ~device
            { texture_descriptor with label = Some "invalid\000label" }));
    ignore
      (expect_error Native_error
         (Texture.create ~device
            { texture_descriptor with label = Some "\255" }));
    ignore
      (expect_error Invalid_argument
         (Device.supports_texture_sample_count device 0));
    if get (Device.supports_texture_sample_count device 2) then begin
      let multisample_texture =
        get
          (Texture.create ~device
             { texture_descriptor with
               kind = Texture.Texture_2d_multisample
             ; mip_levels = 1
             ; sample_count = 2
             ; storage = Buffer.Private
             ; usage = [ Texture.Render_target ]
             ; label = None
             })
      in
      ignore
        (expect_error Unsupported
           (Texture.read_bytes multisample_texture ~region:full_region
              ~mip_level:0 ~slice:0 ~bytes_per_row:16 ~bytes_per_image:64));
      get (Texture.destroy multisample_texture)
    end;
    let sampler_descriptor =
      { (Sampler.default ~label:"Metal linear sampler" ()) with
        min_filter = Sampler.Linear
      ; mag_filter = Sampler.Linear
      ; mip_filter = Sampler.Mip_linear
      ; max_anisotropy = 4
      ; s_address = Sampler.Repeat
      ; t_address = Sampler.Repeat
      ; r_address = Sampler.Repeat
      ; lod_max_clamp = 3.
      ; support_argument_buffers = true
      }
    in
    let sampler = get (Sampler.create ~device sampler_descriptor) in
    if get (Sampler.label sampler) <> Some "Metal linear sampler" then
      fail "sampler label did not round-trip";
    ignore
      (expect_error Invalid_argument
         (Sampler.create ~device { sampler_descriptor with max_anisotropy = 0 }));
    ignore
      (expect_error Invalid_argument
         (Sampler.create ~device { sampler_descriptor with lod_min_clamp = nan }));
    ignore
      (expect_error Invalid_argument
         (Sampler.create ~device
            { sampler_descriptor with
              normalized_coordinates = false
            ; s_address = Sampler.Repeat
            }));
    ignore
      (expect_error Invalid_argument
         (Sampler.create ~device
            { sampler_descriptor with lod_min_clamp = 2.; lod_max_clamp = 1. }));
    ignore
      (expect_error Invalid_argument
         (Sampler.create ~device
            { sampler_descriptor with label = Some "invalid\000label" }));
    ignore
      (expect_error Native_error
         (Sampler.create ~device
            { sampler_descriptor with label = Some "\255" }));
    get (Sampler.destroy sampler);
    get (Texture.destroy texture);
    let invalid_shader =
      expect_error Native_error
        (Library.compile_source ~device "not a Metal program")
    in
    if invalid_shader.message = "" then
      fail "shader compilation lost its diagnostic";
    let library = get (Library.compile_source ~device shader_source) in
    let function_ = get (Function.find ~library "increment") in
    if get (Function.name function_) <> "increment" then
      fail "Metal function name did not round-trip";
    ignore (expect_error Parent_has_dependents (Library.destroy library));
    let pipeline = get (Compute_pipeline.create function_) in
    if Compute_pipeline.thread_execution_width pipeline <= 0
       || Compute_pipeline.max_total_threads_per_threadgroup pipeline <= 0
    then fail "compute pipeline limits are invalid";
    let queue = get (Command_queue.create device) in
    let commands =
      get (Command_buffer.create queue ~label:"Metal compute conformance" ())
    in
    let encoder = get (Compute_encoder.create commands) in
    get (Compute_encoder.set_pipeline encoder pipeline);
    if get (Buffer.read_bytes buffer ~offset:0L ~length:16) <> input_values () then
      fail "compute input changed before command encoding";
    get (Compute_encoder.set_buffer encoder ~index:0 ~offset:0L buffer);
    ignore (expect_error Parent_has_dependents (Buffer.destroy buffer));
    ignore
      (expect_error Parent_has_dependents
         (Buffer.set_purgeable_state buffer Volatile));
    ignore
      (expect_error Invalid_argument
         (Compute_encoder.dispatch_threads encoder ~threads:(4, 1, 1)
            ~threadgroup:(max_int, 2, 1)));
    get
      (Compute_encoder.dispatch_threads encoder ~threads:(4, 1, 1)
         ~threadgroup:(4, 1, 1));
    ignore (expect_error Invalid_state (Command_buffer.commit commands));
    get (Compute_encoder.end_encoding encoder);
    get (Command_buffer.commit commands);
    get (Command_buffer.wait_until_completed commands);
    (match get (Command_buffer.status commands) with
     | Command_buffer.Completed -> ()
     | _ -> fail "command buffer did not complete");
    Buffer.read_bytes buffer ~offset:0L ~length:16 |> get |> check_values;
    get (Buffer.destroy buffer);
    get (Command_buffer.destroy commands);
    get (Command_queue.destroy queue);
    get (Compute_pipeline.destroy pipeline);
    get (Function.destroy function_);
    get (Library.destroy library);
    get (Buffer.destroy buffer);
    ignore
      (expect_error Destroyed
         (Buffer.read_bytes buffer ~offset:0L ~length:1));
    get (Device.destroy device);
    List.iter (fun value -> get (Device.destroy value)) all_devices;
    let stats = settle_finalizers ~expected_live:0 in
    if stats.pending <> 0 || stats.dropped <> 0 || stats.live_handles <> 0 then
      fail "Metal release accounting did not settle (%d pending, %d dropped, %d live)"
        stats.pending stats.dropped stats.live_handles;
    Printf.printf
      "Metal ARC/device/heap/buffer/texture/sampler/runtime-shader/compute conformance passed on %s\n%!"
      info.name
  end
