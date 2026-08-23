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

let sparse_shader_source =
  {|
#include <metal_stdlib>
using namespace metal;

kernel void sparse_read(texture2d<uint, access::read> source [[texture(0)]],
                        device uint *result [[buffer(0)]]) {
  result[0] = source.read(uint2(0u, 0u)).x;
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

let complete_commands commands =
  get (Command_buffer.commit commands);
  get (Command_buffer.wait_until_completed commands);
  (match get (Command_buffer.status commands) with
   | Command_buffer.Completed -> ()
   | _ -> fail "sparse conformance command buffer did not complete");
  get (Command_buffer.destroy commands)

let test_format_matrix device =
  let formats = Texture.all_formats in
  if List.length formats <> 130
     || List.length (List.sort_uniq compare formats) <> List.length formats
  then fail "Metal pixel-format inventory is incomplete or duplicated";
  let bc_formats =
    [ Texture.Bc1_rgba; Texture.Bc1_rgba_srgb; Texture.Bc2_rgba
    ; Texture.Bc2_rgba_srgb; Texture.Bc3_rgba; Texture.Bc3_rgba_srgb
    ; Texture.Bc4_r_unorm; Texture.Bc4_r_snorm; Texture.Bc5_rg_unorm
    ; Texture.Bc5_rg_snorm; Texture.Bc6h_rgb_float; Texture.Bc6h_rgb_ufloat
    ; Texture.Bc7_rgba_unorm; Texture.Bc7_rgba_unorm_srgb
    ]
  and eac_etc2_formats =
    [ Texture.Eac_r11_unorm; Texture.Eac_r11_snorm; Texture.Eac_rg11_unorm
    ; Texture.Eac_rg11_snorm; Texture.Eac_rgba8; Texture.Eac_rgba8_srgb
    ; Texture.Etc2_rgb8; Texture.Etc2_rgb8_srgb; Texture.Etc2_rgb8a1
    ; Texture.Etc2_rgb8a1_srgb
    ]
  and astc_ldr_formats =
    [ Texture.Astc_4x4_srgb; Texture.Astc_5x4_srgb; Texture.Astc_5x5_srgb
    ; Texture.Astc_6x5_srgb; Texture.Astc_6x6_srgb; Texture.Astc_8x5_srgb
    ; Texture.Astc_8x6_srgb; Texture.Astc_8x8_srgb
    ; Texture.Astc_10x5_srgb; Texture.Astc_10x6_srgb
    ; Texture.Astc_10x8_srgb; Texture.Astc_10x10_srgb
    ; Texture.Astc_12x10_srgb; Texture.Astc_12x12_srgb
    ; Texture.Astc_4x4_ldr; Texture.Astc_5x4_ldr; Texture.Astc_5x5_ldr
    ; Texture.Astc_6x5_ldr; Texture.Astc_6x6_ldr; Texture.Astc_8x5_ldr
    ; Texture.Astc_8x6_ldr; Texture.Astc_8x8_ldr; Texture.Astc_10x5_ldr
    ; Texture.Astc_10x6_ldr; Texture.Astc_10x8_ldr
    ; Texture.Astc_10x10_ldr; Texture.Astc_12x10_ldr
    ; Texture.Astc_12x12_ldr
    ]
  and astc_hdr_formats =
    [ Texture.Astc_4x4_hdr; Texture.Astc_5x4_hdr; Texture.Astc_5x5_hdr
    ; Texture.Astc_6x5_hdr; Texture.Astc_6x6_hdr; Texture.Astc_8x5_hdr
    ; Texture.Astc_8x6_hdr; Texture.Astc_8x8_hdr; Texture.Astc_10x5_hdr
    ; Texture.Astc_10x6_hdr; Texture.Astc_10x8_hdr
    ; Texture.Astc_10x10_hdr; Texture.Astc_12x10_hdr
    ; Texture.Astc_12x12_hdr
    ]
  in
  let compressed_formats =
    bc_formats @ eac_etc2_formats @ astc_ldr_formats @ astc_hdr_formats
  in
  if List.length compressed_formats <> 66 then
    fail "compressed Metal pixel-format test inventory is incomplete";
  let supports_bc = get (Device.supports_bc_texture_compression device) in
  let supports_apple2 = get (Device.supports_family device Device.Apple2) in
  let supports_apple6 = get (Device.supports_family device Device.Apple6) in
  let supports_metal4 = get (Device.supports_family device Device.Metal4) in
  let supports_eac_astc = supports_apple2 || supports_metal4 in
  let supports_astc_hdr = supports_apple6 || supports_metal4 in
  let expects_compressed format =
    if List.mem format bc_formats then supports_bc
    else if List.mem format eac_etc2_formats then supports_eac_astc
    else if List.mem format astc_ldr_formats then supports_eac_astc
    else if List.mem format astc_hdr_formats then supports_astc_hdr
    else false
  in
  let expect_layout format block_width block_height bytes_per_block =
    let layout = Texture.format_layout format in
    if layout.block_width <> block_width
       || layout.block_height <> block_height
       || layout.bytes_per_block <> bytes_per_block
    then fail "Metal pixel-format block layout is wrong"
  in
  expect_layout Texture.R8_sint 1 1 1;
  expect_layout Texture.B5g6r5_unorm 1 1 2;
  expect_layout Texture.Rgba32_uint 1 1 16;
  expect_layout Texture.Gbgr422 2 1 4;
  expect_layout Texture.Bc1_rgba 4 4 8;
  expect_layout Texture.Bc7_rgba_unorm 4 4 16;
  expect_layout Texture.Eac_r11_unorm 4 4 8;
  expect_layout Texture.Astc_10x6_hdr 10 6 16;
  let before_invalid = get (Release_queue.stats ()) in
  ignore
    (expect_error Invalid_argument
       (Texture.create ~device
          (Texture.descriptor_2d ~format:Texture.Gbgr422 ~width:3 ~height:2
             ())));
  ignore
    (expect_error Invalid_argument
       (Texture.create ~device
          (Texture.descriptor_2d ~mipmapped:true ~format:Texture.Bgrg422
             ~width:4 ~height:4 ())));
  ignore
    (expect_error Invalid_argument
       (Texture.create ~device
          (Texture.descriptor_2d ~format:Texture.X32_stencil8 ~width:4
             ~height:4 ())));
  let after_invalid = get (Release_queue.stats ()) in
  if after_invalid.total_created <> before_invalid.total_created then
    fail "invalid special-format descriptors allocated native handles";
  if not (get (Device.supports_depth24_stencil8 device)) then begin
    let before = get (Release_queue.stats ()) in
    ignore
      (expect_error Unsupported
         (Texture.create ~device
            (Texture.descriptor_2d
               ~format:Texture.Depth24_unorm_stencil8 ~width:4 ~height:4
               ())));
    let after = get (Release_queue.stats ()) in
    if after.total_created <> before.total_created then
      fail "unsupported Depth24Unorm_Stencil8 allocated a native handle"
  end;
  let supported_uncompressed = ref 0 in
  let supported_compressed = ref 0 in
  List.iteri
    (fun index format ->
      if format <> Texture.X32_stencil8 && format <> Texture.X24_stencil8 then
        let compressed = List.mem format compressed_formats in
        let expected = expects_compressed format in
        let before = get (Release_queue.stats ()) in
        let descriptor =
          Texture.descriptor_2d ~storage:Buffer.Private
            ~usage:[ Texture.Shader_read ] ~format ~width:12 ~height:12 ()
        in
        match Texture.create ~device descriptor with
        | Ok texture ->
            if compressed && not expected then
              fail "unsupported compressed format %d reached Metal" index;
            if compressed then incr supported_compressed
            else incr supported_uncompressed;
            if (Texture.descriptor texture).format <> format then
              fail "Metal changed pixel format at matrix index %d" index;
            get (Texture.destroy texture)
        | Error { kind = Unsupported; _ } when compressed && not expected ->
            let after = get (Release_queue.stats ()) in
            if after.total_created <> before.total_created then
              fail "unsupported compressed format %d allocated a handle" index
        | Error error when compressed ->
            fail "compressed format %d contradicted its capability gate: %s"
              index (Format.asprintf "%a" pp_error error)
        | Error { kind = (Native_error | Unsupported); _ } -> ()
        | Error error -> fail "%s" (Format.asprintf "%a" pp_error error))
    formats;
  if !supported_uncompressed < 48 then
    fail "device accepted only %d of 62 creatable uncompressed formats"
      !supported_uncompressed;
  let expected_compressed_count =
    (if supports_bc then List.length bc_formats else 0)
    + (if supports_eac_astc then
         List.length eac_etc2_formats + List.length astc_ldr_formats
       else 0)
    + (if supports_astc_hdr then List.length astc_hdr_formats else 0)
  in
  if !supported_compressed <> expected_compressed_count then
    fail "device accepted %d/%d capability-gated compressed formats"
      !supported_compressed expected_compressed_count;
  List.iteri
    (fun index format ->
      if expects_compressed format then begin
        let layout = Texture.format_layout format in
        let width = (2 * layout.block_width) - 1 in
        let height = (2 * layout.block_height) - 1 in
        let row_bytes = 2 * layout.bytes_per_block in
        let image_bytes = 2 * row_bytes in
        let source =
          Bytes.init image_bytes (fun byte ->
            Char.chr (((index * 47) + (byte * 43)) land 0xff))
        in
        let texture =
          get
            (Texture.create ~device
               (Texture.descriptor_2d ~storage:Buffer.Shared
                  ~usage:[ Texture.Shader_read ] ~format ~width ~height ()))
        in
        let region : Texture.region =
          { x = 0; y = 0; z = 0; width; height; depth = 1 }
        in
        get
          (Texture.write_bytes texture ~region ~mip_level:0 ~slice:0
             ~bytes_per_row:row_bytes ~bytes_per_image:image_bytes source);
        if
          get
            (Texture.read_bytes texture ~region ~mip_level:0 ~slice:0
               ~bytes_per_row:row_bytes ~bytes_per_image:image_bytes)
          <> source
        then
          fail "compressed format %d did not preserve its encoded blocks" index;
        get (Texture.destroy texture)
      end)
    compressed_formats;
  let compressed_view_pairs =
    (if supports_bc then
       [ Texture.Bc1_rgba, Texture.Bc1_rgba_srgb
       ; Texture.Bc2_rgba, Texture.Bc2_rgba_srgb
       ; Texture.Bc3_rgba, Texture.Bc3_rgba_srgb
       ; Texture.Bc7_rgba_unorm, Texture.Bc7_rgba_unorm_srgb
       ]
     else [])
    @
    if supports_eac_astc then
      [ Texture.Eac_rgba8, Texture.Eac_rgba8_srgb
      ; Texture.Etc2_rgb8, Texture.Etc2_rgb8_srgb
      ; Texture.Etc2_rgb8a1, Texture.Etc2_rgb8a1_srgb
      ; Texture.Astc_4x4_ldr, Texture.Astc_4x4_srgb
      ; Texture.Astc_5x4_ldr, Texture.Astc_5x4_srgb
      ; Texture.Astc_5x5_ldr, Texture.Astc_5x5_srgb
      ; Texture.Astc_6x5_ldr, Texture.Astc_6x5_srgb
      ; Texture.Astc_6x6_ldr, Texture.Astc_6x6_srgb
      ; Texture.Astc_8x5_ldr, Texture.Astc_8x5_srgb
      ; Texture.Astc_8x6_ldr, Texture.Astc_8x6_srgb
      ; Texture.Astc_8x8_ldr, Texture.Astc_8x8_srgb
      ; Texture.Astc_10x5_ldr, Texture.Astc_10x5_srgb
      ; Texture.Astc_10x6_ldr, Texture.Astc_10x6_srgb
      ; Texture.Astc_10x8_ldr, Texture.Astc_10x8_srgb
      ; Texture.Astc_10x10_ldr, Texture.Astc_10x10_srgb
      ; Texture.Astc_12x10_ldr, Texture.Astc_12x10_srgb
      ; Texture.Astc_12x12_ldr, Texture.Astc_12x12_srgb
      ]
    else []
  in
  List.iter
    (fun (linear, srgb) ->
      List.iter
        (fun (source, target) ->
          let layout = Texture.format_layout source in
          let parent =
            get
              (Texture.create ~device
                 (Texture.descriptor_2d ~storage:Buffer.Private
                    ~usage:[ Texture.Shader_read; Texture.Pixel_format_view ]
                    ~format:source ~width:layout.block_width
                    ~height:layout.block_height ()))
          in
          let view =
            get
              (Texture.create_view parent ~format:target ~base_mip:0
                 ~mip_count:1 ~base_slice:0 ~slice_count:1 ())
          in
          if (Texture.descriptor view).format <> target then
            fail "Metal changed a compressed texture-view format";
          get (Texture.destroy view);
          get (Texture.destroy parent))
        [ linear, srgb; srgb, linear ])
    compressed_view_pairs;
  let compression_probe =
    if supports_bc then Some (Texture.Bc1_rgba, Texture.Bc1_rgba_srgb)
    else if supports_eac_astc then
      Some (Texture.Eac_rgba8, Texture.Eac_rgba8_srgb)
    else None
  in
  Option.iter
    (fun (format, view_format) ->
      let layout = Texture.format_layout format in
      let width = (2 * layout.block_width) - 1 in
      let height = (2 * layout.block_height) - 1 in
      let before = get (Release_queue.stats ()) in
      let base =
        Texture.descriptor_2d ~storage:Buffer.Shared
          ~usage:[ Texture.Shader_read ] ~format ~width ~height ()
      in
      ignore
        (expect_error Invalid_argument
           (Texture.create ~device
              { base with kind = Texture.Texture_1d; height = 1 }));
      ignore
        (expect_error Invalid_argument
           (Texture.create ~device
              { base with usage = [ Texture.Shader_write ] }));
      ignore
        (expect_error Invalid_argument
           (Texture.minimum_buffer_alignment ~device ~kind:Texture.Texture_2d
              ~format));
      let after = get (Release_queue.stats ()) in
      if after.total_created <> before.total_created then
        fail "invalid compressed descriptors allocated native handles";
      let volume_supported =
        get (Device.supports_family device Device.Apple3)
        || get (Device.supports_family device Device.Mac2)
        || get (Device.supports_family device Device.Metal3)
        || supports_metal4
      in
      let volume_descriptor =
        { base with
          kind = Texture.Texture_3d
        ; width = 8
        ; height = 8
        ; depth = 4
        ; storage = Buffer.Private
        }
      in
      if volume_supported then
        get (Texture.create ~device volume_descriptor) |> Texture.destroy |> get
      else begin
        let before_volume = get (Release_queue.stats ()) in
        ignore
          (expect_error Unsupported
             (Texture.create ~device volume_descriptor));
        let after_volume = get (Release_queue.stats ()) in
        if after_volume.total_created <> before_volume.total_created then
          fail "unsupported compressed volume allocated a native handle"
      end;
      let texture = get (Texture.create ~device base) in
      let full : Texture.region =
        { x = 0; y = 0; z = 0; width; height; depth = 1 }
      in
      let row_bytes = 2 * layout.bytes_per_block in
      let image_bytes = 2 * row_bytes in
      let compressed_bytes =
        Bytes.init image_bytes (fun index -> Char.chr ((index * 43) land 0xff))
      in
      ignore
        (expect_error Invalid_argument
           (Texture.write_bytes texture
              ~region:{ full with x = 1; width = layout.block_width }
              ~mip_level:0 ~slice:0 ~bytes_per_row:row_bytes
              ~bytes_per_image:image_bytes compressed_bytes));
      get
        (Texture.write_bytes texture ~region:full ~mip_level:0 ~slice:0
           ~bytes_per_row:row_bytes ~bytes_per_image:image_bytes
           compressed_bytes);
      if
        get
          (Texture.read_bytes texture ~region:full ~mip_level:0 ~slice:0
             ~bytes_per_row:row_bytes ~bytes_per_image:image_bytes)
        <> compressed_bytes
      then fail "compressed texture blocks did not round-trip exactly";
      get (Texture.destroy texture);
      let view_parent =
        get
          (Texture.create ~device
             { base with
               storage = Buffer.Private
             ; usage = [ Texture.Shader_read; Texture.Pixel_format_view ]
             })
      in
      let view =
        get
          (Texture.create_view view_parent ~format:view_format ~base_mip:0
             ~mip_count:1 ~base_slice:0 ~slice_count:1 ())
      in
      get (Texture.destroy view);
      get (Texture.destroy view_parent);
      let staging =
        get
          (Buffer.create_copy ~device ~storage:Buffer.Shared compressed_bytes)
      in
      let destination =
        get (Texture.create ~device { base with storage = Buffer.Private })
      in
      let queue = get (Command_queue.create device) in
      let commands = get (Command_buffer.create queue ()) in
      let blit = get (Blit_encoder.create commands) in
      ignore
        (expect_error Invalid_argument
           (Blit_encoder.copy_buffer_to_texture blit ~source:staging
              ~source_offset:0L ~source_bytes_per_row:row_bytes
              ~source_bytes_per_image:image_bytes ~destination
              ~destination_slice:0 ~destination_level:0
              ~destination_region:{ full with y = 1; height = layout.block_height }));
      get
        (Blit_encoder.copy_buffer_to_texture blit ~source:staging
           ~source_offset:0L ~source_bytes_per_row:row_bytes
           ~source_bytes_per_image:image_bytes ~destination
           ~destination_slice:0 ~destination_level:0 ~destination_region:full);
      get (Blit_encoder.end_encoding blit);
      complete_commands commands;
      get (Texture.destroy destination);
      get (Buffer.destroy staging);
      get (Command_queue.destroy queue))
    compression_probe;
  let transfer_descriptor =
    Texture.descriptor_2d ~storage:Buffer.Shared
      ~format:Texture.Rgba8_uint ~width:4 ~height:2 ()
  in
  let transfer = get (Texture.create ~device transfer_descriptor) in
  let transfer_region : Texture.region =
    { x = 0; y = 0; z = 0; width = 4; height = 2; depth = 1 }
  in
  let bytes = Bytes.init 32 (fun index -> Char.chr ((index * 29) land 0xff)) in
  get
    (Texture.write_bytes transfer ~region:transfer_region ~mip_level:0
       ~slice:0 ~bytes_per_row:16 ~bytes_per_image:32 bytes);
  if
    get
      (Texture.read_bytes transfer ~region:transfer_region ~mip_level:0
         ~slice:0 ~bytes_per_row:16 ~bytes_per_image:32)
    <> bytes
  then fail "integer pixel-format transfer did not round-trip exactly";
  get (Texture.destroy transfer);
  let packed_descriptor =
    Texture.descriptor_2d ~storage:Buffer.Shared ~format:Texture.Gbgr422
      ~width:4 ~height:2 ()
  in
  (match Texture.create ~device packed_descriptor with
   | Error { kind = Native_error; _ } -> ()
   | Error error -> fail "%s" (Format.asprintf "%a" pp_error error)
   | Ok packed ->
       let misaligned : Texture.region =
         { x = 1; y = 0; z = 0; width = 2; height = 1; depth = 1 }
       in
       ignore
         (expect_error Invalid_argument
            (Texture.write_bytes packed ~region:misaligned ~mip_level:0
               ~slice:0 ~bytes_per_row:4 ~bytes_per_image:4
               (Bytes.make 4 '\000')));
       let full : Texture.region =
         { x = 0; y = 0; z = 0; width = 4; height = 2; depth = 1 }
       in
       let packed_bytes =
         Bytes.init 16 (fun index -> Char.chr ((index * 17) land 0xff))
       in
       get
         (Texture.write_bytes packed ~region:full ~mip_level:0 ~slice:0
            ~bytes_per_row:8 ~bytes_per_image:16 packed_bytes);
       if
         get
           (Texture.read_bytes packed ~region:full ~mip_level:0 ~slice:0
              ~bytes_per_row:8 ~bytes_per_image:16)
         <> packed_bytes
       then fail "subsampled pixel-format transfer did not round-trip exactly";
       get (Texture.destroy packed));
  let depth_stencil_descriptor =
    Texture.descriptor_2d ~storage:Buffer.Private
      ~usage:[ Texture.Render_target; Texture.Pixel_format_view ]
      ~format:Texture.Depth32_float_stencil8 ~width:4 ~height:4 ()
  in
  (match Texture.create ~device depth_stencil_descriptor with
   | Error { kind = Native_error; _ } -> ()
   | Error error -> fail "%s" (Format.asprintf "%a" pp_error error)
   | Ok depth_stencil ->
       let stencil =
         get
           (Texture.create_view depth_stencil ~format:Texture.X32_stencil8
              ~base_mip:0 ~mip_count:1 ~base_slice:0 ~slice_count:1 ())
       in
       get (Texture.destroy stencil);
       get (Texture.destroy depth_stencil))

let test_sparse_textures device =
  if not (get (Device.supports_sparse_textures device)) then false
  else begin
    let page_sizes =
      [ Sparse_page_size.Page_64_kib
      ; Sparse_page_size.Page_16_kib
      ; Sparse_page_size.Page_256_kib
      ]
    in
    let supported_pages =
      List.filter_map
        (fun page_size ->
          match Heap.sparse_tile_size_in_bytes ~device page_size with
          | Ok bytes ->
              if bytes <> Sparse_page_size.bytes page_size then
                fail "sparse page size query changed its byte cardinality";
              Some (page_size, bytes)
          | Error { kind = Unsupported; _ } -> None
          | Error error -> fail "%s" (Format.asprintf "%a" pp_error error))
        page_sizes
    in
    let page_size, page_bytes =
      match supported_pages with
      | first :: _ -> first
      | [] -> fail "device reports sparse textures but no supported page size"
    in
    List.iter
      (fun (candidate, bytes) ->
        let probe =
          get
            (Heap.create ~device
               (Heap.make_descriptor ~kind:Heap.Sparse
                  ~sparse_page_size:candidate ~size:bytes ()))
        in
        get (Heap.destroy probe))
      supported_pages;
    let before_invalid = get (Release_queue.stats ()) in
    ignore
      (expect_error Invalid_argument
         (Heap.create ~device
            (Heap.make_descriptor ~kind:Heap.Sparse ~size:page_bytes ())));
    ignore
      (expect_error Invalid_argument
         (Heap.create ~device
            (Heap.make_descriptor ~sparse_page_size:page_size
               ~size:page_bytes ())));
    ignore
      (expect_error Invalid_argument
         (Heap.create ~device
            (Heap.make_descriptor ~kind:Heap.Sparse
               ~sparse_page_size:page_size ~storage:Buffer.Shared
               ~size:page_bytes ())));
    ignore
      (expect_error Invalid_argument
         (Heap.create ~device
            (Heap.make_descriptor ~kind:Heap.Sparse
               ~sparse_page_size:page_size ~size:(Int64.pred page_bytes) ())));
    let after_invalid = get (Release_queue.stats ()) in
    if after_invalid.total_created <> before_invalid.total_created then
      fail "invalid sparse heap descriptors allocated native handles";
    let heap =
      get
        (Heap.create ~device
           (Heap.make_descriptor ~kind:Heap.Sparse
              ~sparse_page_size:page_size ~label:"Metal sparse heap"
              ~size:(Int64.mul 4L page_bytes) ()))
    in
    let heap_info = get (Heap.info heap) in
    if heap_info.kind <> Heap.Sparse || heap_info.storage <> Buffer.Private then
      fail "sparse heap properties did not round-trip";
    ignore
      (expect_error Unsupported
         (Heap.create_buffer heap ~length:page_bytes ()));
    let descriptor =
      Texture.descriptor_2d ~mipmapped:true ~storage:Buffer.Private
        ~usage:[ Texture.Shader_read; Texture.Shader_write ]
        ~label:"Metal sparse texture" ~format:Texture.R8_uint ~width:1024
        ~height:1024 ()
    in
    ignore
      (expect_error Invalid_argument
         (Heap.create_texture heap ~offset:0L descriptor));
    ignore
      (expect_error Unsupported
         (Heap.create_texture heap
            { descriptor with
              kind = Texture.Texture_1d
            ; height = 1
            }));
    ignore
      (expect_error Unsupported
         (Heap.create_texture heap
            { descriptor with format = Texture.Depth32_float }));
    let texture = get (Heap.create_texture heap descriptor) in
    if Texture.heap_offset texture <> None then
      fail "sparse texture unexpectedly reports a placement offset";
    let sparse_info =
      match get (Texture.sparse_info texture) with
      | Some info -> info
      | None -> fail "sparse heap returned a non-sparse texture"
    in
    if sparse_info.page_size <> page_size
       || sparse_info.tile_size_in_bytes <> page_bytes
       || sparse_info.tile_width <= 0 || sparse_info.tile_height <= 0
       || sparse_info.tile_depth <= 0
    then fail "sparse texture metadata is inconsistent";
    let compressed_texture =
      get
        (Heap.create_texture heap
           (Texture.descriptor_2d ~mipmapped:true ~storage:Buffer.Private
              ~usage:[ Texture.Shader_read ] ~format:Texture.Astc_4x4_ldr
              ~width:256 ~height:256 ()))
    in
    let compressed_sparse_info =
      match get (Texture.sparse_info compressed_texture) with
      | Some info -> info
      | None -> fail "compressed sparse texture lost its sparse metadata"
    in
    if compressed_sparse_info.page_size <> page_size
       || compressed_sparse_info.tile_size_in_bytes <> page_bytes
       || compressed_sparse_info.tile_width mod 4 <> 0
       || compressed_sparse_info.tile_height mod 4 <> 0
    then fail "compressed sparse tile metadata is not block-aligned";
    ignore (expect_error Invalid_state (Texture.purgeable_state texture));
    ignore
      (expect_error Invalid_state
         (Texture.set_purgeable_state texture Volatile));
    ignore (expect_error Invalid_state (Texture.make_aliasable texture));
    let ordinary =
      get
        (Texture.create ~device
           (Texture.descriptor_2d ~storage:Buffer.Private
              ~usage:[ Texture.Shader_read; Texture.Shader_write ]
              ~format:Texture.R8_uint ~width:4 ~height:4 ()))
    in
    if get (Texture.sparse_info ordinary) <> None then
      fail "ordinary texture was reported as sparse";
    let overflow_texture =
      get
        (Texture.create ~device
           { (Texture.descriptor_2d ~storage:Buffer.Private
                ~format:Texture.R8_uint ~width:1 ~height:1 ()) with
             kind = Texture.Texture_3d
           ; depth = 2
           })
    in
    let staging_bytes = Bytes.make (Int64.to_int page_bytes) '\000' in
    Bytes.set staging_bytes 0 (Char.chr 37);
    let staging =
      get
        (Buffer.create_copy ~device ~storage:Buffer.Shared
           ~label:"Metal sparse tile staging" staging_bytes)
    in
    let queue = get (Command_queue.create device) in
    let tile : Resource_state_encoder.tile_region =
      { x = 0; y = 0; z = 0; width = 1; height = 1; depth = 1 }
    in
    let map_commands = get (Command_buffer.create queue ()) in
    let mapper = get (Resource_state_encoder.create map_commands) in
    ignore
      (expect_error Invalid_argument
         (Resource_state_encoder.update_texture_mapping mapper
            ~mode:Resource_state_encoder.Map ordinary ~mip_level:0 ~slice:0
            ~region:tile));
    ignore
      (expect_error Invalid_argument
         (Resource_state_encoder.update_texture_mapping mapper
            ~mode:Resource_state_encoder.Map texture ~mip_level:(-1) ~slice:0
            ~region:tile));
    ignore
      (expect_error Invalid_argument
         (Resource_state_encoder.update_texture_mapping mapper
            ~mode:Resource_state_encoder.Map texture ~mip_level:0 ~slice:1
            ~region:tile));
    ignore
      (expect_error Invalid_argument
         (Resource_state_encoder.update_texture_mapping mapper
            ~mode:Resource_state_encoder.Map texture ~mip_level:0 ~slice:0
            ~region:{ tile with x = max_int }));
    get
      (Resource_state_encoder.update_texture_mapping mapper
         ~mode:Resource_state_encoder.Map texture ~mip_level:0 ~slice:0
         ~region:tile);
    Option.iter
      (fun first_mip ->
        get
          (Resource_state_encoder.update_texture_mapping mapper
             ~mode:Resource_state_encoder.Map texture ~mip_level:first_mip
             ~slice:0 ~region:tile))
      sparse_info.first_mip_in_tail;
    ignore (expect_error Parent_has_dependents (Texture.destroy texture));
    ignore (expect_error Parent_has_dependents (Heap.destroy heap));
    ignore
      (expect_error Parent_has_dependents
         (Heap.set_purgeable_state heap Volatile));
    ignore (expect_error Invalid_state (Command_buffer.commit map_commands));
    get (Resource_state_encoder.end_encoding mapper);
    if not (Resource_state_encoder.destroyed mapper) then
      fail "ended resource-state encoder remained live";
    ignore
      (expect_error Destroyed
         (Resource_state_encoder.update_texture_mapping mapper
            ~mode:Resource_state_encoder.Map texture ~mip_level:0 ~slice:0
            ~region:tile));
    let blit = get (Blit_encoder.create map_commands) in
    let destination_region : Texture.region =
      { x = 0
      ; y = 0
      ; z = 0
      ; width = sparse_info.tile_width
      ; height = sparse_info.tile_height
      ; depth = sparse_info.tile_depth
      }
    in
    ignore
      (expect_error Invalid_argument
         (Blit_encoder.copy_buffer_to_texture blit ~source:staging
            ~source_offset:(-1L)
            ~source_bytes_per_row:sparse_info.tile_width
            ~source_bytes_per_image:(Int64.to_int page_bytes)
            ~destination:texture ~destination_slice:0 ~destination_level:0
            ~destination_region));
    ignore
      (expect_error Invalid_argument
         (Blit_encoder.copy_buffer_to_texture blit ~source:staging
            ~source_offset:0L ~source_bytes_per_row:1
            ~source_bytes_per_image:max_int ~destination:overflow_texture
            ~destination_slice:0 ~destination_level:0
            ~destination_region:
              { x = 0; y = 0; z = 0; width = 1; height = 1; depth = 2 }));
    get
      (Blit_encoder.copy_buffer_to_texture blit ~source:staging
         ~source_offset:0L ~source_bytes_per_row:sparse_info.tile_width
         ~source_bytes_per_image:(Int64.to_int page_bytes)
         ~destination:texture ~destination_slice:0 ~destination_level:0
         ~destination_region);
    ignore (expect_error Parent_has_dependents (Buffer.destroy staging));
    get (Blit_encoder.end_encoding blit);
    if not (Blit_encoder.destroyed blit) then
      fail "ended blit encoder remained live";
    ignore
      (expect_error Destroyed
         (Blit_encoder.copy_buffer_to_texture blit ~source:staging
            ~source_offset:0L ~source_bytes_per_row:sparse_info.tile_width
            ~source_bytes_per_image:(Int64.to_int page_bytes)
            ~destination:texture ~destination_slice:0 ~destination_level:0
            ~destination_region));
    complete_commands map_commands;
    let library = get (Library.compile_source ~device sparse_shader_source) in
    let read_function = get (Function.find ~library "sparse_read") in
    let read_pipeline = get (Compute_pipeline.create read_function) in
    let output =
      get (Buffer.create ~device ~length:4L ~storage:Buffer.Shared ())
    in
    let run_read source =
      get (Buffer.write_bytes output ~dst_offset:0L (Bytes.make 4 '\000'));
      let commands = get (Command_buffer.create queue ()) in
      let encoder = get (Compute_encoder.create commands) in
      get (Compute_encoder.set_pipeline encoder read_pipeline);
      ignore
        (expect_error Invalid_argument
           (Compute_encoder.set_texture encoder ~index:(-1) source));
      get (Compute_encoder.set_texture encoder ~index:0 source);
      get (Compute_encoder.set_buffer encoder ~index:0 ~offset:0L output);
      get
        (Compute_encoder.dispatch_threads encoder ~threads:(1, 1, 1)
           ~threadgroup:(1, 1, 1));
      get (Compute_encoder.end_encoding encoder);
      complete_commands commands;
      Bytes.get_int32_le (get (Buffer.read_bytes output ~offset:0L ~length:4)) 0
    in
    let mapped_value = run_read texture in
    if mapped_value <> 37l then begin
      let mapped_heap = get (Heap.info heap) in
      fail
        "mapped sparse texture lost GPU writes (value=%ld used=%Ld allocated=%Ld page=%Ld tile=%dx%dx%d tail=%s/%Ld)"
        mapped_value mapped_heap.used_size mapped_heap.current_allocated_size
        page_bytes sparse_info.tile_width sparse_info.tile_height
        sparse_info.tile_depth
        (match sparse_info.first_mip_in_tail with
         | None -> "none"
         | Some level -> string_of_int level)
        sparse_info.tail_size_in_bytes
    end;
    let unmap_commands = get (Command_buffer.create queue ()) in
    let unmapper = get (Resource_state_encoder.create unmap_commands) in
    get
      (Resource_state_encoder.update_texture_mapping unmapper
         ~mode:Resource_state_encoder.Unmap texture ~mip_level:0 ~slice:0
         ~region:tile);
    Option.iter
      (fun first_mip ->
        get
          (Resource_state_encoder.update_texture_mapping unmapper
             ~mode:Resource_state_encoder.Unmap texture ~mip_level:first_mip
             ~slice:0 ~region:tile))
      sparse_info.first_mip_in_tail;
    get (Resource_state_encoder.end_encoding unmapper);
    complete_commands unmap_commands;
    if run_read texture <> 0l then
      fail "unmapped sparse texture did not return defined zero data";
    get (Buffer.destroy staging);
    get (Buffer.destroy output);
    get (Compute_pipeline.destroy read_pipeline);
    get (Function.destroy read_function);
    get (Library.destroy library);
    get (Texture.destroy overflow_texture);
    get (Texture.destroy ordinary);
    get (Texture.destroy compressed_texture);
    get (Texture.destroy texture);
    get (Heap.destroy heap);
    get (Command_queue.destroy queue);
    true
  end

let test_residency_set device =
  let supported = get (Device.supports_residency_sets device) in
  let descriptor =
    Residency_set.make_descriptor ~label:"Metal residency conformance"
      ~initial_capacity:3 ()
  in
  if not supported then begin
    ignore
      (expect_error Unsupported (Residency_set.create ~device descriptor));
    false
  end
  else begin
    ignore
      (expect_error Invalid_argument
         (Residency_set.create ~device
            (Residency_set.make_descriptor ~initial_capacity:(-1) ())));
    ignore
      (expect_error Invalid_argument
         (Residency_set.create ~device
            (Residency_set.make_descriptor ~label:"invalid\000label" ())));
    ignore
      (expect_error Native_error
         (Residency_set.create ~device
            (Residency_set.make_descriptor ~label:"\255" ())));
    let before_finalizer = get (Release_queue.stats ()) in
    let allocate_unreleased_membership () =
      let buffer =
        get (Buffer.create ~device ~length:16L ~storage:Buffer.Shared ())
      in
      let residency_set =
        get
          (Residency_set.create ~device
             (Residency_set.make_descriptor ~initial_capacity:1 ()))
      in
      get
        (Residency_set.add_allocation residency_set
           (Residency_set.Buffer buffer))
    in
    allocate_unreleased_membership ();
    let after_finalizer =
      settle_finalizers ~expected_live:before_finalizer.live_handles
    in
    if
      Int64.sub after_finalizer.total_created before_finalizer.total_created <> 2L
      || Int64.sub after_finalizer.total_released before_finalizer.total_released
         <> 2L
    then fail "residency finalization did not release its set and allocation";
    let buffer =
      get (Buffer.create ~device ~length:64L ~storage:Buffer.Shared ())
    in
    let texture =
      get
        (Texture.create ~device
           (Texture.descriptor_2d ~storage:Buffer.Shared
              ~format:Texture.Rgba8_unorm ~width:4 ~height:4 ()))
    in
    let heap_layout =
      get
        (Heap.buffer_size_and_align ~device ~length:64L
           ~storage:Buffer.Private ())
    in
    let heap =
      get
        (Heap.create ~device
           (Heap.make_descriptor ~size:heap_layout.size ()))
    in
    let residency_set = get (Residency_set.create ~device descriptor) in
    if not (Device.same device (Residency_set.device residency_set)) then
      fail "residency set lost its creating device";
    let native_label = get (Residency_set.label residency_set) in
    if
      (native_label <> None
       && native_label <> Some "Metal residency conformance")
      || get (Residency_set.allocation_count residency_set) <> 0
      || get (Residency_set.allocations residency_set) <> []
    then fail "empty residency-set properties are wrong";
    let buffer_allocation = Residency_set.Buffer buffer in
    let texture_allocation = Residency_set.Texture texture in
    let heap_allocation = Residency_set.Heap heap in
    List.iter
      (fun allocation ->
        if get (Residency_set.allocation_size allocation) < 0L then
          fail "Metal returned a negative allocation size")
      [ buffer_allocation; texture_allocation; heap_allocation ];
    get (Residency_set.add_allocation residency_set buffer_allocation);
    get
      (Residency_set.add_allocations residency_set
         [ texture_allocation; heap_allocation ]);
    if get (Residency_set.allocation_count residency_set) <> 3
       || List.length (get (Residency_set.allocations residency_set)) <> 3
       || not (get (Residency_set.contains residency_set buffer_allocation))
       || not (get (Residency_set.contains residency_set texture_allocation))
       || not (get (Residency_set.contains residency_set heap_allocation))
    then fail "residency-set additions did not round-trip";
    ignore
      (expect_error Invalid_argument
         (Residency_set.add_allocations residency_set
            [ texture_allocation; texture_allocation ]));
    ignore (expect_error Parent_has_dependents (Buffer.destroy buffer));
    ignore
      (expect_error Parent_has_dependents
         (Buffer.set_purgeable_state buffer Volatile));
    ignore (expect_error Parent_has_dependents (Texture.destroy texture));
    ignore
      (expect_error Parent_has_dependents
         (Texture.set_purgeable_state texture Volatile));
    ignore (expect_error Parent_has_dependents (Heap.destroy heap));
    ignore
      (expect_error Parent_has_dependents
         (Heap.set_purgeable_state heap Volatile));
    get (Residency_set.commit residency_set);
    if get (Residency_set.allocated_size residency_set) < 0L then
      fail "Metal returned a negative residency-set footprint";
    get (Residency_set.request_residency residency_set);
    get (Residency_set.end_residency residency_set);
    get (Residency_set.remove_allocation residency_set buffer_allocation);
    if get (Residency_set.contains residency_set buffer_allocation)
       || get (Residency_set.allocation_count residency_set) <> 2
    then fail "pending residency removal was not observable";
    ignore (expect_error Parent_has_dependents (Buffer.destroy buffer));
    get (Residency_set.add_allocation residency_set buffer_allocation);
    if not (get (Residency_set.contains residency_set buffer_allocation)) then
      fail "residency re-add did not cancel the pending removal";
    get (Residency_set.commit residency_set);
    get
      (Residency_set.remove_allocations residency_set
         [ buffer_allocation; texture_allocation ]);
    if get (Residency_set.allocation_count residency_set) <> 1 then
      fail "bulk residency removal count is wrong";
    ignore (expect_error Parent_has_dependents (Buffer.destroy buffer));
    ignore (expect_error Parent_has_dependents (Texture.destroy texture));
    get (Residency_set.commit residency_set);
    get (Buffer.destroy buffer);
    get (Texture.destroy texture);
    get (Residency_set.remove_all_allocations residency_set);
    if get (Residency_set.allocation_count residency_set) <> 0 then
      fail "remove-all residency membership is wrong";
    ignore (expect_error Parent_has_dependents (Heap.destroy heap));
    get (Residency_set.commit residency_set);
    get (Heap.destroy heap);
    get (Residency_set.destroy residency_set);
    ignore
      (expect_error Destroyed (Residency_set.label residency_set));
    true
  end

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
    test_format_matrix device;
    let residency_sets_supported = test_residency_set device in
    ignore (test_sparse_textures device);
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
    let copy_source = Bytes.init 32 (fun index -> Char.chr (index + 1)) in
    let copied_buffer =
      get
        (Buffer.create_copy ~device ~storage:Buffer.Shared ~src_offset:4
           ~length:16 ~label:"Copied Metal buffer" copy_source)
    in
    if Buffer.external_memory copied_buffer <> None
       || get (Buffer.label copied_buffer) <> Some "Copied Metal buffer"
    then fail "copied buffer ownership or label is wrong";
    let expected_copy = Bytes.sub copy_source 4 16 in
    Bytes.fill copy_source 4 16 '\000';
    if get (Buffer.read_bytes copied_buffer ~offset:0L ~length:16) <> expected_copy
    then fail "newBufferWithBytes did not retain an independent copy";
    ignore
      (expect_error Invalid_argument
         (Buffer.create_copy ~device ~storage:Buffer.Shared ~src_offset:(-1)
            copy_source));
    ignore
      (expect_error Invalid_argument
         (Buffer.create_copy ~device ~storage:Buffer.Shared ~length:0
            copy_source));
    ignore
      (expect_error Invalid_argument
         (Buffer.create_copy ~device ~storage:Buffer.Shared ~src_offset:24
            ~length:9 copy_source));
    get (Buffer.destroy copied_buffer);
    let page_size = get (Buffer.External.page_size ()) in
    if page_size <= 0 || page_size land (page_size - 1) <> 0 then
      fail "native VM page size is invalid";
    ignore
      (expect_error Invalid_argument (Buffer.External.create ~length:0L));
    ignore
      (expect_error Invalid_argument
         (Buffer.External.create ~length:(Int64.of_int (page_size - 1))));
    let external_memory =
      get (Buffer.External.create ~length:(Int64.of_int page_size))
    in
    if Buffer.External.length external_memory <> Int64.of_int page_size
       || Buffer.External.alignment external_memory <> Int64.of_int page_size
    then fail "external-memory page layout is wrong";
    if
      get (Buffer.External.read_bytes external_memory ~offset:0L ~length:16)
      <> Bytes.make 16 '\000'
    then fail "external memory was not initialized deterministically";
    get
      (Buffer.External.write_bytes external_memory ~dst_offset:0L (input_values ()));
    let before_no_copy = get (Release_queue.stats ()) in
    let no_copy_buffer =
      get
        (Buffer.create_no_copy ~device ~memory:external_memory
           ~storage:Buffer.Shared ~label:"No-copy Metal buffer" ())
    in
    (match Buffer.external_memory no_copy_buffer with
     | Some owner when owner == external_memory -> ()
     | Some _ | None -> fail "no-copy buffer lost its external owner");
    ignore (expect_error Parent_has_dependents (Device.destroy device));
    if get (Buffer.read_bytes no_copy_buffer ~offset:0L ~length:16)
       <> input_values ()
    then fail "no-copy buffer did not expose its external bytes";
    ignore
      (expect_error Parent_has_dependents
         (Buffer.External.read_bytes external_memory ~offset:0L ~length:1));
    ignore
      (expect_error Parent_has_dependents
         (Buffer.External.write_bytes external_memory ~dst_offset:0L
            (Bytes.make 1 '\000')));
    ignore
      (expect_error Parent_has_dependents
         (Buffer.External.destroy external_memory));
    ignore
      (expect_error Parent_has_dependents
         (Buffer.create_no_copy ~device ~memory:external_memory
            ~storage:Buffer.Shared ()));
    let private_external =
      get (Buffer.External.create ~length:(Int64.of_int page_size))
    in
    ignore
      (expect_error Unsupported
         (Buffer.create_no_copy ~device ~memory:private_external
            ~storage:Buffer.Private ()));
    get (Buffer.External.destroy private_external);
    let updated_external = Bytes.make 16 '\123' in
    get (Buffer.write_bytes no_copy_buffer ~dst_offset:0L updated_external);
    get (Buffer.destroy no_copy_buffer);
    let after_no_copy = get (Release_queue.stats ()) in
    if after_no_copy.external_deallocation_mismatches
       <> before_no_copy.external_deallocation_mismatches
    then
      fail
        "Metal no-copy deallocator mismatch (before=%Ld/%Ld after=%Ld/%Ld)"
        before_no_copy.external_deallocations
        before_no_copy.external_deallocation_mismatches
        after_no_copy.external_deallocations
        after_no_copy.external_deallocation_mismatches;
    if
      get (Buffer.External.read_bytes external_memory ~offset:0L ~length:16)
      <> updated_external
    then fail "external bytes did not survive the Metal buffer borrow";
    get (Buffer.External.destroy external_memory);
    ignore
      (expect_error Destroyed
         (Buffer.External.read_bytes external_memory ~offset:0L ~length:1));
    let before_external_finalizer = get (Release_queue.stats ()) in
    let allocate_unreleased_external_buffer () =
      let memory =
        get (Buffer.External.create ~length:(Int64.of_int page_size))
      in
      ignore
        (get
           (Buffer.create_no_copy ~device ~memory ~storage:Buffer.Shared ()))
    in
    allocate_unreleased_external_buffer ();
    let after_external_finalizer =
      settle_finalizers ~expected_live:before_external_finalizer.live_handles
    in
    if
      Int64.sub after_external_finalizer.total_created
        before_external_finalizer.total_created
      <> 2L
      || Int64.sub after_external_finalizer.total_released
           before_external_finalizer.total_released
         <> 2L
      || after_external_finalizer.external_deallocation_mismatches
         <> before_external_finalizer.external_deallocation_mismatches
    then
      fail
        "external/no-copy finalization did not release exactly two handles with a valid deallocator layout";
    let linear_alignment =
      get
        (Texture.minimum_buffer_alignment ~device ~kind:Texture.Texture_2d
           ~format:Texture.Rgba8_unorm)
    in
    let texture_buffer_alignment =
      get
        (Texture.minimum_buffer_alignment ~device
           ~kind:Texture.Texture_buffer ~format:Texture.Rgba8_unorm)
    in
    if
      linear_alignment <= 0L
      || Int64.logand linear_alignment (Int64.pred linear_alignment) <> 0L
      || texture_buffer_alignment <= 0L
      || Int64.logand texture_buffer_alignment
           (Int64.pred texture_buffer_alignment)
         <> 0L
      || linear_alignment > Int64.of_int max_int
      || texture_buffer_alignment > Int64.of_int max_int
    then fail "buffer-backed texture alignments are invalid";
    ignore
      (expect_error Invalid_argument
         (Texture.minimum_buffer_alignment ~device ~kind:Texture.Texture_3d
            ~format:Texture.Rgba8_unorm));
    ignore
      (expect_error Invalid_argument
         (Texture.minimum_buffer_alignment ~device ~kind:Texture.Texture_2d
            ~format:Texture.Depth32_float));
    let linear_width = 4 in
    let linear_height = 4 in
    let linear_row_pitch =
      align_up (Int64.of_int (linear_width * 4)) linear_alignment
      |> Int64.to_int
    in
    let linear_offset = linear_alignment in
    let linear_length =
      Int64.add linear_offset
        (Int64.mul (Int64.of_int linear_row_pitch)
           (Int64.of_int linear_height))
    in
    let linear_buffer =
      get
        (Buffer.create ~device ~length:linear_length ~storage:Buffer.Shared
           ~label:"Linear texture buffer" ())
    in
    let linear_descriptor =
      Texture.descriptor_2d ~storage:Buffer.Shared
        ~usage:[ Texture.Shader_read; Texture.Pixel_format_view ]
        ~label:"Buffer-backed texture" ~format:Texture.Rgba8_unorm
        ~width:linear_width ~height:linear_height ()
    in
    let linear_bytes = Bytes.make (linear_row_pitch * linear_height) '\000' in
    for row = 0 to linear_height - 1 do
      for column = 0 to (linear_width * 4) - 1 do
        Bytes.set_uint8 linear_bytes ((row * linear_row_pitch) + column)
          ((row * 31 + column) land 0xff)
      done
    done;
    get (Buffer.write_bytes linear_buffer ~dst_offset:linear_offset linear_bytes);
    let linear_texture =
      get
        (Texture.create_from_buffer ~buffer:linear_buffer ~offset:linear_offset
           ~bytes_per_row:linear_row_pitch linear_descriptor)
    in
    (match Texture.buffer_backing linear_texture with
     | Some backing
       when backing.buffer == linear_buffer
            && backing.offset = linear_offset
            && backing.bytes_per_row = linear_row_pitch -> ()
     | Some _ | None -> fail "buffer-backed texture lost its checked layout");
    if Texture.heap_offset linear_texture <> None
       || get (Texture.label linear_texture) <> Some "Buffer-backed texture"
       || get (Texture.purgeable_state linear_texture) <> Nonvolatile
       || get (Texture.is_aliasable linear_texture)
    then fail "buffer-backed texture resource properties are wrong";
    let linear_region : Texture.region =
      { x = 0
      ; y = 0
      ; z = 0
      ; width = linear_width
      ; height = linear_height
      ; depth = 1
      }
    in
    if
      get
        (Texture.read_bytes linear_texture ~region:linear_region ~mip_level:0
           ~slice:0 ~bytes_per_row:linear_row_pitch
           ~bytes_per_image:(linear_row_pitch * linear_height))
      <> linear_bytes
    then fail "backing-buffer writes were not visible through the texture";
    let replacement_linear_bytes = Bytes.copy linear_bytes in
    for row = 0 to linear_height - 1 do
      for column = 0 to (linear_width * 4) - 1 do
        Bytes.set_uint8 replacement_linear_bytes
          ((row * linear_row_pitch) + column)
          ((255 - row - column) land 0xff)
      done
    done;
    get
      (Texture.write_bytes linear_texture ~region:linear_region ~mip_level:0
         ~slice:0 ~bytes_per_row:linear_row_pitch
         ~bytes_per_image:(linear_row_pitch * linear_height)
         replacement_linear_bytes);
    if
      get
        (Buffer.read_bytes linear_buffer ~offset:linear_offset
           ~length:(Bytes.length replacement_linear_bytes))
      <> replacement_linear_bytes
    then fail "texture writes were not visible through the backing buffer";
    let linear_view =
      get
        (Texture.create_view linear_texture
           ~format:Texture.Rgba8_unorm_srgb ~base_mip:0 ~mip_count:1
           ~base_slice:0 ~slice_count:1 ())
    in
    (match Texture.buffer_backing linear_view with
     | Some backing when backing.buffer == linear_buffer -> ()
     | Some _ | None -> fail "texture view lost its backing-buffer ancestry");
    ignore (expect_error Parent_has_dependents (Buffer.destroy linear_buffer));
    ignore
      (expect_error Parent_has_dependents
         (Buffer.set_purgeable_state linear_buffer Volatile));
    ignore
      (expect_error Parent_has_dependents (Buffer.make_aliasable linear_buffer));
    ignore
      (expect_error Parent_has_dependents (Texture.destroy linear_texture));
    get (Texture.destroy linear_view);
    ignore
      (expect_error Invalid_state
         (Texture.set_purgeable_state linear_texture Volatile));
    ignore (expect_error Invalid_state (Texture.make_aliasable linear_texture));
    let before_invalid_linear_textures = get (Release_queue.stats ()) in
    ignore
      (expect_error Invalid_argument
         (Texture.create_from_buffer ~buffer:linear_buffer ~offset:1L
            ~bytes_per_row:linear_row_pitch linear_descriptor));
    ignore
      (expect_error Invalid_argument
         (Texture.create_from_buffer ~buffer:linear_buffer ~offset:linear_offset
            ~bytes_per_row:(linear_row_pitch + 1) linear_descriptor));
    ignore
      (expect_error Invalid_argument
         (Texture.create_from_buffer ~buffer:linear_buffer ~offset:linear_offset
            ~bytes_per_row:linear_row_pitch
            { linear_descriptor with height = linear_height + 1 }));
    ignore
      (expect_error Invalid_argument
         (Texture.create_from_buffer ~buffer:linear_buffer ~offset:linear_offset
            ~bytes_per_row:linear_row_pitch
            { linear_descriptor with storage = Buffer.Private }));
    ignore
      (expect_error Invalid_argument
         (Texture.create_from_buffer ~buffer:linear_buffer ~offset:linear_offset
            ~bytes_per_row:linear_row_pitch
            { linear_descriptor with format = Texture.Depth32_float }));
    ignore
      (expect_error Invalid_argument
         (Texture.create_from_buffer ~buffer:linear_buffer ~offset:linear_offset
            ~bytes_per_row:linear_row_pitch
            { linear_descriptor with kind = Texture.Texture_3d }));
    ignore
      (expect_error Invalid_argument
         (Texture.create_from_buffer ~buffer:linear_buffer ~offset:linear_offset
            ~bytes_per_row:linear_row_pitch
            { linear_descriptor with mip_levels = 2 }));
    ignore
      (expect_error Invalid_argument
         (Texture.create_from_buffer ~buffer:linear_buffer ~offset:linear_offset
            ~bytes_per_row:linear_row_pitch
            { linear_descriptor with label = Some "invalid\000label" }));
    ignore
      (expect_error Native_error
         (Texture.create_from_buffer ~buffer:linear_buffer ~offset:linear_offset
            ~bytes_per_row:linear_row_pitch
            { linear_descriptor with label = Some "\255" }));
    let after_invalid_linear_textures = get (Release_queue.stats ()) in
    if
      after_invalid_linear_textures.total_created
      <> before_invalid_linear_textures.total_created
      || after_invalid_linear_textures.live_handles
         <> before_invalid_linear_textures.live_handles
    then fail "invalid buffer-backed textures allocated partial native handles";
    let render_target_linear_descriptor : Texture.descriptor =
      { linear_descriptor with
        usage = [ Texture.Render_target ]
      ; label = None
      }
    in
    if get (Device.supports_family device Device.Apple1) then begin
      let render_target_linear_texture =
        get
          (Texture.create_from_buffer ~buffer:linear_buffer
             ~offset:linear_offset ~bytes_per_row:linear_row_pitch
             render_target_linear_descriptor)
      in
      get (Texture.destroy render_target_linear_texture)
    end
    else
      ignore
        (expect_error Unsupported
           (Texture.create_from_buffer ~buffer:linear_buffer
              ~offset:linear_offset ~bytes_per_row:linear_row_pitch
              render_target_linear_descriptor));
    let texture_buffer_row_pitch =
      align_up 16L texture_buffer_alignment |> Int64.to_int
    in
    let texture_buffer_source =
      get
        (Buffer.create ~device
           ~length:(Int64.of_int texture_buffer_row_pitch)
           ~storage:Buffer.Shared ())
    in
    let texture_buffer_descriptor : Texture.descriptor =
      { linear_descriptor with
        kind = Texture.Texture_buffer
      ; width = 4
      ; height = 1
      ; usage = [ Texture.Shader_read ]
      ; label = Some "Typed texture buffer"
      }
    in
    ignore
      (expect_error Invalid_argument
         (Texture.create ~device texture_buffer_descriptor));
    ignore
      (expect_error Invalid_argument
         (Heap.texture_size_and_align ~device texture_buffer_descriptor));
    let texture_buffer =
      get
        (Texture.create_from_buffer ~buffer:texture_buffer_source ~offset:0L
           ~bytes_per_row:texture_buffer_row_pitch texture_buffer_descriptor)
    in
    (match Texture.buffer_backing texture_buffer with
     | Some backing
       when backing.buffer == texture_buffer_source
            && backing.bytes_per_row = texture_buffer_row_pitch -> ()
     | Some _ | None -> fail "texture-buffer kind lost its backing layout");
    get (Texture.destroy texture_buffer);
    get (Buffer.destroy texture_buffer_source);
    List.iter
      (fun storage ->
        let buffer =
          get
            (Buffer.create ~device ~length:(Int64.of_int linear_row_pitch)
               ~storage ())
        in
        let descriptor : Texture.descriptor =
          { linear_descriptor with
            height = 1
          ; storage
          ; usage = [ Texture.Shader_read ]
          ; label = None
          }
        in
        let texture =
          get
            (Texture.create_from_buffer ~buffer ~offset:0L
               ~bytes_per_row:linear_row_pitch descriptor)
        in
        (match storage with
         | Buffer.Private ->
             ignore
               (expect_error Unsupported
                  (Texture.read_bytes texture
                     ~region:{ linear_region with height = 1 } ~mip_level:0
                     ~slice:0 ~bytes_per_row:linear_row_pitch
                     ~bytes_per_image:linear_row_pitch))
         | Buffer.Shared | Buffer.Managed -> ());
        get (Texture.destroy texture);
        get (Buffer.destroy buffer))
      [ Buffer.Managed; Buffer.Private ];
    let configured_linear_buffer =
      get
        (Buffer.create ~device ~length:(Int64.of_int linear_row_pitch)
           ~storage:Buffer.Shared ~cpu_cache:Buffer.Write_combined
           ~hazard_tracking:Buffer.Untracked ())
    in
    let configured_linear_texture =
      get
        (Texture.create_from_buffer ~buffer:configured_linear_buffer ~offset:0L
           ~bytes_per_row:linear_row_pitch
           { linear_descriptor with
             height = 1
           ; cpu_cache = Texture.Write_combined
           ; hazard_tracking = Texture.Untracked
           ; label = None
           })
    in
    if
      (Texture.descriptor configured_linear_texture).cpu_cache
      <> Texture.Write_combined
      || (Texture.descriptor configured_linear_texture).hazard_tracking
         <> Texture.Untracked
    then fail "configured buffer-backed texture modes are wrong";
    get (Texture.destroy configured_linear_texture);
    get (Buffer.destroy configured_linear_buffer);
    get (Texture.destroy linear_texture);
    get (Buffer.destroy linear_buffer);
    let external_texture_memory =
      get (Buffer.External.create ~length:(Int64.of_int page_size))
    in
    let external_texture_buffer =
      get
        (Buffer.create_no_copy ~device ~memory:external_texture_memory
           ~storage:Buffer.Shared ())
    in
    let external_linear_texture =
      get
        (Texture.create_from_buffer ~buffer:external_texture_buffer ~offset:0L
           ~bytes_per_row:linear_row_pitch
           { linear_descriptor with height = 1; label = None })
    in
    ignore
      (expect_error Parent_has_dependents
         (Buffer.External.destroy external_texture_memory));
    ignore
      (expect_error Parent_has_dependents
         (Buffer.destroy external_texture_buffer));
    get (Texture.destroy external_linear_texture);
    get (Buffer.destroy external_texture_buffer);
    get (Buffer.External.destroy external_texture_memory);
    let before_linear_finalizer = get (Release_queue.stats ()) in
    let allocate_unreleased_linear_texture () =
      let buffer =
        get
          (Buffer.create ~device ~length:(Int64.of_int linear_row_pitch)
             ~storage:Buffer.Shared ())
      in
      ignore
        (get
           (Texture.create_from_buffer ~buffer ~offset:0L
              ~bytes_per_row:linear_row_pitch
              { linear_descriptor with height = 1; label = None }))
    in
    allocate_unreleased_linear_texture ();
    let after_linear_finalizer =
      settle_finalizers ~expected_live:before_linear_finalizer.live_handles
    in
    if
      Int64.sub after_linear_finalizer.total_created
        before_linear_finalizer.total_created
      <> 2L
      || Int64.sub after_linear_finalizer.total_released
           before_linear_finalizer.total_released
         <> 2L
    then
      fail
        "buffer-backed texture finalization did not release its texture and backing buffer";
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
    if get (Texture.is_shareable private_texture) then
      fail "ordinary private texture unexpectedly became shareable";
    ignore
      (expect_error Invalid_state (Texture.shared_handle private_texture));
    get (Texture.destroy private_texture);
    ignore
      (expect_error Invalid_argument
         (Texture.create_shared ~device
            (Texture.descriptor_2d ~storage:Buffer.Shared
               ~format:Texture.Rgba8_unorm ~width:4 ~height:4 ())));
    let shared_texture_descriptor =
      Texture.descriptor_2d ~storage:Buffer.Private
        ~usage:[ Texture.Shader_read; Texture.Pixel_format_view ]
        ~label:"Metal shared texture" ~format:Texture.Rgba8_unorm ~width:4
        ~height:4 ()
    in
    let shared_texture =
      get (Texture.create_shared ~device shared_texture_descriptor)
    in
    if not (get (Texture.is_shareable shared_texture))
       || get (Texture.label shared_texture) <> Some "Metal shared texture"
    then fail "shared texture properties are wrong";
    let shared_texture_actual_descriptor = Texture.descriptor shared_texture in
    let shared_handle = get (Texture.shared_handle shared_texture) in
    if
      not (Device.same (Texture.Shared_handle.device shared_handle) device)
      || Texture.Shared_handle.generation shared_handle <= 0L
      || get (Texture.Shared_handle.label shared_handle)
         <> Some "Metal shared texture"
    then fail "shared texture handle properties are wrong";
    get (Texture.destroy shared_texture);
    let imported_texture =
      get (Texture.import_shared ~device shared_handle)
    in
    if not (get (Texture.is_shareable imported_texture))
       || Texture.descriptor imported_texture <> shared_texture_actual_descriptor
       || get (Texture.label imported_texture) <> Some "Metal shared texture"
    then fail "imported shared texture properties are wrong";
    get (Texture.Shared_handle.destroy shared_handle);
    ignore
      (expect_error Destroyed (Texture.Shared_handle.label shared_handle));
    ignore
      (expect_error Destroyed (Texture.import_shared ~device shared_handle));
    let replacement_shared_handle =
      get (Texture.shared_handle imported_texture)
    in
    get (Texture.Shared_handle.destroy replacement_shared_handle);
    get (Texture.destroy imported_texture);
    let before_shared_finalizer = get (Release_queue.stats ()) in
    let allocate_unreleased_shared_texture_graph () =
      let texture =
        get (Texture.create_shared ~device shared_texture_descriptor)
      in
      let handle = get (Texture.shared_handle texture) in
      ignore (get (Texture.import_shared ~device handle))
    in
    allocate_unreleased_shared_texture_graph ();
    let after_shared_finalizer =
      settle_finalizers ~expected_live:before_shared_finalizer.live_handles
    in
    if
      Int64.sub after_shared_finalizer.total_created
        before_shared_finalizer.total_created
      <> 3L
      || Int64.sub after_shared_finalizer.total_released
           before_shared_finalizer.total_released
         <> 3L
    then
      fail
        "shared texture finalization did not release its source, handle, and import";
    let before_invalid_io_surfaces = get (Release_queue.stats ()) in
    ignore
      (expect_error Invalid_argument
         (Texture.Io_surface.create ~width:0 ~height:4 ~bytes_per_element:4
            ()));
    ignore
      (expect_error Invalid_argument
         (Texture.Io_surface.create ~width:4 ~height:4 ~bytes_per_element:3
            ()));
    ignore
      (expect_error Invalid_argument
         (Texture.Io_surface.create ~width:max_int ~height:2
            ~bytes_per_element:16 ()));
    ignore
      (expect_error Invalid_argument
         (Texture.Io_surface.create_planar []));
    let after_invalid_io_surfaces = get (Release_queue.stats ()) in
    if
      after_invalid_io_surfaces.total_created
      <> before_invalid_io_surfaces.total_created
    then fail "invalid IOSurface creation allocated a native handle";
    let io_surface =
      get
        (Texture.Io_surface.create ~label:"Metal IOSurface" ~width:4
           ~height:4 ~bytes_per_element:4 ())
    in
    let io_plane = get (Texture.Io_surface.plane io_surface 0) in
    if
      Texture.Io_surface.id io_surface <= 0L
      || Texture.Io_surface.allocation_size io_surface < io_plane.size
      || Texture.Io_surface.planar io_surface
      || Texture.Io_surface.plane_count io_surface <> 1
      || Texture.Io_surface.generation io_surface <= 0L
      || get (Texture.Io_surface.label io_surface) <> Some "Metal IOSurface"
      || io_plane.width <> 4 || io_plane.height <> 4
      || io_plane.bytes_per_element <> 4 || io_plane.bytes_per_row < 16
    then fail "non-planar IOSurface properties are wrong";
    ignore
      (expect_error Invalid_argument
         (Texture.Io_surface.plane io_surface 1));
    ignore
      (expect_error Invalid_argument
         (Texture.Io_surface.read_bytes io_surface ~plane:0 ~offset:io_plane.size
            ~length:1));
    ignore
      (expect_error Invalid_argument
         (Texture.Io_surface.write_bytes io_surface ~plane:0 ~src_offset:1
            ~dst_offset:0L Bytes.empty));
    let io_initial = Bytes.make (Int64.to_int io_plane.size) '\090' in
    get
      (Texture.Io_surface.write_bytes io_surface ~plane:0 ~dst_offset:0L
         io_initial);
    let io_descriptor =
      Texture.descriptor_2d ~storage:Buffer.Shared
        ~usage:[ Texture.Shader_read; Texture.Pixel_format_view ]
        ~label:"Metal IOSurface texture" ~format:Texture.Rgba8_unorm ~width:4
        ~height:4 ()
    in
    let before_invalid_io_textures = get (Release_queue.stats ()) in
    ignore
      (expect_error Invalid_argument
         (Texture.create_from_io_surface ~device ~surface:io_surface ~plane:(-1)
            io_descriptor));
    ignore
      (expect_error Invalid_argument
         (Texture.create_from_io_surface ~device ~surface:io_surface ~plane:0
            { io_descriptor with width = 5 }));
    ignore
      (expect_error Invalid_argument
         (Texture.create_from_io_surface ~device ~surface:io_surface ~plane:0
            { io_descriptor with format = Texture.Rg8_unorm }));
    ignore
      (expect_error Invalid_argument
         (Texture.create_from_io_surface ~device ~surface:io_surface ~plane:0
            { io_descriptor with storage = Buffer.Private }));
    ignore
      (expect_error Invalid_argument
         (Texture.create_from_io_surface ~device ~surface:io_surface ~plane:0
            { io_descriptor with mip_levels = 2 }));
    let after_invalid_io_textures = get (Release_queue.stats ()) in
    if
      after_invalid_io_textures.total_created
      <> before_invalid_io_textures.total_created
    then fail "invalid IOSurface texture creation allocated a native handle";
    let io_texture =
      get
        (Texture.create_from_io_surface ~device ~surface:io_surface ~plane:0
           io_descriptor)
    in
    if get (Texture.label io_texture) <> Some "Metal IOSurface texture"
       || get (Texture.is_shareable io_texture)
    then fail "IOSurface texture properties are wrong";
    (match Texture.io_surface_backing io_texture with
     | Some backing when backing.surface == io_surface && backing.plane = 0 -> ()
     | Some _ | None -> fail "IOSurface texture lost its typed ancestry");
    let io_texture_initial =
      get
        (Texture.read_bytes io_texture ~region:full_region ~mip_level:0 ~slice:0
           ~bytes_per_row:16 ~bytes_per_image:64)
    in
    if io_texture_initial <> Bytes.make 64 '\090' then
      fail "IOSurface bytes were not visible through the Metal texture";
    let io_replacement = Bytes.make 64 '\051' in
    get
      (Texture.write_bytes io_texture ~region:full_region ~mip_level:0 ~slice:0
         ~bytes_per_row:16 ~bytes_per_image:64 io_replacement);
    let io_surface_after_texture =
      get
        (Texture.Io_surface.read_bytes io_surface ~plane:0 ~offset:0L
           ~length:(Int64.to_int io_plane.size))
    in
    for row = 0 to 3 do
      if Bytes.sub io_surface_after_texture (row * io_plane.bytes_per_row) 16
         <> Bytes.make 16 '\051'
      then fail "Metal texture writes did not reach the IOSurface plane"
    done;
    ignore
      (expect_error Invalid_state (Texture.purgeable_state io_texture));
    ignore (expect_error Invalid_state (Texture.make_aliasable io_texture));
    let io_view =
      get
        (Texture.create_view io_texture ~format:Texture.Rgba8_unorm_srgb
           ~base_mip:0 ~mip_count:1 ~base_slice:0 ~slice_count:1 ())
    in
    (match Texture.io_surface_backing io_view with
     | Some backing when backing.surface == io_surface && backing.plane = 0 -> ()
     | Some _ | None -> fail "IOSurface texture view lost its typed ancestry");
    ignore
      (expect_error Parent_has_dependents
         (Texture.Io_surface.destroy io_surface));
    ignore (expect_error Parent_has_dependents (Texture.destroy io_texture));
    get (Texture.destroy io_view);
    get (Texture.destroy io_texture);
    get (Texture.Io_surface.destroy io_surface);
    get (Texture.Io_surface.destroy io_surface);
    ignore
      (expect_error Destroyed (Texture.Io_surface.label io_surface));
    ignore
      (expect_error Destroyed (Texture.Io_surface.plane io_surface 0));
    let planar_surface =
      get
        (Texture.Io_surface.create_planar ~label:"Metal planar IOSurface"
           [ Texture.Io_surface.plane_descriptor ~width:4 ~height:4
               ~bytes_per_element:1
           ; Texture.Io_surface.plane_descriptor ~width:2 ~height:2
               ~bytes_per_element:2
           ])
    in
    if not (Texture.Io_surface.planar planar_surface)
       || Texture.Io_surface.plane_count planar_surface <> 2
    then fail "planar IOSurface cardinality is wrong";
    let planar_first = get (Texture.Io_surface.plane planar_surface 0) in
    let planar_second = get (Texture.Io_surface.plane planar_surface 1) in
    get
      (Texture.Io_surface.write_bytes planar_surface ~plane:0 ~dst_offset:0L
         (Bytes.make (Int64.to_int planar_first.size) '\017'));
    get
      (Texture.Io_surface.write_bytes planar_surface ~plane:1 ~dst_offset:0L
         (Bytes.make (Int64.to_int planar_second.size) '\034'));
    let planar_first_texture =
      get
        (Texture.create_from_io_surface ~device ~surface:planar_surface ~plane:0
           (Texture.descriptor_2d ~storage:Buffer.Shared
              ~format:Texture.R8_unorm ~width:4 ~height:4 ()))
    in
    let planar_second_texture =
      get
        (Texture.create_from_io_surface ~device ~surface:planar_surface ~plane:1
           (Texture.descriptor_2d ~storage:Buffer.Shared
              ~format:Texture.Rg8_unorm ~width:2 ~height:2 ()))
    in
    let planar_first_region : Texture.region =
      { x = 0; y = 0; z = 0; width = 4; height = 4; depth = 1 }
    in
    let planar_second_region : Texture.region =
      { x = 0; y = 0; z = 0; width = 2; height = 2; depth = 1 }
    in
    if
      get
        (Texture.read_bytes planar_first_texture ~region:planar_first_region
           ~mip_level:0 ~slice:0 ~bytes_per_row:4 ~bytes_per_image:16)
      <> Bytes.make 16 '\017'
      || get
           (Texture.read_bytes planar_second_texture ~region:planar_second_region
              ~mip_level:0 ~slice:0 ~bytes_per_row:4 ~bytes_per_image:8)
         <> Bytes.make 8 '\034'
    then fail "planar IOSurface textures did not expose their selected planes";
    ignore
      (expect_error Parent_has_dependents
         (Texture.Io_surface.destroy planar_surface));
    get (Texture.destroy planar_second_texture);
    get (Texture.destroy planar_first_texture);
    get (Texture.Io_surface.destroy planar_surface);
    let before_io_finalizer = get (Release_queue.stats ()) in
    let allocate_unreleased_io_surface_graph () =
      let surface =
        get
          (Texture.Io_surface.create ~width:1 ~height:1 ~bytes_per_element:4
             ())
      in
      ignore
        (get
           (Texture.create_from_io_surface ~device ~surface ~plane:0
              (Texture.descriptor_2d ~storage:Buffer.Shared
                 ~format:Texture.Rgba8_unorm ~width:1 ~height:1 ())))
    in
    allocate_unreleased_io_surface_graph ();
    let after_io_finalizer =
      settle_finalizers ~expected_live:before_io_finalizer.live_handles
    in
    if
      Int64.sub after_io_finalizer.total_created
        before_io_finalizer.total_created
      <> 2L
      || Int64.sub after_io_finalizer.total_released
           before_io_finalizer.total_released
         <> 2L
    then fail "IOSurface texture finalization did not release both handles";
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
    let linear_heap_layout =
      get
        (Heap.buffer_size_and_align ~device ~length:(Int64.of_int linear_row_pitch)
           ~storage:Buffer.Shared ())
    in
    let linear_heap =
      get
        (Heap.create ~device
           (Heap.make_descriptor ~storage:Buffer.Shared
              ~size:linear_heap_layout.size ()))
    in
    let linear_heap_buffer =
      get
        (Heap.create_buffer linear_heap ~length:(Int64.of_int linear_row_pitch)
           ())
    in
    let linear_heap_descriptor : Texture.descriptor =
      { linear_descriptor with
        height = 1
      ; usage = [ Texture.Shader_read ]
      ; label = Some "Heap-buffer-backed texture"
      }
    in
    let linear_heap_texture =
      get
        (Texture.create_from_buffer ~buffer:linear_heap_buffer ~offset:0L
           ~bytes_per_row:linear_row_pitch linear_heap_descriptor)
    in
    if Texture.heap_offset linear_heap_texture <> None
       || (Texture.descriptor linear_heap_texture).hazard_tracking
          <> Texture.Untracked
    then fail "heap-buffer-backed texture lost its heap resource properties";
    ignore
      (expect_error Parent_has_dependents (Buffer.destroy linear_heap_buffer));
    ignore (expect_error Parent_has_dependents (Heap.destroy linear_heap));
    ignore (get (Heap.set_purgeable_state linear_heap Volatile));
    (match get (Heap.purgeable_state linear_heap) with
     | Nonvolatile -> ()
     | Volatile | Empty ->
         ignore
           (expect_error Invalid_state
              (Texture.read_bytes linear_heap_texture
                 ~region:{ linear_region with height = 1 } ~mip_level:0
                 ~slice:0 ~bytes_per_row:linear_row_pitch
                 ~bytes_per_image:linear_row_pitch));
         ignore (get (Heap.set_purgeable_state linear_heap Nonvolatile)));
    get (Texture.destroy linear_heap_texture);
    get (Buffer.destroy linear_heap_buffer);
    get (Heap.destroy linear_heap);
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
    let queue_residency_sets =
      if residency_sets_supported then begin
        let first =
          get
            (Residency_set.create ~device
               (Residency_set.make_descriptor ~label:"Queue residency one" ()))
        in
        let second =
          get
            (Residency_set.create ~device
               (Residency_set.make_descriptor ~label:"Queue residency two" ()))
        in
        get (Command_queue.add_residency_set queue first);
        get (Command_queue.add_residency_sets queue [ second ]);
        ignore
          (expect_error Invalid_argument
             (Command_queue.add_residency_sets queue [ first; first ]));
        ignore (expect_error Parent_has_dependents (Residency_set.destroy first));
        ignore (expect_error Parent_has_dependents (Residency_set.destroy second));
        get (Command_queue.remove_residency_set queue first);
        get (Command_queue.remove_residency_sets queue [ second ]);
        get (Command_queue.add_residency_set queue first);
        get (Command_queue.add_residency_sets queue [ second ]);
        Some (first, second)
      end
      else None
    in
    let commands =
      get (Command_buffer.create queue ~label:"Metal compute conformance" ())
    in
    Option.iter
      (fun (first, second) ->
        get (Command_buffer.use_residency_set commands first);
        get (Command_buffer.use_residency_sets commands [ second ]);
        ignore
          (expect_error Invalid_argument
             (Command_buffer.use_residency_sets commands [ first; first ]));
        get (Command_queue.remove_residency_set queue first);
        ignore
          (expect_error Parent_has_dependents (Residency_set.destroy first));
        ignore
          (expect_error Parent_has_dependents (Residency_set.destroy second)))
      queue_residency_sets;
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
    Option.iter
      (fun (first, second) ->
        ignore
          (expect_error Invalid_state
             (Command_buffer.use_residency_set commands first));
        get (Residency_set.destroy first);
        ignore
          (expect_error Parent_has_dependents (Residency_set.destroy second)))
      queue_residency_sets;
    Buffer.read_bytes buffer ~offset:0L ~length:16 |> get |> check_values;
    get (Buffer.destroy buffer);
    get (Command_buffer.destroy commands);
    get (Command_queue.destroy queue);
    Option.iter
      (fun (_, second) -> get (Residency_set.destroy second))
      queue_residency_sets;
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
    if stats.pending <> 0 || stats.dropped <> 0 || stats.live_handles <> 0
       || stats.external_deallocation_mismatches <> 0L
    then
      fail
        "Metal release accounting did not settle (%d pending, %d dropped, %d live, %Ld external deallocations, %Ld mismatches)"
        stats.pending stats.dropped stats.live_handles
        stats.external_deallocations
        stats.external_deallocation_mismatches;
    Printf.printf
      "Metal ARC/device/heap/buffer/texture/sampler/sparse/resource-state/blit/residency/runtime-shader/compute conformance passed on %s\n%!"
      info.name
  end
