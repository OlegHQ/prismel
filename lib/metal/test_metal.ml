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

let contains_substring text pattern =
  let text_length = String.length text
  and pattern_length = String.length pattern in
  let rec search offset =
    if pattern_length = 0 then true
    else if offset > text_length - pattern_length then false
    else if String.sub text offset pattern_length = pattern then true
    else search (offset + 1)
  in
  pattern_length <= text_length && search 0

let shader_source =
  {|
#include <metal_stdlib>
using namespace metal;

kernel void increment(device uint *values [[buffer(0)]],
                      uint index [[thread_position_in_grid]]) {
  values[index] += 1;
}

constant uint increment_amount [[function_constant(0)]];
constant bool apply_twice [[function_constant(1)]];

kernel void specialized_increment(device uint *values [[buffer(0)]],
                                  uint index [[thread_position_in_grid]]) {
  values[index] += apply_twice ? increment_amount * 2u : increment_amount;
}

[[visible]] uint linked_identity(uint value) {
  return value;
}

constant char scalar_i8 [[function_constant(2)]];
constant uchar scalar_u8 [[function_constant(3)]];
constant short scalar_i16 [[function_constant(4)]];
constant ushort scalar_u16 [[function_constant(5)]];
constant int scalar_i32 [[function_constant(6)]];
constant uint scalar_u32 [[function_constant(7)]];
constant long scalar_i64 [[function_constant(8)]];
constant ulong scalar_u64 [[function_constant(9)]];
constant half scalar_f16 [[function_constant(10)]];
constant float scalar_f32 [[function_constant(11)]];
constant bool scalar_bool [[function_constant(12)]];

kernel void scalar_constant_sum(device uint *result [[buffer(0)]]) {
  result[0] = uint(scalar_i8) + uint(scalar_u8) + uint(scalar_i16)
      + uint(scalar_u16) + uint(scalar_i32) + scalar_u32
      + uint(scalar_i64) + uint(scalar_u64) + uint(scalar_f16)
      + uint(scalar_f32) + uint(scalar_bool);
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

let placement_sparse_shader_source =
  {|
#include <metal_stdlib>
using namespace metal;

kernel void placement_buffer_write(device uint *target [[buffer(0)]]) {
  target[0] = 0x5a17c0deu;
}

kernel void placement_buffer_read(device const uint *source [[buffer(0)]],
                                  device uint *result [[buffer(1)]]) {
  result[0] = source[0];
}

kernel void placement_texture_write(
    texture2d<uint, access::write> target [[texture(0)]]) {
  target.write(uint4(83u), uint2(0u));
}
|}

let texture_swizzle_shader_source =
  {|
#include <metal_stdlib>
using namespace metal;

kernel void read_swizzle(texture2d<float, access::sample> source [[texture(0)]],
                         device uint4 *result [[buffer(0)]]) {
  constexpr sampler nearest_sampler(coord::pixel, filter::nearest);
  result[0] = uint4(round(source.sample(nearest_sampler, float2(0.5f)) * 255.0f));
}
|}

let dynamic_library_source =
  {|
#include <metal_stdlib>
using namespace metal;

extern "C" uint prismel_dynamic_add(uint value) {
  return value + 13u;
}
|}

let dynamic_client_source =
  {|
#include <metal_stdlib>
using namespace metal;

extern "C" uint prismel_dynamic_add(uint value);

kernel void call_dynamic_library(device uint *values [[buffer(0)]],
                                 uint index [[thread_position_in_grid]]) {
  values[index] = prismel_dynamic_add(values[index]);
}
|}

let render_shader_source =
  {|
#include <metal_stdlib>
using namespace metal;

struct PrismelVertexOut {
  float4 position [[position]];
};

vertex PrismelVertexOut prismel_vertex(
    uint vertex_id [[vertex_id]],
    constant float2 &offset [[buffer(0)]]) {
  constexpr float2 positions[3] = {
    float2(-1.0f, -1.0f),
    float2(3.0f, -1.0f),
    float2(-1.0f, 3.0f)
  };
  PrismelVertexOut result;
  result.position = float4(positions[vertex_id] + offset, 0.0f, 1.0f);
  return result;
}

vertex void prismel_vertex_only(uint vertex_id [[vertex_id]]) {
  (void)vertex_id;
}

fragment float4 prismel_fragment(constant float4 &tint [[buffer(1)]]) {
  return tint;
}

vertex PrismelVertexOut prismel_fullscreen_vertex(uint vertex_id [[vertex_id]]) {
  constexpr float2 positions[3] = {
    float2(-1.0f, -1.0f),
    float2(3.0f, -1.0f),
    float2(-1.0f, 3.0f)
  };
  PrismelVertexOut result;
  result.position = float4(positions[vertex_id], 0.0f, 1.0f);
  return result;
}

fragment float4 prismel_green_fragment() {
  return float4(0.0f, 1.0f, 0.0f, 1.0f);
}
|}

let mesh_shader_source =
  {|
#include <metal_stdlib>
using namespace metal;

struct PrismelMeshVertex {
  float4 position [[position]];
  float4 color;
};

using PrismelTriangleMesh = metal::mesh<
    PrismelMeshVertex,
    void,
    3,
    1,
    metal::topology::triangle>;

struct PrismelMeshPayload {
  float2 offset;
};

[[object]]
void prismel_object(
    object_data PrismelMeshPayload *payload [[payload]],
    constant float2 &source_offset [[buffer(0)]],
    uint thread_index [[thread_index_in_threadgroup]],
    mesh_grid_properties grid) {
  if (thread_index == 0) {
    payload->offset = source_offset;
    grid.set_threadgroups_per_grid(uint3(1, 1, 1));
  }
}

[[mesh]]
void prismel_mesh(
    PrismelTriangleMesh output_mesh,
    constant float2 &offset [[buffer(2)]],
    uint thread_index [[thread_index_in_threadgroup]]) {
  constexpr float2 positions[3] = {
    float2(-1.0f, -1.0f),
    float2(3.0f, -1.0f),
    float2(-1.0f, 3.0f)
  };
  if (thread_index < 3) {
    PrismelMeshVertex output_vertex;
    output_vertex.position =
        float4(positions[thread_index] + offset, 0.0f, 1.0f);
    output_vertex.color = float4(0.2f, 0.4f, 0.8f, 1.0f);
    output_mesh.set_vertex(thread_index, output_vertex);
    output_mesh.set_index(thread_index, thread_index);
  }
  if (thread_index == 0) {
    output_mesh.set_primitive_count(1);
  }
}

[[mesh]]
void prismel_object_mesh(
    PrismelTriangleMesh output_mesh,
    const object_data PrismelMeshPayload *payload [[payload]],
    constant float4 &mesh_color [[buffer(1)]],
    uint thread_index [[thread_index_in_threadgroup]]) {
  constexpr float2 positions[3] = {
    float2(-1.0f, -1.0f),
    float2(3.0f, -1.0f),
    float2(-1.0f, 3.0f)
  };
  if (thread_index < 3) {
    PrismelMeshVertex output_vertex;
    output_vertex.position =
        float4(positions[thread_index] + payload->offset, 0.0f, 1.0f);
    output_vertex.color = mesh_color;
    output_mesh.set_vertex(thread_index, output_vertex);
    output_mesh.set_index(thread_index, thread_index);
  }
  if (thread_index == 0) {
    output_mesh.set_primitive_count(1);
  }
}

fragment float4 prismel_mesh_fragment(
    PrismelMeshVertex input [[stage_in]],
    constant float4 &tint [[buffer(3)]]) {
  return input.color * tint;
}
|}

let tile_shader_source =
  {|
#include <metal_stdlib>
using namespace metal;

kernel void prismel_tile(
    device uint *tile_output [[buffer(4)]],
    ushort2 local_position [[thread_position_in_threadgroup]]) {
  if (local_position.x == 0 && local_position.y == 0) {
    tile_output[0] = 23u;
  }
}

vertex float4 prismel_not_tile(uint vertex_id [[vertex_id]]) {
  return float4(float(vertex_id), 0.0f, 0.0f, 1.0f);
}
|}

let uncaptured_visible_source =
  {|
#include <metal_stdlib>
using namespace metal;

[[visible]] uint never_captured(uint value) {
  return value + 37u;
}
|}

let static_client_source =
  {|
#include <metal_stdlib>
using namespace metal;

uint prismel_local_add(uint value) {
  return value + 17u;
}

kernel void call_static_library(device uint *values [[buffer(0)]]) {
  values[0] = prismel_local_add(values[0]);
}
|}

let static_provider_source =
  {|
#include <metal_stdlib>
using namespace metal;

[[visible]] uint public_static_identity(uint value) {
  return value;
}

[[visible]] uint private_static_identity(uint value) {
  return value;
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

let test_texture_swizzle_and_compression device =
  let base_swizzle =
    Texture.make_swizzle ~red:Texture.Red ~green:Texture.One
      ~blue:Texture.One ~alpha:Texture.Green
  in
  let descriptor =
    Texture.descriptor_2d ~storage:Buffer.Shared ~swizzle:base_swizzle
      ~format:Texture.Rgba8_unorm ~width:1 ~height:1 ()
  in
  let texture = get (Texture.create ~device descriptor) in
  if (Texture.descriptor texture).swizzle <> base_swizzle then
    fail "base texture swizzle did not round-trip";
  let pixel = Bytes.of_string "\010\020\030\040" in
  let region : Texture.region =
    { x = 0; y = 0; z = 0; width = 1; height = 1; depth = 1 }
  in
  get
    (Texture.write_bytes texture ~region ~mip_level:0 ~slice:0
       ~bytes_per_row:4 ~bytes_per_image:4 pixel);
  let view_swizzle =
    Texture.make_swizzle ~red:Texture.Red ~green:Texture.Green
      ~blue:Texture.Alpha ~alpha:Texture.Blue
  in
  let expected_view_swizzle =
    Texture.make_swizzle ~red:Texture.Red ~green:Texture.One
      ~blue:Texture.Green ~alpha:Texture.One
  in
  let view =
    get
      (Texture.create_view texture ~format:Texture.Rgba8_unorm ~base_mip:0
         ~mip_count:1 ~base_slice:0 ~slice_count:1 ~swizzle:view_swizzle ())
  in
  if (Texture.descriptor view).swizzle <> expected_view_swizzle then
    fail "texture-view swizzle composition is wrong";
  let output =
    get (Buffer.create ~device ~length:16L ~storage:Buffer.Shared ())
  in
  let library =
    get (Library.compile_source ~device texture_swizzle_shader_source)
  in
  let function_ = get (Function.find ~library "read_swizzle") in
  let pipeline = get (Compute_pipeline.create function_) in
  let queue = get (Command_queue.create device) in
  let read name source expected =
    let commands = get (Command_buffer.create queue ()) in
    let encoder = get (Compute_encoder.create commands) in
    get (Compute_encoder.set_pipeline encoder pipeline);
    get (Compute_encoder.set_texture encoder ~index:0 source);
    get (Compute_encoder.set_buffer encoder ~index:0 ~offset:0L output);
    get
      (Compute_encoder.dispatch_threads encoder ~threads:(1, 1, 1)
         ~threadgroup:(1, 1, 1));
    get (Compute_encoder.end_encoding encoder);
    complete_commands commands;
    let bytes = get (Buffer.read_bytes output ~offset:0L ~length:16) in
    let actual =
      Array.init 4 (fun index ->
        Bytes.get_int32_le bytes (index * 4) |> Int32.to_int)
    in
    if actual <> expected then
      fail "%s texture swizzle: expected [%s], got [%s]" name
        (expected |> Array.to_list |> List.map string_of_int
         |> String.concat "; ")
        (actual |> Array.to_list |> List.map string_of_int |> String.concat "; ")
  in
  read "base" texture [| 10; 255; 255; 20 |];
  read "view" view [| 10; 255; 20; 255 |];
  get (Command_queue.destroy queue);
  get (Compute_pipeline.destroy pipeline);
  get (Function.destroy function_);
  get (Library.destroy library);
  get (Buffer.destroy output);
  get (Texture.destroy view);
  get (Texture.destroy texture);
  let before_invalid_swizzle = get (Release_queue.stats ()) in
  List.iter
    (fun usage ->
      ignore
        (expect_error Invalid_argument
           (Texture.create ~device
              (Texture.descriptor_2d ~storage:Buffer.Private ~usage
                 ~swizzle:base_swizzle ~format:Texture.Rgba8_unorm ~width:4
                 ~height:4 ()))))
    [ [ Texture.Shader_write ]; [ Texture.Shader_atomic ] ];
  let after_invalid_swizzle = get (Release_queue.stats ()) in
  if
    after_invalid_swizzle.total_created
    <> before_invalid_swizzle.total_created
  then fail "invalid writable swizzles allocated native handles";
  let writable =
    get
      (Texture.create ~device
         (Texture.descriptor_2d ~storage:Buffer.Private
            ~usage:[ Texture.Shader_write ] ~format:Texture.Rgba8_unorm
            ~width:4 ~height:4 ()))
  in
  let before_invalid_view = get (Release_queue.stats ()) in
  ignore
    (expect_error Invalid_argument
       (Texture.create_view writable ~format:Texture.Rgba8_unorm ~base_mip:0
          ~mip_count:1 ~base_slice:0 ~slice_count:1 ~swizzle:base_swizzle ()));
  let after_invalid_view = get (Release_queue.stats ()) in
  if after_invalid_view.total_created <> before_invalid_view.total_created then
    fail "invalid writable swizzled view allocated a native handle";
  get (Texture.destroy writable);
  let lossy_supported =
    get (Device.supports_lossy_texture_compression device)
  in
  if lossy_supported && not (get (Device.supports_family device Device.Apple8))
  then fail "lossy texture compression escaped its Apple8 hardware gate";
  let lossy_descriptor =
    Texture.descriptor_2d ~storage:Buffer.Private
      ~usage:[ Texture.Render_target ] ~compression:Texture.Lossy
      ~format:Texture.Rgba8_unorm ~width:64 ~height:64 ()
  in
  let before_invalid = get (Release_queue.stats ()) in
  [ { lossy_descriptor with storage = Buffer.Shared }
  ; { lossy_descriptor with allow_gpu_optimized_contents = false }
  ; { lossy_descriptor with usage = [ Texture.Pixel_format_view ] }
  ; { lossy_descriptor with usage = [ Texture.Shader_write ] }
  ; { lossy_descriptor with usage = [ Texture.Shader_atomic ] }
  ; { lossy_descriptor with
      kind = Texture.Texture_1d
    ; height = 1
    }
  ; { lossy_descriptor with format = Texture.Rg11b10_float }
  ; { lossy_descriptor with format = Texture.Astc_4x4_ldr }
  ]
  |> List.iter (fun invalid ->
    ignore (expect_error Invalid_argument (Texture.create ~device invalid)));
  let after_invalid = get (Release_queue.stats ()) in
  if after_invalid.total_created <> before_invalid.total_created then
    fail "invalid lossy texture descriptors allocated native handles";
  if lossy_supported then begin
    let lossy = get (Texture.create ~device lossy_descriptor) in
    if (Texture.descriptor lossy).compression <> Texture.Lossy then
      fail "lossy texture compression did not round-trip";
    get (Texture.destroy lossy)
  end
  else begin
    let before_unsupported = get (Release_queue.stats ()) in
    ignore
      (expect_error Unsupported (Texture.create ~device lossy_descriptor));
    let after_unsupported = get (Release_queue.stats ()) in
    if after_unsupported.total_created <> before_unsupported.total_created then
      fail "unsupported lossy texture allocated a native handle"
  end

let test_placement_sparse_resources device =
  let supported = get (Device.supports_placement_sparse device) in
  let page_sizes =
    [ Sparse_page_size.Page_16_kib
    ; Sparse_page_size.Page_64_kib
    ; Sparse_page_size.Page_256_kib
    ]
  in
  let descriptor =
    Texture.descriptor_2d ~mipmapped:true ~storage:Buffer.Private
      ~usage:
        [ Texture.Shader_read; Texture.Shader_write
        ; Texture.Pixel_format_view
        ]
      ~label:"Metal placement sparse texture" ~format:Texture.R8_uint
      ~width:256 ~height:256 ()
  in
  if not supported then begin
    let before = get (Release_queue.stats ()) in
    ignore
      (expect_error Unsupported
         (Buffer.create_placement_sparse ~device
            ~page_size:Sparse_page_size.Page_16_kib ~length:16_384L
            ~storage:Buffer.Private ()));
    ignore
      (expect_error Unsupported
         (Texture.create_placement_sparse ~device
            ~page_size:Sparse_page_size.Page_16_kib descriptor));
    ignore
      (expect_error Unsupported
         (Heap.create ~device
            (Heap.make_descriptor ~kind:Heap.Placement
               ~sparse_page_size:Sparse_page_size.Page_16_kib ~size:16_384L
               ())));
    let after = get (Release_queue.stats ()) in
    if after.total_created <> before.total_created then
      fail "unsupported placement sparse paths allocated native handles";
    Printf.printf "Metal placement sparse resources skipped: unsupported\n%!";
    false
  end
  else begin
    let supported_pages, failures =
      List.fold_left
        (fun (supported_pages, failures) page_size ->
          let page_bytes = Sparse_page_size.bytes page_size in
          match
             Buffer.create_placement_sparse ~device ~page_size
               ~length:page_bytes ~storage:Buffer.Private
               ~label:"Metal placement sparse buffer" ()
           with
           | Error ({ kind = Unsupported; _ } as error) ->
               ( supported_pages
               , (Printf.sprintf "%Ld-byte buffer: %s" page_bytes
                    (Format.asprintf "%a" pp_error error))
                 :: failures )
           | Error error -> fail "%s" (Format.asprintf "%a" pp_error error)
           | Ok buffer ->
               (match
                  Texture.create_placement_sparse ~device ~page_size descriptor
                with
                | Ok texture ->
                    if
                      Buffer.placement_sparse_page_size buffer
                      <> Some page_size
                      || Texture.placement_sparse_page_size texture
                         <> Some page_size
                    then fail "placement sparse page identity changed";
                    get (Texture.destroy texture);
                    get (Buffer.destroy buffer);
                    (page_size :: supported_pages, failures)
                | Error ({ kind = Unsupported; _ } as error) ->
                    get (Buffer.destroy buffer);
                    ( supported_pages
                    , (Printf.sprintf "%Ld-byte texture: %s" page_bytes
                         (Format.asprintf "%a" pp_error error))
                      :: failures )
                | Error error ->
                    get (Buffer.destroy buffer);
                    fail "%s" (Format.asprintf "%a" pp_error error)))
        ([], []) page_sizes
    in
    let page_size =
      match List.rev supported_pages with
      | page_size :: _ -> page_size
      | [] ->
          fail
            "device reports placement sparse support but accepts no reviewed page size (%s)"
            (String.concat "; " (List.rev failures))
    in
    let page_bytes = Sparse_page_size.bytes page_size in
    let buffer =
      get
        (Buffer.create_placement_sparse ~device ~page_size ~length:page_bytes
           ~storage:Buffer.Private ~label:"Metal placement sparse buffer" ())
    and texture =
      get (Texture.create_placement_sparse ~device ~page_size descriptor)
    in
    if
      Buffer.placement_sparse_page_size buffer <> Some page_size
      || Buffer.heap_offset buffer <> None
      || Buffer.length buffer <> page_bytes
      || Buffer.storage_mode buffer <> Buffer.Private
      || get (Buffer.sparse_tier buffer) <> Buffer.Sparse_tier_1
      || get (Buffer.label buffer) <> Some "Metal placement sparse buffer"
    then fail "placement sparse buffer properties are inconsistent";
    if
      Texture.placement_sparse_page_size texture <> Some page_size
      || Texture.heap_offset texture <> None
      || get (Texture.sparse_tier texture) = Texture.Not_sparse
      || get (Texture.label texture) <> Some "Metal placement sparse texture"
    then fail "placement sparse texture properties are inconsistent";
    let sparse_info =
      match get (Texture.sparse_info texture) with
      | Some info -> info
      | None -> fail "placement sparse texture lost its sparse metadata"
    in
    if sparse_info.page_size <> page_size
       || sparse_info.tile_size_in_bytes <> page_bytes
       || sparse_info.tile_width <= 0 || sparse_info.tile_height <= 0
       || sparse_info.tile_depth <= 0
    then fail "placement sparse texture tile metadata is inconsistent";
    let view =
      get
        (Texture.create_view texture ~format:Texture.R8_uint ~base_mip:0
           ~mip_count:1 ~base_slice:0 ~slice_count:1
           ~label:"Metal placement sparse view" ())
    in
    if
      Texture.placement_sparse_page_size view <> Some page_size
      || get (Texture.sparse_tier view) = Texture.Not_sparse
      || Option.is_none (get (Texture.sparse_info view))
    then fail "placement sparse texture view lost its sparse identity";
    ignore
      (expect_error Parent_has_dependents (Texture.destroy texture));
    get (Texture.destroy view);
    let ordinary_buffer =
      get (Buffer.create ~device ~length:16L ~storage:Buffer.Private ())
    and ordinary_texture =
      get
        (Texture.create ~device
           (Texture.descriptor_2d ~storage:Buffer.Private
              ~format:Texture.R8_uint ~width:1 ~height:1 ()))
    in
    if get (Buffer.sparse_tier ordinary_buffer) <> Buffer.Not_sparse
       || get (Texture.sparse_tier ordinary_texture) <> Texture.Not_sparse
    then fail "ordinary resources reported a placement sparse tier";
    get (Texture.destroy ordinary_texture);
    get (Buffer.destroy ordinary_buffer);
    ignore
      (expect_error Invalid_state
         (Buffer.read_bytes buffer ~offset:0L ~length:1));
    ignore
      (expect_error Invalid_state
         (Buffer.with_mapping buffer ~offset:0L ~length:1 (fun _ -> ())));
    ignore (expect_error Invalid_state (Buffer.purgeable_state buffer));
    ignore (expect_error Invalid_state (Buffer.is_aliasable buffer));
    let region : Texture.region =
      { x = 0; y = 0; z = 0; width = 1; height = 1; depth = 1 }
    in
    ignore
      (expect_error Invalid_state
         (Texture.read_bytes texture ~region ~mip_level:0 ~slice:0
            ~bytes_per_row:1 ~bytes_per_image:1));
    ignore (expect_error Invalid_state (Texture.purgeable_state texture));
    ignore (expect_error Invalid_state (Texture.is_aliasable texture));
    let before_invalid = get (Release_queue.stats ()) in
    ignore
      (expect_error Invalid_argument
         (Buffer.create_placement_sparse ~device ~page_size ~length:0L
            ~storage:Buffer.Private ()));
    ignore
      (expect_error Invalid_argument
         (Buffer.create_placement_sparse ~device ~page_size
            ~length:page_bytes ~storage:Buffer.Private
            ~label:"invalid\000label" ()));
    ignore
      (expect_error Invalid_argument
         (Texture.create_placement_sparse ~device ~page_size
            { descriptor with width = 0 }));
    ignore
      (expect_error Invalid_argument
         (Texture.create_placement_sparse ~device ~page_size
            { descriptor with label = Some "invalid\000label" }));
    ignore
      (expect_error Invalid_argument
         (Heap.create ~device
            (Heap.make_descriptor ~kind:Heap.Placement
               ~sparse_page_size:page_size ~size:(Int64.pred page_bytes) ())));
    ignore
      (expect_error Invalid_argument
         (Heap.create ~device
            (Heap.make_descriptor ~sparse_page_size:page_size
               ~size:page_bytes ())));
    ignore
      (expect_error Invalid_argument
         (Placement_mapping.create_queue ~label:"invalid\000label" device));
    ignore
      (expect_error Native_error
         (Placement_mapping.create_queue ~label:"\255" device));
    let after_invalid = get (Release_queue.stats ()) in
    if after_invalid.total_created <> before_invalid.total_created then
      fail "invalid placement sparse inputs allocated native handles";
    let tail_pages =
      if sparse_info.tail_size_in_bytes = 0L then 0L
      else
        Int64.succ
          (Int64.div (Int64.pred sparse_info.tail_size_in_bytes) page_bytes)
    in
    let heap_pages = Int64.add 2L tail_pages in
    let heap =
      get
        (Heap.create ~device
           (Heap.make_descriptor ~kind:Heap.Placement
              ~sparse_page_size:page_size ~label:"Metal sparse-compatible heap"
              ~size:(Int64.mul heap_pages page_bytes) ()))
    in
    if
      (Heap.descriptor heap).sparse_page_size <> Some page_size
      || (get (Heap.info heap)).kind <> Heap.Placement
      || get (Heap.label heap) <> Some "Metal sparse-compatible heap"
    then fail "placement sparse heap compatibility metadata is inconsistent";
    let tile : Resource_state_encoder.tile_region =
      { x = 0; y = 0; z = 0; width = 1; height = 1; depth = 1 }
    in
    let mapping_queue =
      get
        (Placement_mapping.create_queue ~label:"Metal placement mapper"
           device)
    in
    if
      not
        (Device.same device
           (Placement_mapping.queue_device mapping_queue))
      || Placement_mapping.queue_generation mapping_queue = 0L
      || get (Placement_mapping.queue_label mapping_queue)
         <> Some "Metal placement mapper"
    then fail "placement-mapping queue properties are inconsistent";
    ignore
      (expect_error Wrong_domain
         (Domain.spawn (fun () -> Placement_mapping.queue_label mapping_queue)
          |> Domain.join));
    let before_mapping_invalid = get (Release_queue.stats ()) in
    let invalid_buffer range heap_offset =
      ignore
        (expect_error Invalid_argument
           (Placement_mapping.map_buffer mapping_queue ~heap ~heap_offset
              buffer ~range))
    in
    invalid_buffer { offset = -1; length = 1 } 0L;
    invalid_buffer { offset = 0; length = 0 } 0L;
    invalid_buffer { offset = 1; length = 1 } 0L;
    invalid_buffer { offset = 0; length = 1 } 1L;
    invalid_buffer { offset = 0; length = 1 }
      (Heap.descriptor heap).size;
    ignore
      (expect_error Invalid_argument
         (Placement_mapping.map_texture mapping_queue ~heap ~heap_offset:0L
            texture ~mip_level:(-1) ~slice:0 ~region:tile));
    ignore
      (expect_error Invalid_argument
         (Placement_mapping.map_texture mapping_queue ~heap ~heap_offset:0L
            texture ~mip_level:0 ~slice:1 ~region:tile));
    ignore
      (expect_error Invalid_argument
         (Placement_mapping.map_texture mapping_queue ~heap ~heap_offset:0L
            texture ~mip_level:0 ~slice:0
            ~region:{ tile with x = max_int }));
    let after_mapping_invalid = get (Release_queue.stats ()) in
    if
      after_mapping_invalid.placement_mapping_operations
      <> before_mapping_invalid.placement_mapping_operations
    then fail "invalid placement mappings reached Objective-C";
    let buffer_mapping =
      get
        (Placement_mapping.map_buffer mapping_queue ~heap ~heap_offset:0L
           buffer ~range:{ offset = 0; length = 1 })
    in
    if
      Placement_mapping.kind buffer_mapping <> Placement_mapping.Buffer
      || Placement_mapping.page_size buffer_mapping <> page_size
      || Placement_mapping.heap_offset buffer_mapping <> 0L
      || Placement_mapping.mapped_bytes buffer_mapping <> page_bytes
      || Placement_mapping.destroyed buffer_mapping
    then fail "placement sparse buffer mapping metadata is inconsistent";
    let before_overlap_invalid = get (Release_queue.stats ()) in
    ignore
      (expect_error Invalid_state
         (Placement_mapping.map_buffer mapping_queue ~heap
            ~heap_offset:page_bytes buffer
            ~range:{ offset = 0; length = 1 }));
    ignore
      (expect_error Invalid_state
         (Placement_mapping.map_texture mapping_queue ~heap ~heap_offset:0L
            texture ~mip_level:0 ~slice:0 ~region:tile));
    let after_overlap_invalid = get (Release_queue.stats ()) in
    if
      after_overlap_invalid.placement_mapping_operations
      <> before_overlap_invalid.placement_mapping_operations
    then fail "overlapping placement mappings reached Objective-C";
    let texture_mapping =
      get
        (Placement_mapping.map_texture mapping_queue ~heap
           ~heap_offset:page_bytes texture ~mip_level:0 ~slice:0 ~region:tile)
    in
    if
      Placement_mapping.kind texture_mapping <> Placement_mapping.Texture
      || Placement_mapping.heap texture_mapping != heap
      || Placement_mapping.page_size texture_mapping <> page_size
      || Placement_mapping.heap_offset texture_mapping <> page_bytes
      || Placement_mapping.mapped_bytes texture_mapping <> page_bytes
      || Placement_mapping.destroyed texture_mapping
    then fail "placement sparse texture mapping metadata is inconsistent";
    let tail_mapping =
      match sparse_info.first_mip_in_tail with
      | None -> None
      | Some first_mip ->
          if tail_pages <= 0L then
            fail "placement sparse mip tail has no physical pages";
          if first_mip + 1 < descriptor.mip_levels then
            ignore
              (expect_error Invalid_argument
                 (Placement_mapping.map_texture mapping_queue ~heap
                    ~heap_offset:(Int64.mul 2L page_bytes) texture
                    ~mip_level:(first_mip + 1) ~slice:0 ~region:tile));
          let mapping =
            get
              (Placement_mapping.map_texture mapping_queue ~heap
                 ~heap_offset:(Int64.mul 2L page_bytes) texture
                 ~mip_level:first_mip ~slice:0 ~region:tile)
          in
          if
            Placement_mapping.mapped_bytes mapping
            <> Int64.mul tail_pages page_bytes
          then fail "placement sparse mip-tail byte ownership is inconsistent";
          Some mapping
    in
    ignore
      (expect_error Invalid_state
         (Texture.create_view texture ~format:Texture.R8_uint ~base_mip:0
            ~mip_count:1 ~base_slice:0 ~slice_count:1 ()));
    ignore
      (expect_error Parent_has_dependents
         (Placement_mapping.destroy_queue mapping_queue));
    ignore (expect_error Parent_has_dependents (Buffer.destroy buffer));
    ignore (expect_error Parent_has_dependents (Texture.destroy texture));
    ignore (expect_error Parent_has_dependents (Heap.destroy heap));
    ignore
      (expect_error Parent_has_dependents
         (Heap.set_purgeable_state heap Volatile));

    let command_queue = get (Command_queue.create device) in
    let placement_library =
      get (Library.compile_source ~device placement_sparse_shader_source)
    in
    let write_function =
      get (Function.find ~library:placement_library "placement_buffer_write")
    and read_function =
      get (Function.find ~library:placement_library "placement_buffer_read")
    and texture_write_function =
      get (Function.find ~library:placement_library "placement_texture_write")
    in
    let write_pipeline = get (Compute_pipeline.create write_function)
    and read_pipeline = get (Compute_pipeline.create read_function)
    and texture_write_pipeline =
      get (Compute_pipeline.create texture_write_function)
    in
    let output =
      get (Buffer.create ~device ~length:4L ~storage:Buffer.Shared ())
    in
    let write_commands = get (Command_buffer.create command_queue ()) in
    let write_encoder = get (Compute_encoder.create write_commands) in
    get (Compute_encoder.set_pipeline write_encoder write_pipeline);
    get (Compute_encoder.set_buffer write_encoder ~index:0 ~offset:0L buffer);
    get
      (Compute_encoder.dispatch_threads write_encoder ~threads:(1, 1, 1)
         ~threadgroup:(1, 1, 1));
    get (Compute_encoder.end_encoding write_encoder);
    complete_commands write_commands;
    get (Buffer.write_bytes output ~dst_offset:0L (Bytes.make 4 '\000'));
    let read_commands = get (Command_buffer.create command_queue ()) in
    let read_encoder = get (Compute_encoder.create read_commands) in
    get (Compute_encoder.set_pipeline read_encoder read_pipeline);
    get (Compute_encoder.set_buffer read_encoder ~index:0 ~offset:0L buffer);
    get (Compute_encoder.set_buffer read_encoder ~index:1 ~offset:0L output);
    get
      (Compute_encoder.dispatch_threads read_encoder ~threads:(1, 1, 1)
         ~threadgroup:(1, 1, 1));
    get (Compute_encoder.end_encoding read_encoder);
    ignore
      (expect_error Parent_has_dependents
         (Placement_mapping.unmap buffer_mapping));
    complete_commands read_commands;
    let buffer_value =
      Bytes.get_int32_le (get (Buffer.read_bytes output ~offset:0L ~length:4)) 0
    in
    if buffer_value <> Int32.of_string "0x5a17c0de" then
      fail "placement sparse buffer lost mapped GPU storage (%ld)" buffer_value;
    get (Placement_mapping.unmap buffer_mapping);
    if not (Placement_mapping.destroyed buffer_mapping) then
      fail "unmapped buffer mapping remained live";
    get (Placement_mapping.unmap buffer_mapping);
    let reused_mapping =
      get
        (Placement_mapping.map_buffer mapping_queue ~heap ~heap_offset:0L
           buffer ~range:{ offset = 0; length = 1 })
    in
    get (Placement_mapping.unmap reused_mapping);

    let texture_write_commands =
      get (Command_buffer.create command_queue ())
    in
    let texture_write_encoder =
      get (Compute_encoder.create texture_write_commands)
    in
    get
      (Compute_encoder.set_pipeline texture_write_encoder
         texture_write_pipeline);
    get (Compute_encoder.set_texture texture_write_encoder ~index:0 texture);
    get
      (Compute_encoder.dispatch_threads texture_write_encoder
         ~threads:(1, 1, 1) ~threadgroup:(1, 1, 1));
    get (Compute_encoder.end_encoding texture_write_encoder);
    complete_commands texture_write_commands;
    let sparse_library =
      get (Library.compile_source ~device sparse_shader_source)
    in
    let sparse_function =
      get (Function.find ~library:sparse_library "sparse_read")
    in
    let sparse_pipeline = get (Compute_pipeline.create sparse_function) in
    let read_texture source =
      get (Buffer.write_bytes output ~dst_offset:0L (Bytes.make 4 '\000'));
      let commands = get (Command_buffer.create command_queue ()) in
      let encoder = get (Compute_encoder.create commands) in
      get (Compute_encoder.set_pipeline encoder sparse_pipeline);
      get (Compute_encoder.set_texture encoder ~index:0 source);
      get (Compute_encoder.set_buffer encoder ~index:0 ~offset:0L output);
      get
        (Compute_encoder.dispatch_threads encoder ~threads:(1, 1, 1)
           ~threadgroup:(1, 1, 1));
      get (Compute_encoder.end_encoding encoder);
      complete_commands commands;
      Bytes.get_int32_le (get (Buffer.read_bytes output ~offset:0L ~length:4)) 0
    in
    let mapped_texture_value = read_texture texture in
    if mapped_texture_value <> 83l then
      fail
        "placement sparse texture lost mapped GPU storage (%ld; tile=%dx%dx%d, tail=%s/%Ld)"
        mapped_texture_value sparse_info.tile_width sparse_info.tile_height
        sparse_info.tile_depth
        (match sparse_info.first_mip_in_tail with
         | None -> "none"
         | Some value -> string_of_int value)
        sparse_info.tail_size_in_bytes;
    Option.iter (fun mapping -> get (Placement_mapping.unmap mapping))
      tail_mapping;
    get (Placement_mapping.unmap texture_mapping);
    if read_texture texture <> 0l then
      fail "unmapped placement sparse texture did not return defined zero data";
    let after_mapping = get (Release_queue.stats ()) in
    if
      Int64.sub after_mapping.placement_mapping_operations
        before_mapping_invalid.placement_mapping_operations
      <> (if Option.is_some tail_mapping then 8L else 6L)
    then fail "placement mapping operations did not cross Objective-C exactly once";
    get (Placement_mapping.destroy_queue mapping_queue);
    if not (Placement_mapping.queue_destroyed mapping_queue) then
      fail "destroyed placement-mapping queue remained live";
    ignore
      (expect_error Destroyed
         (Placement_mapping.queue_label mapping_queue));
    let before_mapping_finalizer = get (Release_queue.stats ()) in
    let allocate_unreleased_mapping () =
      let finalizer_heap =
        get
          (Heap.create ~device
             (Heap.make_descriptor ~kind:Heap.Placement
                ~sparse_page_size:page_size ~size:page_bytes ()))
      in
      let finalizer_buffer =
        get
          (Buffer.create_placement_sparse ~device ~page_size
             ~length:page_bytes ~storage:Buffer.Private ())
      in
      let finalizer_queue = get (Placement_mapping.create_queue device) in
      ignore
        (get
           (Placement_mapping.map_buffer finalizer_queue ~heap:finalizer_heap
              ~heap_offset:0L finalizer_buffer
              ~range:{ offset = 0; length = 1 }))
    in
    allocate_unreleased_mapping ();
    let after_mapping_finalizer =
      settle_finalizers ~expected_live:before_mapping_finalizer.live_handles
    in
    if
      Int64.sub after_mapping_finalizer.total_created
        before_mapping_finalizer.total_created
      <> 3L
      || Int64.sub after_mapping_finalizer.total_released
           before_mapping_finalizer.total_released
         <> 3L
    then fail "placement mapping finalization did not release all owners";

    let commands = get (Command_buffer.create command_queue ()) in
    let encoder = get (Resource_state_encoder.create commands) in
    ignore
      (expect_error Unsupported
         (Resource_state_encoder.update_texture_mapping encoder
            ~mode:Resource_state_encoder.Map texture ~mip_level:0 ~slice:0
            ~region:tile));
    get (Resource_state_encoder.end_encoding encoder);
    complete_commands commands;
    get (Buffer.destroy output);
    get (Compute_pipeline.destroy sparse_pipeline);
    get (Function.destroy sparse_function);
    get (Library.destroy sparse_library);
    get (Compute_pipeline.destroy read_pipeline);
    get (Compute_pipeline.destroy write_pipeline);
    get (Compute_pipeline.destroy texture_write_pipeline);
    get (Function.destroy read_function);
    get (Function.destroy write_function);
    get (Function.destroy texture_write_function);
    get (Library.destroy placement_library);
    get (Command_queue.destroy command_queue);
    get (Texture.destroy texture);
    get (Buffer.destroy buffer);
    get (Heap.destroy heap);
    ignore (expect_error Destroyed (Buffer.sparse_tier buffer));
    ignore (expect_error Destroyed (Texture.sparse_tier texture));
    Printf.printf
      "Metal 4 placement sparse mapping conformance passed (%Ld-byte pages)\n%!"
      page_bytes;
    true
  end

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
    let sparse_depth_stencil_formats = ref [] in
    let sparse_depth_stencil_count =
      [ "Depth16Unorm", Texture.Depth16_unorm
      ; "Depth32Float", Texture.Depth32_float
      ; "Stencil8", Texture.Stencil8
      ; "Depth24Unorm_Stencil8", Texture.Depth24_unorm_stencil8
      ; "Depth32Float_Stencil8", Texture.Depth32_float_stencil8
      ]
      |> List.fold_left
           (fun count (name, format) ->
             let candidate =
               Texture.descriptor_2d ~storage:Buffer.Private
                 ~usage:[ Texture.Render_target ] ~format ~width:256
                 ~height:256 ()
             in
             match Heap.create_texture heap candidate with
             | Error { kind = Unsupported; _ } -> count
             | Error error ->
                 fail "sparse %s creation failed unexpectedly: %s" name
                   (Format.asprintf "%a" pp_error error)
             | Ok sparse_depth_stencil ->
                 (match get (Texture.sparse_info sparse_depth_stencil) with
                  | Some info
                    when info.page_size = page_size
                         && info.tile_size_in_bytes = page_bytes
                         && info.tile_width > 0 && info.tile_height > 0
                         && info.tile_depth > 0 -> ()
                 | Some _ | None ->
                      fail "sparse %s metadata is inconsistent" name);
                 get (Texture.destroy sparse_depth_stencil);
                 sparse_depth_stencil_formats :=
                   name :: !sparse_depth_stencil_formats;
                 count + 1)
           0
    in
    if sparse_depth_stencil_count = 0 then
      Printf.printf
        "Metal sparse depth/stencil formats skipped: device reports no supported layout\n%!"
    else
      Printf.printf "Metal sparse depth/stencil formats passed: %s\n%!"
        (String.concat ", " (List.rev !sparse_depth_stencil_formats));
    let texture = get (Heap.create_texture heap descriptor) in
    if Texture.heap_offset texture <> None then
      fail "sparse texture unexpectedly reports a placement offset";
    if get (Texture.sparse_tier texture) = Texture.Not_sparse then
      fail "legacy sparse texture lost its minimum sparse tier";
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

let run_pipeline_once device pipeline ~initial ~expected =
  let bytes = Bytes.create 4 in
  Bytes.set_int32_le bytes 0 initial;
  let buffer =
    get (Buffer.create ~device ~length:4L ~storage:Buffer.Shared ())
  in
  get (Buffer.write_bytes buffer ~dst_offset:0L bytes);
  let queue = get (Command_queue.create device) in
  let commands = get (Command_buffer.create queue ()) in
  let encoder = get (Compute_encoder.create commands) in
  get (Compute_encoder.set_pipeline encoder pipeline);
  get (Compute_encoder.set_buffer encoder ~index:0 ~offset:0L buffer);
  get
    (Compute_encoder.dispatch_threads encoder ~threads:(1, 1, 1)
       ~threadgroup:(1, 1, 1));
  get (Compute_encoder.end_encoding encoder);
  complete_commands commands;
  let output = get (Buffer.read_bytes buffer ~offset:0L ~length:4) in
  if Bytes.get_int32_le output 0 <> expected then
    fail "pipeline asset produced %ld instead of %ld"
      (Bytes.get_int32_le output 0) expected;
  get (Command_queue.destroy queue);
  get (Buffer.destroy buffer)

let test_pipeline_assets device =
  let archive_path = Filename.temp_file "prismel-metal-" ".archive" in
  let dynamic_path = Filename.temp_file "prismel-metal-" ".dynamic" in
  Sys.remove archive_path;
  Sys.remove dynamic_path;
  Fun.protect
    ~finally:(fun () ->
      if Sys.file_exists archive_path then Sys.remove archive_path;
      if Sys.file_exists dynamic_path then Sys.remove dynamic_path)
    (fun () ->
      let missing_metallib = archive_path ^ ".missing.metallib" in
      ignore
        (expect_error Invalid_argument
           (Library.load_file ~device "relative.metallib"));
      ignore
        (expect_error Invalid_argument
           (Binary_archive.create ~path:"relative.archive" device));
      let missing_library =
        expect_error Native_error
          (Library.load_file ~device ~label:"missing metallib diagnostic"
             missing_metallib)
      in
      if not
           (contains_substring missing_library.message
              "missing metallib diagnostic")
      then fail "metallib loading lost its labeled diagnostic";
      let library =
        get
          (Library.compile_source ~device ~label:"pipeline asset library"
             shader_source)
      in
      let device_info = get (Device.info device) in
      let library_kind = get (Library.kind library) in
      let library_install_name = get (Library.install_name library) in
      let library_function_names = get (Library.function_names library) in
      if library_kind <> Library.Executable_library
         || Option.fold ~none:false ~some:(fun name -> name = "")
              library_install_name
         || not (List.mem "increment" library_function_names)
      then
        fail "executable Metal library metadata is wrong: kind=%s install=%s functions=%s"
          (match library_kind with
           | Library.Executable_library -> "executable"
           | Library.Dynamic_library_source -> "dynamic"
           | Library.Unknown_library_kind code -> Printf.sprintf "unknown(%d)" code)
          (match library_install_name with None -> "none" | Some value -> value)
          (String.concat "," library_function_names);
      let function_ = get (Function.find ~library "increment") in
      let archive_linked_function =
        if device_info.function_pointers then
          Some (get (Function.find ~library "linked_identity"))
        else None
      in
      let before_archive_finalizer = get (Release_queue.stats ()) in
      let allocate_unreleased_archive () =
        ignore (get (Binary_archive.create device))
      in
      allocate_unreleased_archive ();
      let after_archive_finalizer =
        settle_finalizers
          ~expected_live:before_archive_finalizer.live_handles
      in
      if
        Int64.sub after_archive_finalizer.total_created
          before_archive_finalizer.total_created
        <> 1L
        || Int64.sub after_archive_finalizer.total_released
             before_archive_finalizer.total_released
           <> 1L
      then fail "binary-archive finalization did not release exactly one handle";
      let archive =
        get (Binary_archive.create ~label:"pipeline archive" device)
      in
      if not (Device.same device (Binary_archive.device archive))
         || Binary_archive.generation archive <= 0L
         || get (Binary_archive.label archive) <> Some "pipeline archive"
      then
        fail "binary archive label did not round-trip";
      ignore
        (expect_error Wrong_domain
           (Domain.spawn (fun () -> Binary_archive.label archive)
            |> Domain.join));
      ignore
        (expect_error Invalid_argument
           (Binary_archive.serialize archive "relative.archive"));
      ignore
        (expect_error Invalid_argument
           (Compute_pipeline.create ~fail_on_binary_archive_miss:true
              function_));
      get
        (Binary_archive.add_compute_functions archive
           ~linked_functions:(Option.to_list archive_linked_function)
           function_);
      get (Binary_archive.serialize archive archive_path);
      if not (Sys.file_exists archive_path) then
        fail "Metal did not serialize the binary archive";
      let loaded_archive =
        get
          (Binary_archive.create ~path:archive_path
             ~label:"loaded pipeline archive" device)
      in
      let before_duplicate_archive = get (Release_queue.stats ()) in
      ignore
        (expect_error Invalid_argument
           (Compute_pipeline.create
              ~binary_archives:[ loaded_archive; loaded_archive ] function_));
      let after_duplicate_archive = get (Release_queue.stats ()) in
      if after_duplicate_archive.total_created
         <> before_duplicate_archive.total_created
      then fail "duplicate binary archives allocated a native handle";
      let archive_pipeline =
        get
          (Compute_pipeline.create
             ~linked_functions:(Option.to_list archive_linked_function)
             ~binary_archives:[ loaded_archive ]
             ~fail_on_binary_archive_miss:true function_)
      in
      get (Binary_archive.destroy loaded_archive);
      get (Binary_archive.destroy archive);
      Option.iter
        (fun value -> get (Function.destroy value))
        archive_linked_function;
      ignore (expect_error Destroyed (Binary_archive.label loaded_archive));
      ignore
        (expect_error Destroyed
           (Binary_archive.serialize archive archive_path));
      run_pipeline_once device archive_pipeline ~initial:41l ~expected:42l;
      get (Compute_pipeline.destroy archive_pipeline);
      if device_info.dynamic_libraries then begin
        ignore
          (expect_error Invalid_argument
             (Library.compile_dynamic_source ~device ~install_name:""
                dynamic_library_source));
        ignore
          (expect_error Invalid_argument
             (Dynamic_library.load_file ~device "relative.dynamic"));
        ignore
          (expect_error Invalid_argument (Dynamic_library.create library));
        let before_dynamic_finalizer = get (Release_queue.stats ()) in
        let allocate_unreleased_dynamic_library () =
          let source =
            get
              (Library.compile_dynamic_source ~device
                 ~install_name:(dynamic_path ^ ".finalizer")
                 dynamic_library_source)
          in
          ignore (get (Dynamic_library.create source))
        in
        allocate_unreleased_dynamic_library ();
        let after_dynamic_finalizer =
          settle_finalizers
            ~expected_live:before_dynamic_finalizer.live_handles
        in
        if
          Int64.sub after_dynamic_finalizer.total_created
            before_dynamic_finalizer.total_created
          <> 2L
          || Int64.sub after_dynamic_finalizer.total_released
               before_dynamic_finalizer.total_released
             <> 2L
        then
          fail
            "dynamic-library finalization did not release source and library handles";
        let dynamic_source =
          get
            (Library.compile_dynamic_source ~device
               ~label:"dynamic source library" ~install_name:dynamic_path
               dynamic_library_source)
        in
        if get (Library.kind dynamic_source)
           <> Library.Dynamic_library_source
           || get (Library.install_name dynamic_source) <> Some dynamic_path
        then fail "dynamic source-library metadata is wrong";
        let dynamic_library =
          get
            (Dynamic_library.create ~label:"live dynamic library"
               dynamic_source)
        in
        if get (Dynamic_library.label dynamic_library)
           <> Some "live dynamic library"
           || get (Dynamic_library.install_name dynamic_library) <> dynamic_path
           || not (Device.same device (Dynamic_library.device dynamic_library))
           || Dynamic_library.generation dynamic_library <= 0L
        then fail "dynamic-library metadata is wrong";
        ignore
          (expect_error Wrong_domain
             (Domain.spawn (fun () -> Dynamic_library.label dynamic_library)
              |> Domain.join));
        ignore
          (expect_error Invalid_argument
             (Dynamic_library.serialize dynamic_library "relative.dynamic"));
        get (Dynamic_library.serialize dynamic_library dynamic_path);
        if not (Sys.file_exists dynamic_path) then
          fail "Metal did not serialize the dynamic library";
        get (Library.destroy dynamic_source);
        get (Dynamic_library.destroy dynamic_library);
        ignore
          (expect_error Destroyed
             (Dynamic_library.label dynamic_library));
        ignore
          (expect_error Destroyed
             (Dynamic_library.create dynamic_source));
        let loaded_dynamic =
          get
            (Dynamic_library.load_file ~device ~label:"loaded dynamic library"
               dynamic_path)
        in
        if get (Dynamic_library.install_name loaded_dynamic) <> dynamic_path
        then fail "loaded dynamic-library install name changed";
        let before_duplicate_dynamic = get (Release_queue.stats ()) in
        ignore
          (expect_error Invalid_argument
             (Dynamic_library.compile_source ~device
                ~libraries:[ loaded_dynamic; loaded_dynamic ]
                dynamic_client_source));
        let after_duplicate_dynamic = get (Release_queue.stats ()) in
        if after_duplicate_dynamic.total_created
           <> before_duplicate_dynamic.total_created
        then fail "duplicate dynamic libraries allocated a native handle";
        let client_library =
          get
            (Dynamic_library.compile_source ~device
               ~label:"dynamic client library" ~libraries:[ loaded_dynamic ]
               dynamic_client_source)
        in
        let client_function =
          get (Function.find ~library:client_library "call_dynamic_library")
        in
        let dynamic_archive =
          get
            (Binary_archive.create ~label:"dynamic pipeline archive" device)
        in
        get
          (Binary_archive.add_compute_functions dynamic_archive
             ~preloaded_libraries:[ loaded_dynamic ] client_function);
        if Sys.file_exists archive_path then Sys.remove archive_path;
        get (Binary_archive.serialize dynamic_archive archive_path);
        let loaded_dynamic_archive =
          get (Binary_archive.create ~path:archive_path device)
        in
        let dynamic_pipeline =
          get
            (Compute_pipeline.create
               ~preloaded_libraries:[ loaded_dynamic ]
               ~binary_archives:[ loaded_dynamic_archive ]
               ~fail_on_binary_archive_miss:true client_function)
        in
        get (Binary_archive.destroy loaded_dynamic_archive);
        get (Binary_archive.destroy dynamic_archive);
        get (Function.destroy client_function);
        get (Library.destroy client_library);
        get (Dynamic_library.destroy loaded_dynamic);
        ignore
          (expect_error Destroyed
             (Compute_pipeline.create
                ~preloaded_libraries:[ loaded_dynamic ] function_));
        run_pipeline_once device dynamic_pipeline ~initial:29l ~expected:42l;
        get (Compute_pipeline.destroy dynamic_pipeline)
      end;
      get (Function.destroy function_);
      get (Library.destroy library))

let test_metal4_compiler device =
  if not (get (Device.supports_family device Device.Metal4)) then begin
    ignore
      (expect_error Unsupported
         (Pipeline_dataset.create ~device [ Pipeline_dataset.Descriptors ]));
    false
  end
  else begin
    let archive_path = Filename.temp_file "prismel-metal4-" ".metallib" in
    let dynamic_path =
      Filename.temp_file "prismel-metal4-dynamic-" ".metallib"
    in
    Sys.remove archive_path;
    Sys.remove dynamic_path;
    Fun.protect
      ~finally:(fun () ->
        if Sys.file_exists archive_path then Sys.remove archive_path;
        if Sys.file_exists dynamic_path then Sys.remove dynamic_path)
      (fun () ->
        let before_invalid_dataset = get (Release_queue.stats ()) in
        ignore
          (expect_error Invalid_argument
             (Pipeline_dataset.create ~device []));
        ignore
          (expect_error Invalid_argument
             (Pipeline_dataset.create ~device
                [ Pipeline_dataset.Descriptors
                ; Pipeline_dataset.Descriptors
                ]));
        ignore
          (expect_error Invalid_argument
             (Pipeline_archive.load_file ~device "relative.mtl4archive"));
        let after_invalid_dataset = get (Release_queue.stats ()) in
        if after_invalid_dataset.total_created
           <> before_invalid_dataset.total_created
        then fail "invalid Metal 4 dataset inputs allocated native handles";
        let before_compiler_finalizers = get (Release_queue.stats ()) in
        let allocate_unreleased_compiler () =
          let finalizer_dataset =
            get
              (Pipeline_dataset.create ~device
                 [ Pipeline_dataset.Descriptors ])
          in
          ignore (get (Compiler.create ~dataset:finalizer_dataset device))
        in
        allocate_unreleased_compiler ();
        let after_compiler_finalizers =
          settle_finalizers
            ~expected_live:before_compiler_finalizers.live_handles
        in
        if
          Int64.sub after_compiler_finalizers.total_created
            before_compiler_finalizers.total_created
          <> 2L
          || Int64.sub after_compiler_finalizers.total_released
               before_compiler_finalizers.total_released
             <> 2L
        then
          fail
            "Metal 4 compiler/dataset finalization did not release two handles";
        let descriptors_only =
          get
            (Pipeline_dataset.create ~device
               [ Pipeline_dataset.Descriptors ])
        in
        ignore
          (expect_error Invalid_state
             (Pipeline_dataset.serialize_archive descriptors_only
                archive_path));
        get (Pipeline_dataset.destroy descriptors_only);
        let dataset =
          get
            (Pipeline_dataset.create ~device
               [ Pipeline_dataset.Descriptors ])
        in
        if
          Pipeline_dataset.captures dataset
          <> [ Pipeline_dataset.Descriptors ]
          || not (Device.same device (Pipeline_dataset.device dataset))
          || Pipeline_dataset.generation dataset <= 0L
        then fail "Metal 4 pipeline-dataset metadata is wrong";
        let compiler =
          get
            (Compiler.create ~label:"Metal 4 dataset compiler" ~dataset device)
        in
        let compiler_label = get (Compiler.label compiler) in
        if
          (compiler_label <> None
           && compiler_label <> Some "Metal 4 dataset compiler")
           || not (Device.same device (Compiler.device compiler))
           || Compiler.generation compiler <= 0L
           || Option.is_none (Compiler.dataset compiler)
        then fail "Metal 4 compiler metadata is wrong";
        if Compiler_task.completion_capacity <= 0
           || get (Compiler_task.pending_completions ()) <> 0
           || get (Compiler_task.dropped_completions ()) <> 0L
        then fail "Metal 4 compiler completion queue metadata is wrong";
        ignore
          (expect_error Invalid_argument
             (Compiler_task.drain_completions ~limit:0 ()));
        ignore
          (expect_error Invalid_argument
             (Compiler_task.drain_completions
                ~limit:(Compiler_task.completion_capacity + 1) ()));
        if get (Compiler_task.drain_completions ()) <> [] then
          fail "Metal 4 compiler completion queue was not initially empty";
        let before_invalid_async = get (Release_queue.stats ()) in
        ignore
          (expect_error Invalid_argument
             (Compiler.compile_source_async compiler ""));
        ignore
          (expect_error Invalid_argument
             (Compiler.compile_source_async ~name:"invalid\000async" compiler
                shader_source));
        let after_invalid_async = get (Release_queue.stats ()) in
        if after_invalid_async.total_created
           <> before_invalid_async.total_created
        then fail "invalid async compilation allocated a native handle";
        let async_library_task =
          get
            (Compiler.compile_source_async ~name:"async-library" compiler
               shader_source)
        in
        let async_error_task =
          get
            (Compiler.compile_source_async ~name:"async-diagnostic" compiler
               "kernel this is not valid MSL")
        in
        if Compiler_task.id async_library_task <= 0L
           || Compiler_task.id async_error_task <= 0L
           || Compiler_task.id async_library_task
              = Compiler_task.id async_error_task
           || not
                (Device.same device (Compiler_task.device async_library_task))
        then fail "Metal 4 compiler-task identity is wrong";
        ignore
          (expect_error Parent_has_dependents (Compiler.destroy compiler));
        ignore
          (expect_error Wrong_domain
             (Domain.spawn (fun () -> Compiler_task.status async_library_task)
              |> Domain.join));
        get (Compiler_task.wait async_library_task);
        get (Compiler_task.wait async_error_task);
        if get (Compiler_task.status async_library_task)
           <> Compiler_task.Finished
           || get (Compiler_task.status async_error_task)
              <> Compiler_task.Finished
        then fail "waited Metal 4 compiler task is not finished";
        if get (Compiler_task.pending_completions ()) <> 2 then
          fail "Metal 4 compiler completion queue pending count is wrong";
        let completed_ids = get (Compiler_task.drain_completions ()) in
        if
          not
            (List.mem (Compiler_task.id async_library_task) completed_ids)
          || not
               (List.mem (Compiler_task.id async_error_task) completed_ids)
        then fail "Metal 4 compiler completion IDs were not drained";
        if get (Compiler_task.pending_completions ()) <> 0 then
          fail "drained Metal 4 compiler completion IDs remained pending";
        let async_library =
          match get (Compiler_task.poll async_library_task) with
          | Compiler_task.Complete (Ok library) -> library
          | Compiler_task.Complete (Error error) ->
              fail "async library compilation failed: %s"
                (Format.asprintf "%a" pp_error error)
          | Compiler_task.Pending ->
              fail "waited async library compilation remained pending"
        in
        let async_diagnostic =
          match get (Compiler_task.poll async_error_task) with
          | Compiler_task.Complete (Error error) -> error
          | Compiler_task.Complete (Ok library) ->
              get (Library.destroy library);
              fail "invalid async shader unexpectedly compiled"
          | Compiler_task.Pending ->
              fail "waited invalid async compilation remained pending"
        in
        if get (Library.label async_library) <> Some "async-library"
           || not
                (List.mem "increment"
                   (get (Library.function_names async_library)))
        then fail "async Metal 4 library metadata is wrong";
        if
          not
            (contains_substring async_diagnostic.message "async-diagnostic")
          || not (contains_substring async_diagnostic.message "domain=")
          || not (contains_substring async_diagnostic.message "userInfo=")
        then fail "async Metal 4 compilation lost its full diagnostic";
        ignore
          (expect_error Invalid_state
             (Compiler_task.poll async_library_task));
        get (Library.destroy async_library);
        get (Compiler_task.destroy async_error_task);
        get (Compiler_task.destroy async_library_task);
        ignore
          (expect_error Destroyed
             (Compiler_task.status async_library_task));
        let before_async_finalizer = get (Release_queue.stats ()) in
        let allocate_unreleased_async_task () =
          let task =
            get
              (Compiler.compile_source_async
                 ~name:"finalized-async-library" compiler shader_source)
          in
          let identifier = Compiler_task.id task in
          get (Compiler_task.wait task);
          identifier
        in
        let finalized_async_id = allocate_unreleased_async_task () in
        let after_async_finalizer =
          settle_finalizers ~expected_live:before_async_finalizer.live_handles
        in
        if
          Int64.sub after_async_finalizer.total_created
            before_async_finalizer.total_created
          <> 1L
          || Int64.sub after_async_finalizer.total_released
               before_async_finalizer.total_released
             <> 1L
        then fail "Metal 4 compiler-task finalizer did not release one handle";
        if
          not
            (List.mem finalized_async_id
               (get (Compiler_task.drain_completions ())))
        then fail "finalized compiler task did not enqueue its completion ID";
        if get (Compiler_task.dropped_completions ()) <> 0L then
          fail "Metal 4 compiler completion queue dropped an identifier";
        ignore
          (expect_error Parent_has_dependents
             (Pipeline_dataset.destroy dataset));
        ignore
          (expect_error Wrong_domain
             (Domain.spawn (fun () -> Compiler.label compiler)
              |> Domain.join));
        let before_invalid_compilation = get (Release_queue.stats ()) in
        ignore
          (expect_error Invalid_argument
             (Compiler.compile_source compiler ""));
        ignore
          (expect_error Invalid_argument
             (Compiler.compile_source ~name:"invalid\000name" compiler
                shader_source));
        let compiler_diagnostic =
          expect_error Native_error
            (Compiler.compile_source ~name:"Metal 4 compiler diagnostic"
               compiler "kernel this is not valid MSL")
        in
        if
          not
            (contains_substring compiler_diagnostic.message
               "Metal 4 compiler diagnostic")
          || not (contains_substring compiler_diagnostic.message "domain=")
          || not (contains_substring compiler_diagnostic.message "userInfo=")
        then fail "Metal 4 compiler lost its full labeled diagnostic";
        let library =
          get
            (Compiler.compile_source ~name:"metal4_increment_library" compiler
               shader_source)
        in
        if get (Library.label library) <> Some "metal4_increment_library"
           || not (List.mem "increment" (get (Library.function_names library)))
        then fail "Metal 4 compiler library metadata is wrong";
        ignore
          (expect_error Invalid_argument
             (Compiler.create_compute_pipeline compiler ~library ""));
        ignore
          (expect_error Invalid_argument
             (Compiler.create_compute_pipeline ~label:"invalid\000label"
                compiler ~library "increment"));
        ignore
          (expect_error Invalid_argument
             (Compiler.create_compute_pipeline
                ~max_total_threads_per_threadgroup:0 compiler ~library
                "increment"));
        ignore
          (expect_error Invalid_argument
             (Compiler.create_compute_pipeline
                ~required_threads_per_threadgroup:(1, 0, 1) compiler ~library
                "increment"));
        ignore
          (expect_error Invalid_argument
             (Compiler.create_compute_pipeline
                ~max_total_threads_per_threadgroup:4
                ~required_threads_per_threadgroup:(8, 1, 1) compiler ~library
                "increment"));
        ignore
          (expect_error Invalid_argument
             (Compiler.create_compute_pipeline ~max_call_stack_depth:0 compiler
                ~library "increment"));
        ignore
          (expect_error Invalid_argument
             (Compiler.create_compute_pipeline_async compiler ~library ""));
        ignore
          (expect_error Invalid_argument
             (Compiler.create_compute_pipeline_async
                ~required_threads_per_threadgroup:(1, 0, 1) compiler ~library
                "increment"));
        ignore
          (expect_error Invalid_argument
             (Compiler.create_compute_pipeline_async compiler ~library
                "missing_kernel"));
        let after_invalid_compilation = get (Release_queue.stats ()) in
        if after_invalid_compilation.total_created
           <> Int64.add before_invalid_compilation.total_created 1L
        then
          fail
            "invalid Metal 4 compiler inputs allocated native handles beyond the valid library";
        let render_library =
          get
            (Compiler.compile_source ~name:"metal4-render-library" compiler
               render_shader_source)
        in
        let before_invalid_render = get (Release_queue.stats ()) in
        ignore
          (expect_error Invalid_argument
             (Compiler.create_render_pipeline compiler ~library:render_library
                ~vertex:""));
        ignore
          (expect_error Invalid_argument
             (Compiler.create_render_pipeline compiler ~library:render_library
                ~vertex:"missing_vertex"));
        ignore
          (expect_error Invalid_argument
             (Compiler.create_render_pipeline_async compiler
                ~library:render_library ~vertex:"missing_vertex"));
        ignore
          (expect_error Invalid_argument
             (Compiler.create_render_pipeline ~label:"invalid\000render"
                ~fragment:"prismel_fragment" compiler
                ~library:render_library ~vertex:"prismel_vertex"));
        ignore
          (expect_error Invalid_argument
             (Compiler.create_render_pipeline compiler ~library:render_library
                ~vertex:"prismel_vertex"));
        ignore
          (expect_error Invalid_argument
             (Compiler.create_render_pipeline
                ~rasterization_enabled:false ~color_formats:[]
                ~fragment:"prismel_fragment" compiler
                ~library:render_library ~vertex:"prismel_vertex"));
        ignore
          (expect_error Invalid_argument
             (Compiler.create_render_pipeline
                ~rasterization_enabled:false compiler
                ~library:render_library ~vertex:"prismel_vertex"));
        ignore
          (expect_error Invalid_argument
             (Compiler.create_render_pipeline ~raster_sample_count:0
                ~fragment:"prismel_fragment" compiler
                ~library:render_library ~vertex:"prismel_vertex"));
        ignore
          (expect_error Invalid_argument
             (Compiler.create_render_pipeline
                ~color_formats:
                  [ Texture.Bgra8_unorm; Texture.Bgra8_unorm
                  ; Texture.Bgra8_unorm; Texture.Bgra8_unorm
                  ; Texture.Bgra8_unorm; Texture.Bgra8_unorm
                  ; Texture.Bgra8_unorm; Texture.Bgra8_unorm
                  ; Texture.Bgra8_unorm
                  ]
                ~fragment:"prismel_fragment" compiler
                ~library:render_library ~vertex:"prismel_vertex"));
        ignore
          (expect_error Native_error
             (Compiler.create_render_pipeline
                ~fragment:"prismel_fragment" compiler
                ~library:render_library ~vertex:"prismel_fragment"));
        ignore
          (expect_error Native_error
             (Compiler.create_render_pipeline ~fragment:"prismel_vertex"
                compiler ~library:render_library ~vertex:"prismel_vertex"));
        ignore
          (expect_error Native_error
             (Compiler.create_render_pipeline_async
                ~fragment:"prismel_fragment" compiler
                ~library:render_library ~vertex:"prismel_fragment"));
        let after_invalid_render = get (Release_queue.stats ()) in
        if after_invalid_render.total_created
           <> before_invalid_render.total_created
        then fail "invalid Metal 4 render inputs allocated native handles";
        let render_pipeline =
          get
            (Compiler.create_render_pipeline
               ~label:"metal4 reflected render" ~fragment:"prismel_fragment"
               ~reflection:true ~primitive_topology:Render_pipeline.Triangle
               ~support_indirect_command_buffers:true compiler
               ~library:render_library ~vertex:"prismel_vertex")
        in
        if get (Render_pipeline.label render_pipeline)
           <> Some "metal4 reflected render"
           || Render_pipeline.kind render_pipeline <> Render_pipeline.Render
           || not
                (Device.same device (Render_pipeline.device render_pipeline))
           || Render_pipeline.generation render_pipeline <= 0L
        then fail "Metal 4 render-pipeline metadata is wrong";
        (match Render_pipeline.reflection render_pipeline with
         | Some reflection ->
             get
               (Binding.validate_layout reflection.vertex
                  ~expected:
                    [ { name = "offset"
                      ; index = 0L
                      ; access = Binding.Read_only
                      ; kind = Binding.Buffer_layout
                      ; data_type =
                          Some (Shader_type.Vector (Shader_type.Float, 2))
                      }
                    ]);
             get
               (Binding.validate_layout reflection.fragment
                  ~expected:
                    [ { name = "tint"
                      ; index = 1L
                      ; access = Binding.Read_only
                      ; kind = Binding.Buffer_layout
                      ; data_type =
                          Some (Shader_type.Vector (Shader_type.Float, 4))
                      }
                    ]);
             if reflection.tile <> [] || reflection.object_ <> []
                || reflection.mesh <> []
             then
               fail
                 "Metal 4 conventional render reflection populated an unrelated stage"
         | None -> fail "Metal 4 render reflection is missing");
        let vertex_only_pipeline =
          get
            (Compiler.create_render_pipeline
               ~label:"metal4 vertex-only render"
               ~rasterization_enabled:false ~color_formats:[] compiler
               ~library:render_library ~vertex:"prismel_vertex_only")
        in
        if Render_pipeline.reflection vertex_only_pipeline <> None
           || get (Render_pipeline.label vertex_only_pipeline)
              <> Some "metal4 vertex-only render"
        then fail "Metal 4 vertex-only render-pipeline metadata is wrong";
        get (Render_pipeline.destroy vertex_only_pipeline);
        let before_render_finalizer = get (Release_queue.stats ()) in
        let allocate_unreleased_render_pipeline () =
          ignore
            (get
               (Compiler.create_render_pipeline
                  ~fragment:"prismel_fragment" compiler
                  ~library:render_library ~vertex:"prismel_vertex"))
        in
        allocate_unreleased_render_pipeline ();
        let after_render_finalizer =
          settle_finalizers
            ~expected_live:before_render_finalizer.live_handles
        in
        if
          Int64.sub after_render_finalizer.total_created
            before_render_finalizer.total_created
          <> 1L
          || Int64.sub after_render_finalizer.total_released
               before_render_finalizer.total_released
             <> 1L
        then fail "Metal 4 render-pipeline finalizer did not release one handle";
        let async_render_library =
          get
            (Compiler.compile_source ~name:"async-render-source" compiler
               render_shader_source)
        in
        let async_render_task =
          get
            (Compiler.create_render_pipeline_async
               ~label:"async reflected render" ~fragment:"prismel_fragment"
               ~reflection:true compiler ~library:async_render_library
               ~vertex:"prismel_vertex")
        in
        let async_render_id = Compiler_task.id async_render_task in
        get (Library.destroy async_render_library);
        get (Compiler_task.wait async_render_task);
        if
          not
            (List.mem async_render_id
               (get (Compiler_task.drain_completions ())))
        then fail "async render-pipeline completion ID was not drained";
        let async_render_pipeline =
          match get (Compiler_task.poll async_render_task) with
          | Compiler_task.Complete (Ok pipeline) -> pipeline
          | Compiler_task.Complete (Error error) ->
              fail "async render-pipeline compilation failed: %s"
                (Format.asprintf "%a" pp_error error)
          | Compiler_task.Pending ->
              fail "waited async render-pipeline compilation remained pending"
        in
        if get (Render_pipeline.label async_render_pipeline)
           <> Some "async reflected render"
           || Render_pipeline.kind async_render_pipeline
              <> Render_pipeline.Render
           || Option.is_none
                (Render_pipeline.reflection async_render_pipeline)
        then fail "async Metal 4 render-pipeline metadata is wrong";
        get (Render_pipeline.destroy async_render_pipeline);
        get (Compiler_task.destroy async_render_task);
        get (Render_pipeline.destroy render_pipeline);
        if not (Render_pipeline.destroyed render_pipeline) then
          fail "destroyed Metal 4 render pipeline remained live";
        ignore
          (expect_error Destroyed (Render_pipeline.label render_pipeline));
        get (Render_pipeline.destroy render_pipeline);
        get (Library.destroy render_library);
        let mesh_library =
          get
            (Compiler.compile_source ~name:"metal4-mesh-library" compiler
               mesh_shader_source)
        in
        let before_invalid_mesh = get (Release_queue.stats ()) in
        ignore
          (expect_error Invalid_argument
             (Compiler.create_mesh_pipeline ~fragment:"prismel_mesh_fragment"
                compiler ~library:mesh_library ~mesh:"missing_mesh"));
        ignore
          (expect_error Invalid_argument
             (Compiler.create_mesh_pipeline
                ~max_total_threads_per_object_threadgroup:1
                ~fragment:"prismel_mesh_fragment" compiler
                ~library:mesh_library ~mesh:"prismel_mesh"));
        ignore
          (expect_error Invalid_argument
             (Compiler.create_mesh_pipeline ~object_function:"prismel_object"
                ~payload_memory_length:0 ~fragment:"prismel_mesh_fragment"
                compiler ~library:mesh_library ~mesh:"prismel_object_mesh"));
        ignore
          (expect_error Invalid_argument
             (Compiler.create_mesh_pipeline ~object_function:"prismel_object"
                ~payload_memory_length:16_385
                ~fragment:"prismel_mesh_fragment" compiler
                ~library:mesh_library ~mesh:"prismel_object_mesh"));
        ignore
          (expect_error Invalid_argument
             (Compiler.create_mesh_pipeline ~object_function:"prismel_object"
                ~max_total_threadgroups_per_mesh_grid:0
                ~fragment:"prismel_mesh_fragment" compiler
                ~library:mesh_library ~mesh:"prismel_object_mesh"));
        ignore
          (expect_error Invalid_argument
             (Compiler.create_mesh_pipeline
                ~max_total_threads_per_mesh_threadgroup:0
                ~fragment:"prismel_mesh_fragment" compiler
                ~library:mesh_library ~mesh:"prismel_mesh"));
        ignore
          (expect_error Invalid_argument
             (Compiler.create_mesh_pipeline
                ~required_threads_per_mesh_threadgroup:(3, 0, 1)
                ~fragment:"prismel_mesh_fragment" compiler
                ~library:mesh_library ~mesh:"prismel_mesh"));
        ignore
          (expect_error Invalid_argument
             (Compiler.create_mesh_pipeline
                ~max_total_threads_per_mesh_threadgroup:4
                ~required_threads_per_mesh_threadgroup:(3, 1, 1)
                ~fragment:"prismel_mesh_fragment" compiler
                ~library:mesh_library ~mesh:"prismel_mesh"));
        ignore
          (expect_error Native_error
             (Compiler.create_mesh_pipeline ~fragment:"prismel_mesh_fragment"
                compiler ~library:mesh_library
                ~mesh:"prismel_mesh_fragment"));
        ignore
          (expect_error Native_error
             (Compiler.create_mesh_pipeline ~fragment:"prismel_mesh" compiler
                ~library:mesh_library ~mesh:"prismel_mesh"));
        ignore
          (expect_error Native_error
             (Compiler.create_mesh_pipeline ~object_function:"prismel_mesh"
                ~fragment:"prismel_mesh_fragment" compiler
                ~library:mesh_library ~mesh:"prismel_object_mesh"));
        ignore
          (expect_error Invalid_argument
             (Compiler.create_mesh_pipeline_async
                ~fragment:"prismel_mesh_fragment" compiler
                ~library:mesh_library ~mesh:"missing_mesh"));
        if not (get (Device.supports_family device Device.Apple9)) then
          ignore
            (expect_error Unsupported
               (Compiler.create_mesh_pipeline
                  ~support_indirect_command_buffers:true
                  ~fragment:"prismel_mesh_fragment" compiler
                  ~library:mesh_library ~mesh:"prismel_mesh"));
        let after_invalid_mesh = get (Release_queue.stats ()) in
        if after_invalid_mesh.total_created
           <> before_invalid_mesh.total_created
        then fail "invalid Metal 4 mesh inputs allocated native handles";
        let mesh_pipeline =
          get
            (Compiler.create_mesh_pipeline ~label:"metal4 reflected mesh"
               ~fragment:"prismel_mesh_fragment" ~reflection:true
               ~max_total_threads_per_mesh_threadgroup:3
               ~required_threads_per_mesh_threadgroup:(3, 1, 1) compiler
               ~library:mesh_library ~mesh:"prismel_mesh")
        in
        if get (Render_pipeline.label mesh_pipeline)
           <> Some "metal4 reflected mesh"
           || Render_pipeline.kind mesh_pipeline <> Render_pipeline.Mesh
        then fail "Metal 4 mesh-pipeline metadata is wrong";
        (match Render_pipeline.reflection mesh_pipeline with
         | Some reflection ->
             get
               (Binding.validate_layout reflection.mesh
                  ~expected:
                    [ { name = "offset"
                      ; index = 2L
                      ; access = Binding.Read_only
                      ; kind = Binding.Buffer_layout
                      ; data_type =
                          Some (Shader_type.Vector (Shader_type.Float, 2))
                      }
                    ]);
             get
               (Binding.validate_layout reflection.fragment
                  ~expected:
                    [ { name = "tint"
                      ; index = 3L
                      ; access = Binding.Read_only
                      ; kind = Binding.Buffer_layout
                      ; data_type =
                          Some (Shader_type.Vector (Shader_type.Float, 4))
                      }
                    ]);
             if reflection.vertex <> [] || reflection.tile <> []
                || reflection.object_ <> []
             then
               fail
                 "Metal 4 mesh reflection populated an unrelated stage"
         | None -> fail "Metal 4 mesh reflection is missing");
        let object_mesh_pipeline =
          get
            (Compiler.create_mesh_pipeline
               ~label:"metal4 reflected object mesh"
               ~object_function:"prismel_object"
               ~fragment:"prismel_mesh_fragment" ~reflection:true
               ~max_total_threads_per_object_threadgroup:1
               ~max_total_threads_per_mesh_threadgroup:3
               ~required_threads_per_object_threadgroup:(1, 1, 1)
               ~required_threads_per_mesh_threadgroup:(3, 1, 1)
               ~payload_memory_length:8
               ~max_total_threadgroups_per_mesh_grid:1 compiler
               ~library:mesh_library ~mesh:"prismel_object_mesh")
        in
        (match Render_pipeline.reflection object_mesh_pipeline with
         | Some reflection ->
             get
               (Binding.validate_layout reflection.object_
                  ~expected:
                    [ { name = "payload"
                      ; index = 4_294_967_295L
                      ; access = Binding.Read_write
                      ; kind = Binding.Object_payload_layout
                      ; data_type = None
                      }
                    ; { name = "source_offset"
                      ; index = 0L
                      ; access = Binding.Read_only
                      ; kind = Binding.Buffer_layout
                      ; data_type =
                          Some (Shader_type.Vector (Shader_type.Float, 2))
                      }
                    ]);
             get
               (Binding.validate_layout reflection.mesh
                  ~expected:
                    [ { name = "payload"
                      ; index = 4_294_967_295L
                      ; access = Binding.Read_only
                      ; kind = Binding.Object_payload_layout
                      ; data_type = None
                      }
                    ; { name = "mesh_color"
                      ; index = 1L
                      ; access = Binding.Read_only
                      ; kind = Binding.Buffer_layout
                      ; data_type =
                          Some (Shader_type.Vector (Shader_type.Float, 4))
                      }
                    ]);
             let payload_size_is_exact bindings =
               List.exists
                 (fun (binding : Binding.t) ->
                   binding.name = "payload"
                   &&
                   match binding.kind with
                   | Binding.Object_payload_binding payload ->
                       payload.alignment = 8L && payload.data_size = 8L
                   | _ -> false)
                 bindings
             in
             if not (payload_size_is_exact reflection.object_)
                || not (payload_size_is_exact reflection.mesh)
             then fail "Metal 4 object payload reflection size is wrong";
             if reflection.vertex <> [] || reflection.tile <> [] then
               fail
                 "Metal 4 object-mesh reflection populated an unrelated stage"
         | None -> fail "Metal 4 object-mesh reflection is missing");
        get (Render_pipeline.destroy object_mesh_pipeline);
        let nonraster_mesh =
          get
            (Compiler.create_mesh_pipeline ~rasterization_enabled:false
               ~color_formats:[] compiler ~library:mesh_library
               ~mesh:"prismel_mesh")
        in
        get (Render_pipeline.destroy nonraster_mesh);
        let async_mesh_library =
          get
            (Compiler.compile_source ~name:"async-mesh-source" compiler
               mesh_shader_source)
        in
        let async_mesh_task =
          get
            (Compiler.create_mesh_pipeline_async
               ~label:"async reflected mesh"
               ~fragment:"prismel_mesh_fragment" ~reflection:true
               ~max_total_threads_per_mesh_threadgroup:3
               ~required_threads_per_mesh_threadgroup:(3, 1, 1) compiler
               ~library:async_mesh_library ~mesh:"prismel_mesh")
        in
        let async_mesh_id = Compiler_task.id async_mesh_task in
        get (Library.destroy async_mesh_library);
        get (Compiler_task.wait async_mesh_task);
        if
          not
            (List.mem async_mesh_id
               (get (Compiler_task.drain_completions ())))
        then fail "async mesh-pipeline completion ID was not drained";
        let async_mesh_pipeline =
          match get (Compiler_task.poll async_mesh_task) with
          | Compiler_task.Complete (Ok pipeline) -> pipeline
          | Compiler_task.Complete (Error error) ->
              fail "async mesh-pipeline compilation failed: %s"
                (Format.asprintf "%a" pp_error error)
          | Compiler_task.Pending ->
              fail "waited async mesh-pipeline compilation remained pending"
        in
        if get (Render_pipeline.label async_mesh_pipeline)
           <> Some "async reflected mesh"
           || Render_pipeline.kind async_mesh_pipeline
              <> Render_pipeline.Mesh
           || Option.is_none (Render_pipeline.reflection async_mesh_pipeline)
        then fail "async Metal 4 mesh-pipeline metadata is wrong";
        get (Render_pipeline.destroy async_mesh_pipeline);
        get (Compiler_task.destroy async_mesh_task);
        get (Render_pipeline.destroy mesh_pipeline);
        get (Library.destroy mesh_library);
        let tile_library =
          get
            (Compiler.compile_source ~name:"metal4-tile-library" compiler
               tile_shader_source)
        in
        if not (get (Device.supports_family device Device.Apple4)) then begin
          ignore
            (expect_error Unsupported
               (Compiler.create_tile_pipeline compiler ~library:tile_library
                  ~tile:"prismel_tile"));
          get (Library.destroy tile_library)
        end
        else begin
          let empty_tile_static : Compiler.static_linking =
            { functions = []; private_functions = []; groups = [] }
          in
          let before_invalid_tile = get (Release_queue.stats ()) in
          ignore
            (expect_error Invalid_argument
               (Compiler.create_tile_pipeline compiler ~library:tile_library
                  ~tile:"missing_tile"));
          ignore
            (expect_error Invalid_argument
               (Compiler.create_tile_pipeline_async compiler
                  ~library:tile_library ~tile:"missing_tile"));
          ignore
            (expect_error Invalid_argument
               (Compiler.create_tile_pipeline ~label:"invalid\000tile" compiler
                  ~library:tile_library ~tile:"prismel_tile"));
          ignore
            (expect_error Invalid_argument
               (Compiler.create_tile_pipeline
                  ~max_total_threads_per_threadgroup:0 compiler
                  ~library:tile_library ~tile:"prismel_tile"));
          ignore
            (expect_error Invalid_argument
               (Compiler.create_tile_pipeline
                  ~required_threads_per_threadgroup:(1, 0, 1) compiler
                  ~library:tile_library ~tile:"prismel_tile"));
          ignore
            (expect_error Invalid_argument
               (Compiler.create_tile_pipeline
                  ~max_total_threads_per_threadgroup:2
                  ~required_threads_per_threadgroup:(1, 1, 1) compiler
                  ~library:tile_library ~tile:"prismel_tile"));
          ignore
            (expect_error Invalid_argument
               (Compiler.create_tile_pipeline ~raster_sample_count:0 compiler
                  ~library:tile_library ~tile:"prismel_tile"));
          ignore
            (expect_error Invalid_argument
               (Compiler.create_tile_pipeline
                  ~color_formats:
                    [ Texture.Bgra8_unorm; Texture.Bgra8_unorm
                    ; Texture.Bgra8_unorm; Texture.Bgra8_unorm
                    ; Texture.Bgra8_unorm; Texture.Bgra8_unorm
                    ; Texture.Bgra8_unorm; Texture.Bgra8_unorm
                    ; Texture.Bgra8_unorm
                    ]
                  compiler ~library:tile_library ~tile:"prismel_tile"));
          ignore
            (expect_error Invalid_argument
               (Compiler.create_tile_pipeline
                  ~static_linking:empty_tile_static compiler
                  ~library:tile_library ~tile:"prismel_tile"));
          ignore
            (expect_error Native_error
               (Compiler.create_tile_pipeline compiler ~library:tile_library
                  ~tile:"prismel_not_tile"));
          let after_invalid_tile = get (Release_queue.stats ()) in
          if after_invalid_tile.total_created
             <> before_invalid_tile.total_created
          then fail "invalid Metal 4 tile inputs allocated native handles";
          let tile_static_provider =
            get
              (Compiler.compile_source ~name:"tile-static-provider" compiler
                 static_provider_source)
          in
          let tile_static_linking : Compiler.static_linking =
            { functions = []
            ; private_functions =
                [ { library = tile_static_provider
                  ; name = "private_static_identity"
                  }
                ]
            ; groups = []
            }
          in
          let tile_pipeline =
            get
              (Compiler.create_tile_pipeline ~label:"metal4 reflected tile"
                 ~reflection:true ~max_total_threads_per_threadgroup:1
                 ~required_threads_per_threadgroup:(1, 1, 1)
                 ~support_binary_linking:true
                 ~static_linking:tile_static_linking compiler
                 ~library:tile_library ~tile:"prismel_tile")
          in
          if get (Render_pipeline.label tile_pipeline)
             <> Some "metal4 reflected tile"
             || Render_pipeline.kind tile_pipeline <> Render_pipeline.Tile
          then fail "Metal 4 tile-pipeline metadata is wrong";
          (match Render_pipeline.reflection tile_pipeline with
           | Some reflection ->
               get
                 (Binding.validate_layout reflection.tile
                    ~expected:
                      [ { name = "tile_output"
                        ; index = 4L
                        ; access = Binding.Read_write
                        ; kind = Binding.Buffer_layout
                        ; data_type =
                            Some (Shader_type.Scalar Shader_type.Uint)
                        }
                      ]);
               if reflection.vertex <> [] || reflection.fragment <> []
                  || reflection.object_ <> [] || reflection.mesh <> []
               then
                 fail
                   "Metal 4 tile reflection populated an unrelated stage"
           | None -> fail "Metal 4 tile reflection is missing");
          get (Library.destroy tile_static_provider);
          let attachmentless_tile =
            get
              (Compiler.create_tile_pipeline ~color_formats:[]
                 ~threadgroup_size_matches_tile_size:true compiler
                 ~library:tile_library ~tile:"prismel_tile")
          in
          get (Render_pipeline.destroy attachmentless_tile);
          let async_tile_library =
            get
              (Compiler.compile_source ~name:"async-tile-source" compiler
                 tile_shader_source)
          in
          let async_tile_static_provider =
            get
              (Compiler.compile_source ~name:"async-tile-static-provider"
                 compiler static_provider_source)
          in
          let async_tile_static_linking : Compiler.static_linking =
            { functions = []
            ; private_functions =
                [ { library = async_tile_static_provider
                  ; name = "private_static_identity"
                  }
                ]
            ; groups = []
            }
          in
          let async_tile_task =
            get
              (Compiler.create_tile_pipeline_async
                 ~label:"async reflected tile" ~reflection:true
                 ~max_total_threads_per_threadgroup:1
                 ~required_threads_per_threadgroup:(1, 1, 1)
                 ~static_linking:async_tile_static_linking compiler
                 ~library:async_tile_library ~tile:"prismel_tile")
          in
          let async_tile_id = Compiler_task.id async_tile_task in
          get (Library.destroy async_tile_library);
          get (Library.destroy async_tile_static_provider);
          get (Compiler_task.wait async_tile_task);
          if
            not
              (List.mem async_tile_id
                 (get (Compiler_task.drain_completions ())))
          then fail "async tile-pipeline completion ID was not drained";
          let async_tile_pipeline =
            match get (Compiler_task.poll async_tile_task) with
            | Compiler_task.Complete (Ok pipeline) -> pipeline
            | Compiler_task.Complete (Error error) ->
                fail "async tile-pipeline compilation failed: %s"
                  (Format.asprintf "%a" pp_error error)
            | Compiler_task.Pending ->
                fail "waited async tile-pipeline compilation remained pending"
          in
          if get (Render_pipeline.label async_tile_pipeline)
             <> Some "async reflected tile"
             || Render_pipeline.kind async_tile_pipeline
                <> Render_pipeline.Tile
             || Option.is_none
                  (Render_pipeline.reflection async_tile_pipeline)
          then fail "async Metal 4 tile-pipeline metadata is wrong";
          get (Render_pipeline.destroy async_tile_pipeline);
          get (Compiler_task.destroy async_tile_task);
          get (Render_pipeline.destroy tile_pipeline);
          get (Library.destroy tile_library)
        end;
        let before_invalid_dynamic = get (Release_queue.stats ()) in
        ignore
          (expect_error Invalid_argument
             (Compiler.create_dynamic_library compiler library));
        ignore
          (expect_error Invalid_argument
             (Compiler.create_dynamic_library_async compiler library));
        ignore
          (expect_error Invalid_argument
             (Compiler.load_dynamic_library compiler "relative.metallib"));
        ignore
          (expect_error Invalid_argument
             (Compiler.load_dynamic_library_async compiler
                "relative.metallib"));
        let after_invalid_dynamic = get (Release_queue.stats ()) in
        if after_invalid_dynamic.total_created
           <> before_invalid_dynamic.total_created
        then
          fail
            "invalid Metal 4 dynamic-library inputs allocated native handles";
        let dynamic_source =
          get
            (Library.compile_dynamic_source ~device
               ~label:"Metal 4 dynamic source" ~install_name:dynamic_path
               dynamic_library_source)
        in
        let compiler_dynamic =
          get
            (Compiler.create_dynamic_library
               ~label:"Metal 4 compiler dynamic" compiler dynamic_source)
        in
        let unlabeled_compiler_dynamic =
          get (Compiler.create_dynamic_library compiler dynamic_source)
        in
        let async_dynamic_task =
          get
            (Compiler.create_dynamic_library_async
               ~label:"Metal 4 async dynamic" compiler dynamic_source)
        in
        let async_dynamic_id = Compiler_task.id async_dynamic_task in
        get (Library.destroy dynamic_source);
        get (Compiler_task.wait async_dynamic_task);
        if
          not
            (List.mem async_dynamic_id
               (get (Compiler_task.drain_completions ())))
        then fail "async dynamic-library completion ID was not drained";
        let async_dynamic =
          match get (Compiler_task.poll async_dynamic_task) with
          | Compiler_task.Complete (Ok library) -> library
          | Compiler_task.Complete (Error error) ->
              fail "async dynamic-library compilation failed: %s"
                (Format.asprintf "%a" pp_error error)
          | Compiler_task.Pending ->
              fail "waited async dynamic-library compilation remained pending"
        in
        if get (Dynamic_library.label compiler_dynamic)
           <> Some "Metal 4 compiler dynamic"
           || get (Dynamic_library.label unlabeled_compiler_dynamic) <> None
           || get (Dynamic_library.label async_dynamic)
              <> Some "Metal 4 async dynamic"
           || get (Dynamic_library.install_name compiler_dynamic)
              <> dynamic_path
           || get (Dynamic_library.install_name async_dynamic)
              <> dynamic_path
        then fail "Metal 4 compiler dynamic-library metadata is wrong";
        get (Dynamic_library.serialize compiler_dynamic dynamic_path);
        let loaded_compiler_dynamic =
          get
            (Compiler.load_dynamic_library
               ~label:"Metal 4 loaded dynamic" compiler dynamic_path)
        in
        let async_loaded_dynamic_task =
          get
            (Compiler.load_dynamic_library_async
               ~label:"Metal 4 async loaded dynamic" compiler dynamic_path)
        in
        let missing_dynamic_path = dynamic_path ^ ".missing" in
        let missing_dynamic_task =
          get
            (Compiler.load_dynamic_library_async
               ~label:"Metal 4 missing dynamic" compiler
               missing_dynamic_path)
        in
        let async_loaded_dynamic_id =
          Compiler_task.id async_loaded_dynamic_task
        in
        let missing_dynamic_id = Compiler_task.id missing_dynamic_task in
        get (Compiler_task.wait async_loaded_dynamic_task);
        get (Compiler_task.wait missing_dynamic_task);
        let loaded_dynamic_ids =
          get (Compiler_task.drain_completions ())
        in
        if not (List.mem async_loaded_dynamic_id loaded_dynamic_ids)
           || not (List.mem missing_dynamic_id loaded_dynamic_ids)
        then fail "async dynamic-library load IDs were not drained";
        let async_loaded_dynamic =
          match get (Compiler_task.poll async_loaded_dynamic_task) with
          | Compiler_task.Complete (Ok library) -> library
          | Compiler_task.Complete (Error error) ->
              fail "async dynamic-library load failed: %s"
                (Format.asprintf "%a" pp_error error)
          | Compiler_task.Pending ->
              fail "waited async dynamic-library load remained pending"
        in
        let missing_dynamic_diagnostic =
          match get (Compiler_task.poll missing_dynamic_task) with
          | Compiler_task.Complete (Error error) -> error
          | Compiler_task.Complete (Ok library) ->
              get (Dynamic_library.destroy library);
              fail "missing async dynamic-library path unexpectedly loaded"
          | Compiler_task.Pending ->
              fail "waited missing dynamic-library load remained pending"
        in
        if get (Dynamic_library.label loaded_compiler_dynamic)
           <> Some "Metal 4 loaded dynamic"
           || get (Dynamic_library.label async_loaded_dynamic)
              <> Some "Metal 4 async loaded dynamic"
           || get (Dynamic_library.install_name loaded_compiler_dynamic)
              <> dynamic_path
           || get (Dynamic_library.install_name async_loaded_dynamic)
              <> dynamic_path
        then fail "loaded Metal 4 dynamic-library metadata is wrong";
        if
          not
            (contains_substring missing_dynamic_diagnostic.message
               "Metal 4 missing dynamic")
          || not
               (contains_substring missing_dynamic_diagnostic.message
                  "domain=")
        then fail "async dynamic-library load lost its diagnostic";
        let dynamic_client_library =
          get
            (Dynamic_library.compile_source ~device
               ~label:"Metal 4 dynamic client"
               ~libraries:[ async_loaded_dynamic ] dynamic_client_source)
        in
        let dynamic_client_function =
          get
            (Function.find ~library:dynamic_client_library
               "call_dynamic_library")
        in
        let compiler_dynamic_pipeline =
          get
            (Compute_pipeline.create
               ~preloaded_libraries:[ async_loaded_dynamic ]
               dynamic_client_function)
        in
        get (Function.destroy dynamic_client_function);
        get (Library.destroy dynamic_client_library);
        get (Dynamic_library.destroy async_loaded_dynamic);
        get (Dynamic_library.destroy loaded_compiler_dynamic);
        get (Dynamic_library.destroy async_dynamic);
        get (Dynamic_library.destroy unlabeled_compiler_dynamic);
        get (Dynamic_library.destroy compiler_dynamic);
        get (Compiler_task.destroy missing_dynamic_task);
        get (Compiler_task.destroy async_loaded_dynamic_task);
        get (Compiler_task.destroy async_dynamic_task);
        run_pipeline_once device compiler_dynamic_pipeline ~initial:20l
          ~expected:33l;
        get (Compute_pipeline.destroy compiler_dynamic_pipeline);
        let async_compute_library =
          get
            (Compiler.compile_source ~name:"async-compute-source" compiler
               shader_source)
        in
        let async_compute_task =
          get
            (Compiler.create_compute_pipeline_async
               ~label:"async reflected increment" ~reflection:true
               ~max_total_threads_per_threadgroup:1
               ~required_threads_per_threadgroup:(1, 1, 1) compiler
               ~library:async_compute_library "increment")
        in
        let async_compute_id = Compiler_task.id async_compute_task in
        get (Library.destroy async_compute_library);
        get (Compiler_task.wait async_compute_task);
        let async_compute_ids =
          get (Compiler_task.drain_completions ())
        in
        if not (List.mem async_compute_id async_compute_ids)
        then fail "async compute-pipeline completion IDs were not drained";
        let async_compute_pipeline =
          match get (Compiler_task.poll async_compute_task) with
          | Compiler_task.Complete (Ok pipeline) -> pipeline
          | Compiler_task.Complete (Error error) ->
              fail "async compute-pipeline compilation failed: %s"
                (Format.asprintf "%a" pp_error error)
          | Compiler_task.Pending ->
              fail "waited async compute-pipeline compilation remained pending"
        in
        if get (Compute_pipeline.label async_compute_pipeline)
           <> Some "async reflected increment"
        then fail "async Metal 4 compute-pipeline label did not round-trip";
        let async_compute_bindings =
          match Compute_pipeline.bindings async_compute_pipeline with
          | Some bindings -> bindings
          | None -> fail "async Metal 4 compute reflection is missing"
        in
        get
          (Binding.validate_layout async_compute_bindings
             ~expected:
               [ { name = "values"
                 ; index = 0L
                 ; access = Binding.Read_write
                 ; kind = Binding.Buffer_layout
                 ; data_type = Some (Shader_type.Scalar Shader_type.Uint)
                 }
               ]);
        run_pipeline_once device async_compute_pipeline ~initial:13l
          ~expected:14l;
        get (Compute_pipeline.destroy async_compute_pipeline);
        get (Compiler_task.destroy async_compute_task);
        let visible_source =
          get (Function.find ~library "linked_identity")
        in
        let kernel_source = get (Function.find ~library "increment") in
        if get (Function.kind visible_source) <> Function.Visible then
          fail "Metal 4 binary-function source is not visible";
        let before_invalid_binary = get (Release_queue.stats ()) in
        ignore
          (expect_error Invalid_argument
             (Compiler.create_binary_function compiler ~source:visible_source
                ~name:""));
        ignore
          (expect_error Invalid_argument
             (Compiler.create_binary_function compiler ~source:kernel_source
                ~name:"invalid-kernel-binary"));
        ignore
          (expect_error Invalid_argument
             (Compiler.create_binary_function_async compiler
                ~source:visible_source ~name:""));
        ignore
          (expect_error Invalid_argument
             (Compiler.create_binary_function_async compiler
                ~source:kernel_source ~name:"invalid-async-kernel-binary"));
        let after_invalid_binary = get (Release_queue.stats ()) in
        if after_invalid_binary.total_created
           <> before_invalid_binary.total_created
        then fail "invalid Metal 4 binary functions allocated native handles";
        let async_binary_library =
          get
            (Compiler.compile_source ~name:"async-binary-source" compiler
               shader_source)
        in
        let async_binary_source =
          get (Function.find ~library:async_binary_library "linked_identity")
        in
        let async_binary_task =
          get
            (Compiler.create_binary_function_async
               ~pipeline_independent:true compiler
               ~source:async_binary_source ~name:"async-visible-binary")
        in
        let async_binary_id = Compiler_task.id async_binary_task in
        get (Function.destroy async_binary_source);
        get (Library.destroy async_binary_library);
        get (Compiler_task.wait async_binary_task);
        if
          not
            (List.mem async_binary_id
               (get (Compiler_task.drain_completions ())))
        then fail "async binary-function completion ID was not drained";
        let async_binary =
          match get (Compiler_task.poll async_binary_task) with
          | Compiler_task.Complete (Ok function_) -> function_
          | Compiler_task.Complete (Error error) ->
              fail "async binary-function compilation failed: %s"
                (Format.asprintf "%a" pp_error error)
          | Compiler_task.Pending ->
              fail "waited async binary-function compilation remained pending"
        in
        if Binary_function.name async_binary <> "async-visible-binary"
           || Binary_function.kind async_binary <> Function.Visible
           || not (Binary_function.pipeline_independent async_binary)
        then fail "async Metal 4 binary-function metadata is wrong";
        get (Binary_function.destroy async_binary);
        get (Compiler_task.destroy async_binary_task);
        let before_binary_finalizer = get (Release_queue.stats ()) in
        let allocate_unreleased_binary_function () =
          ignore
            (get
               (Compiler.create_binary_function compiler
                  ~source:visible_source ~name:"finalized-visible"))
        in
        allocate_unreleased_binary_function ();
        let after_binary_finalizer =
          settle_finalizers
            ~expected_live:before_binary_finalizer.live_handles
        in
        if
          Int64.sub after_binary_finalizer.total_created
            before_binary_finalizer.total_created
          <> 1L
          || Int64.sub after_binary_finalizer.total_released
               before_binary_finalizer.total_released
             <> 1L
        then
          fail
            "Metal 4 binary-function finalization did not release one handle";
        let static_visible : Compiler.static_function =
          { library; name = "linked_identity" }
        in
        let empty_static : Compiler.static_linking =
          { functions = []; private_functions = []; groups = [] }
        in
        let invalid_static_name : Compiler.static_linking =
          { functions = [ { library; name = "invalid\000name" } ]
          ; private_functions = []
          ; groups = []
          }
        in
        let before_invalid_static = get (Release_queue.stats ()) in
        ignore
          (expect_error Invalid_argument
             (Compiler.create_compute_pipeline ~static_linking:empty_static
                compiler ~library "increment"));
        ignore
          (expect_error Invalid_argument
             (Compiler.create_compute_pipeline
                ~static_linking:invalid_static_name compiler ~library
                "increment"));
        ignore
          (expect_error Invalid_argument
             (Compiler.create_compute_pipeline
                ~static_linking:
                  { functions = [ static_visible; static_visible ]
                  ; private_functions = []
                  ; groups = []
                  }
                compiler ~library "increment"));
        ignore
          (expect_error Invalid_argument
             (Compiler.create_compute_pipeline
                ~static_linking:
                  { functions = [ static_visible ]
                  ; private_functions = [ static_visible ]
                  ; groups = []
                  }
                compiler ~library "increment"));
        ignore
          (expect_error Invalid_argument
             (Compiler.create_compute_pipeline
                ~static_linking:
                  { functions = [ static_visible ]
                  ; private_functions = []
                  ; groups = [ "empty", [] ]
                  }
                compiler ~library "increment"));
        ignore
          (expect_error Invalid_argument
             (Compiler.create_compute_pipeline
                ~static_linking:
                  { functions = [ static_visible ]
                  ; private_functions = []
                  ; groups =
                      [ "identity", [ static_visible ]
                      ; "identity", [ static_visible ]
                      ]
                  }
                compiler ~library "increment"));
        let after_invalid_static = get (Release_queue.stats ()) in
        if after_invalid_static.total_created
           <> before_invalid_static.total_created
        then fail "invalid Metal 4 static linking allocated native handles";
        let static_provider =
          get
            (Compiler.compile_source ~name:"static-provider" compiler
               static_provider_source)
        in
        let static_client =
          get
            (Compiler.compile_source ~name:"static-client" compiler
               static_client_source)
        in
        let static_public : Compiler.static_function =
          { library = static_provider; name = "public_static_identity" }
        in
        let static_private : Compiler.static_function =
          { library = static_provider; name = "private_static_identity" }
        in
        let static_linking : Compiler.static_linking =
          { functions = [ static_public ]
          ; private_functions = [ static_private ]
          ; groups = [ "identity", [ static_public ] ]
          }
        in
        let static_pipeline =
          get
            (Compiler.create_compute_pipeline ~static_linking compiler
               ~library:static_client "call_static_library")
        in
        get (Library.destroy static_client);
        get (Library.destroy static_provider);
        ignore
          (expect_error Destroyed
             (Compiler.create_compute_pipeline
                ~static_linking:
                  { functions = []
                  ; private_functions =
                      [ { library = static_client
                        ; name = "call_static_library"
                        }
                      ]
                  ; groups = []
                  }
                compiler ~library "increment"));
        run_pipeline_once device static_pipeline ~initial:25l ~expected:42l;
        get (Compute_pipeline.destroy static_pipeline);
        let pipeline =
          get
            (Compiler.create_compute_pipeline
               ~label:"metal4 reflected increment" ~reflection:true
               ~max_total_threads_per_threadgroup:1
               ~required_threads_per_threadgroup:(1, 1, 1)
               ~support_binary_linking:true
               ~support_indirect_command_buffers:true compiler ~library
               "increment")
        in
        if get (Compute_pipeline.label pipeline)
           <> Some "metal4 reflected increment"
        then fail "Metal 4 compute-pipeline label did not round-trip";
        let reflected_bindings =
          match Compute_pipeline.bindings pipeline with
          | Some bindings -> bindings
          | None -> fail "Metal 4 compute reflection is missing"
        in
        get
          (Binding.validate_layout reflected_bindings
             ~expected:
               [ { name = "values"
                 ; index = 0L
                 ; access = Binding.Read_write
                 ; kind = Binding.Buffer_layout
                 ; data_type = Some (Shader_type.Scalar Shader_type.Uint)
                 }
               ]);
        let script = get (Pipeline_dataset.serialize_script dataset) in
        if Bytes.length script = 0 then
          fail "Metal 4 pipeline script serialization returned no data";
        let binary_dataset =
          get
            (Pipeline_dataset.create ~device [ Pipeline_dataset.Binaries ])
        in
        let binary_compiler =
          get (Compiler.create ~dataset:binary_dataset device)
        in
        let captured_binary =
          get
            (Compiler.create_binary_function ~pipeline_independent:true
               binary_compiler ~source:visible_source
               ~name:"metal4-linked-identity")
        in
        if Binary_function.name captured_binary <> "metal4-linked-identity"
           || Binary_function.kind captured_binary <> Function.Visible
           || not (Binary_function.pipeline_independent captured_binary)
           || not
                (Device.same device (Binary_function.device captured_binary))
        then fail "Metal 4 binary-function metadata is wrong";
        if get (Device.supports_family device Device.Apple9) then begin
          let async_linked_pipeline_task =
            get
              (Compiler.create_compute_pipeline_async
                 ~label:"async dynamically linked increment"
                 ~support_binary_linking:true binary_compiler ~library
                 ~binary_linked_functions:[ captured_binary ] "increment")
          in
          let async_linked_pipeline_id =
            Compiler_task.id async_linked_pipeline_task
          in
          get (Compiler_task.wait async_linked_pipeline_task);
          if
            not
              (List.mem async_linked_pipeline_id
                 (get (Compiler_task.drain_completions ())))
          then fail "async dynamically linked completion ID was not drained";
          let async_linked_pipeline =
            match get (Compiler_task.poll async_linked_pipeline_task) with
            | Compiler_task.Complete (Ok pipeline) -> pipeline
            | Compiler_task.Complete (Error error) ->
                fail "async dynamically linked pipeline failed: %s"
                  (Format.asprintf "%a" pp_error error)
            | Compiler_task.Pending ->
                fail
                  "waited async dynamically linked pipeline remained pending"
          in
          get (Compiler_task.destroy async_linked_pipeline_task);
          run_pipeline_once device async_linked_pipeline ~initial:31l
            ~expected:32l;
          get (Compute_pipeline.destroy async_linked_pipeline)
        end
        else begin
          let before_async_dynamic = get (Release_queue.stats ()) in
          ignore
            (expect_error Unsupported
               (Compiler.create_compute_pipeline_async
                  ~support_binary_linking:true binary_compiler ~library
                  ~binary_linked_functions:[ captured_binary ] "increment"));
          let after_async_dynamic = get (Release_queue.stats ()) in
          if after_async_dynamic.total_created
             <> before_async_dynamic.total_created
          then
            fail
              "unsupported async dynamic linking allocated a native handle"
        end;
        let archive_seed_pipeline =
          get
            (Compiler.create_compute_pipeline
               ~label:"metal4 archived increment"
               ~max_total_threads_per_threadgroup:1
               ~required_threads_per_threadgroup:(1, 1, 1)
               ~support_binary_linking:true
               ~support_indirect_command_buffers:true binary_compiler ~library
               ~binary_linked_functions:[ captured_binary ]
               "increment")
        in
        get (Pipeline_dataset.serialize_archive binary_dataset archive_path);
        if not (Sys.file_exists archive_path) then
          fail "Metal 4 pipeline archive was not serialized";
        let archive =
          get
            (Pipeline_archive.load_file ~device
               ~label:"reloaded Metal 4 archive" archive_path)
        in
        if get (Pipeline_archive.label archive)
           <> Some "reloaded Metal 4 archive"
           || not (Device.same device (Pipeline_archive.device archive))
        then fail "reloaded Metal 4 pipeline-archive metadata is wrong";
        let lookup_compiler = get (Compiler.create device) in
        let uncaptured_library =
          get
            (Compiler.compile_source ~name:"uncaptured-visible-library"
               lookup_compiler uncaptured_visible_source)
        in
        let uncaptured_source =
          get (Function.find ~library:uncaptured_library "never_captured")
        in
        let missing_binary =
          expect_error Native_error
            (Pipeline_archive.load_binary_function archive
               ~pipeline_independent:true ~source:uncaptured_source
               ~name:"missing-metal4-binary")
        in
        if
          not
            (contains_substring missing_binary.message
               "missing-metal4-binary")
        then fail "Metal 4 archive lookup lost its binary-function identity";
        get (Function.destroy uncaptured_source);
        get (Library.destroy uncaptured_library);
        let archived_binary =
          get
            (Pipeline_archive.load_binary_function archive
               ~pipeline_independent:true ~source:visible_source
               ~name:"metal4-linked-identity")
        in
        let before_duplicate_archive = get (Release_queue.stats ()) in
        ignore
          (expect_error Invalid_argument
             (Compiler.create_compute_pipeline
                ~lookup_archives:[ archive; archive ] lookup_compiler ~library
                "increment"));
        let after_duplicate_archive = get (Release_queue.stats ()) in
        if after_duplicate_archive.total_created
           <> before_duplicate_archive.total_created
        then fail "duplicate Metal 4 archives allocated a native handle";
        ignore
          (expect_error Invalid_argument
             (Compiler.create_binary_function
                ~lookup_archives:[ archive; archive ] lookup_compiler
                ~source:visible_source ~name:"metal4-linked-identity"));
        let looked_up_binary =
          get
            (Compiler.create_binary_function ~pipeline_independent:true
               ~lookup_archives:[ archive ] lookup_compiler
               ~source:visible_source ~name:"metal4-linked-identity")
        in
        let before_duplicate_binary = get (Release_queue.stats ()) in
        ignore
          (expect_error Invalid_argument
             (Compiler.create_compute_pipeline
                ~binary_linked_functions:[ archived_binary ] lookup_compiler
                ~library "increment"));
        ignore
          (expect_error Invalid_argument
             (Compiler.create_compute_pipeline
                ~binary_linked_functions:[ archived_binary; archived_binary ]
                lookup_compiler ~library "increment"));
        let after_duplicate_binary = get (Release_queue.stats ()) in
        if after_duplicate_binary.total_created
           <> before_duplicate_binary.total_created
        then fail "duplicate Metal 4 binary functions allocated a native handle";
        let archived_pipeline =
          get
            (Compiler.create_compute_pipeline
               ~label:"metal4 archived increment"
               ~max_total_threads_per_threadgroup:1
               ~required_threads_per_threadgroup:(1, 1, 1)
               ~support_binary_linking:true
               ~support_indirect_command_buffers:true
               ~binary_linked_functions:[ archived_binary ]
               ~lookup_archives:[ archive ] lookup_compiler ~library
               "increment")
        in
        get (Pipeline_archive.destroy archive);
        get (Compiler.destroy lookup_compiler);
        ignore
          (expect_error Destroyed
             (Pipeline_archive.load_binary_function archive
                ~pipeline_independent:true ~source:visible_source
                ~name:"metal4-linked-identity"));
        ignore
          (expect_error Destroyed
             (Compiler.create_binary_function lookup_compiler
                ~source:visible_source ~name:"metal4-linked-identity"));
        get (Binary_function.destroy looked_up_binary);
        get (Binary_function.destroy archived_binary);
        get (Binary_function.destroy captured_binary);
        get (Function.destroy kernel_source);
        get (Function.destroy visible_source);
        get (Library.destroy library);
        get (Compiler.destroy binary_compiler);
        get (Pipeline_dataset.destroy binary_dataset);
        get (Compiler.destroy compiler);
        get (Pipeline_dataset.destroy dataset);
        ignore (expect_error Destroyed (Compiler.label compiler));
        ignore
          (expect_error Destroyed
             (Pipeline_dataset.serialize_script dataset));
        if not (Binary_function.destroyed captured_binary) then
          fail "destroyed Metal 4 binary function remained live";
        run_pipeline_once device pipeline ~initial:4l ~expected:5l;
        run_pipeline_once device archive_seed_pipeline ~initial:6l ~expected:7l;
        run_pipeline_once device archived_pipeline ~initial:8l ~expected:9l;
        get (Compute_pipeline.destroy archived_pipeline);
        get (Compute_pipeline.destroy archive_seed_pipeline);
        get (Compute_pipeline.destroy pipeline));
    true
  end

let test_metal4_render_commands device =
  if not (get (Device.supports_family device Device.Metal4)) then false
  else begin
    let before_invalid = get (Release_queue.stats ()) in
    ignore
      (expect_error Invalid_argument
         (Command4.Allocator.create ~label:"invalid\000allocator" device));
    ignore
      (expect_error Invalid_argument
         (Command4.Queue.create ~label:"invalid\000queue" device));
    ignore
      (expect_error Invalid_argument
         (Command4.Argument_table.create device ()));
    ignore
      (expect_error Invalid_argument
         (Command4.Argument_table.create ~max_buffers:32 device ()));
    ignore
      (expect_error Invalid_argument
         (Command4.Argument_table.create ~max_textures:129 device ()));
    ignore
      (expect_error Invalid_argument
         (Command4.Argument_table.create ~max_samplers:17 device ()));
    ignore
      (expect_error Invalid_argument
         (Command4.Argument_table.create ~label:"invalid\000arguments"
            ~max_buffers:1 device ()));
    ignore
      (expect_error Native_error
         (Command4.Allocator.create ~label:"\255" device));
    ignore
      (expect_error Native_error
         (Command4.Argument_table.create ~label:"\255" ~max_buffers:1 device
            ()));
    ignore
      (expect_error Wrong_domain
         (Domain.spawn (fun () -> Command4.Allocator.create device)
          |> Domain.join));
    ignore
      (expect_error Wrong_domain
         (Domain.spawn (fun () ->
              Command4.Argument_table.create ~max_buffers:1 device ())
          |> Domain.join));
    let after_invalid = get (Release_queue.stats ()) in
    if after_invalid.total_created <> before_invalid.total_created then
      fail "invalid Metal 4 command labels allocated native handles";
    let allocator =
      get (Command4.Allocator.create ~label:"Metal 4 allocator" device)
    in
    let queue = get (Command4.Queue.create ~label:"Metal 4 queue" device) in
    if get (Command4.Allocator.label allocator) <> Some "Metal 4 allocator"
       || get (Command4.Queue.label queue) <> Some "Metal 4 queue"
       || not (Device.same device (Command4.Allocator.device allocator))
       || not (Device.same device (Command4.Queue.device queue))
       || Command4.Allocator.generation allocator <= 0L
       || Command4.Queue.generation queue <= 0L
    then fail "Metal 4 command allocator/queue metadata is wrong";
    let commands =
      get
        (Command4.Command_buffer.create allocator ~label:"Metal 4 render commands"
           ())
    in
    if get (Command4.Command_buffer.label commands)
       <> Some "Metal 4 render commands"
       || Command4.Command_buffer.state commands
          <> Command4.Command_buffer.Recording
       || not (Device.same device (Command4.Command_buffer.device commands))
       || Command4.Command_buffer.generation commands <= 0L
    then fail "Metal 4 command-buffer metadata is wrong";
    ignore
      (expect_error Invalid_state
         (Command4.Command_buffer.create allocator ()));
    ignore
      (expect_error Invalid_state (Command4.Allocator.reset allocator));
    ignore
      (expect_error Parent_has_dependents
         (Command4.Allocator.destroy allocator));
    let render_target_descriptor =
      Texture.descriptor_2d ~storage:Buffer.Shared
        ~usage:[ Texture.Render_target ] ~format:Texture.Bgra8_unorm ~width:8
        ~height:8 ~label:"Metal 4 offscreen render target" ()
    in
    let render_target = get (Texture.create ~device render_target_descriptor) in
    let non_target =
      get
        (Texture.create ~device
           (Texture.descriptor_2d ~storage:Buffer.Shared
              ~usage:[ Texture.Shader_read ] ~format:Texture.Bgra8_unorm
              ~width:8 ~height:8 ()))
    in
    let tint_buffer =
      get (Buffer.create ~device ~length:16L ~storage:Buffer.Shared ())
    in
    let tint_bytes = Bytes.create 16 in
    [| 0.; 1.; 0.; 1. |]
    |> Array.iteri (fun index component ->
      Bytes.set_int32_le tint_bytes (index * 4) (Int32.bits_of_float component));
    get (Buffer.write_bytes tint_buffer ~dst_offset:0L tint_bytes);
    let transient_buffer =
      get (Buffer.create ~device ~length:16L ~storage:Buffer.Shared ())
    in
    let transient_texture =
      get
        (Texture.create ~device
           (Texture.descriptor_2d ~storage:Buffer.Shared
              ~usage:[ Texture.Shader_read ] ~format:Texture.Rgba8_unorm
              ~width:1 ~height:1 ()))
    in
    let transient_sampler = get (Sampler.create ~device (Sampler.default ())) in
    let arguments =
      get
        (Command4.Argument_table.create ~label:"Metal 4 render arguments"
           ~max_buffers:2 ~max_textures:1 ~max_samplers:1 device ())
    in
    if get (Command4.Argument_table.label arguments)
       <> Some "Metal 4 render arguments"
       || Command4.Argument_table.max_buffers arguments <> 2
       || Command4.Argument_table.max_textures arguments <> 1
       || Command4.Argument_table.max_samplers arguments <> 1
       || not (Command4.Argument_table.initializes_bindings arguments)
       || Command4.Argument_table.supports_attribute_strides arguments
       || not
            (Device.same device (Command4.Argument_table.device arguments))
       || Command4.Argument_table.generation arguments <= 0L
    then fail "Metal 4 argument-table metadata is wrong";
    ignore
      (expect_error Invalid_argument
         (Command4.Argument_table.set_buffer arguments ~index:2 tint_buffer));
    ignore
      (expect_error Invalid_argument
         (Command4.Argument_table.set_buffer arguments ~index:0 ~offset:16L
            tint_buffer));
    ignore
      (expect_error Invalid_argument
         (Command4.Argument_table.set_buffer arguments ~index:0
            ~attribute_stride:16 transient_buffer));
    let stride_arguments =
      get
        (Command4.Argument_table.create ~initialize_bindings:false
           ~support_attribute_strides:true ~max_buffers:1 device ())
    in
    if Command4.Argument_table.initializes_bindings stride_arguments
       || not
            (Command4.Argument_table.supports_attribute_strides
               stride_arguments)
    then fail "Metal 4 argument-table stride policy is wrong";
    get
      (Command4.Argument_table.set_buffer stride_arguments ~index:0
         ~attribute_stride:16 transient_buffer);
    get (Command4.Argument_table.clear_buffer stride_arguments ~index:0);
    get (Command4.Argument_table.destroy stride_arguments);
    get (Command4.Argument_table.destroy stride_arguments);
    if not (Command4.Argument_table.destroyed stride_arguments) then
      fail "destroyed Metal 4 argument table remained live";
    ignore
      (expect_error Destroyed
         (Command4.Argument_table.label stride_arguments));
    get
      (Command4.Argument_table.set_buffer arguments ~index:0 transient_buffer);
    ignore (expect_error Parent_has_dependents (Buffer.destroy transient_buffer));
    get (Command4.Argument_table.clear_buffer arguments ~index:0);
    get (Buffer.destroy transient_buffer);
    get
      (Command4.Argument_table.set_texture arguments ~index:0
         transient_texture);
    ignore
      (expect_error Invalid_argument
         (Command4.Argument_table.set_texture arguments ~index:1
            transient_texture));
    ignore
      (expect_error Parent_has_dependents (Texture.destroy transient_texture));
    get (Command4.Argument_table.clear_texture arguments ~index:0);
    get (Texture.destroy transient_texture);
    get
      (Command4.Argument_table.set_sampler arguments ~index:0
         transient_sampler);
    ignore
      (expect_error Invalid_argument
         (Command4.Argument_table.set_sampler arguments ~index:1
            transient_sampler));
    ignore
      (expect_error Parent_has_dependents (Sampler.destroy transient_sampler));
    get (Command4.Argument_table.clear_sampler arguments ~index:0);
    get (Sampler.destroy transient_sampler);
    get (Command4.Argument_table.set_buffer arguments ~index:1 tint_buffer);
    ignore (expect_error Parent_has_dependents (Buffer.destroy tint_buffer));
    let clear =
      Command4.Render_encoder.color ~red:1. ~green:0. ~blue:0. ~alpha:1.
    in
    let attachment =
      Command4.Render_encoder.color_attachment
        ~load_action:(Command4.Render_encoder.Clear clear) render_target
    in
    let invalid_clear =
      Command4.Render_encoder.color ~red:nan ~green:0. ~blue:0. ~alpha:1.
    in
    ignore
      (expect_error Invalid_argument
         (Command4.Render_encoder.create commands ~color_attachments:[]));
    ignore
      (expect_error Invalid_argument
         (Command4.Render_encoder.create commands
            ~color_attachments:(List.init 9 (fun _ -> attachment))));
    ignore
      (expect_error Invalid_argument
         (Command4.Render_encoder.create commands
            ~color_attachments:
              [ Command4.Render_encoder.color_attachment
                  ~load_action:(Command4.Render_encoder.Clear invalid_clear)
                  render_target
              ]));
    ignore
      (expect_error Invalid_argument
         (Command4.Render_encoder.create commands
            ~color_attachments:
              [ Command4.Render_encoder.color_attachment non_target ]));
    let compiler = get (Compiler.create device) in
    let library =
      get
        (Compiler.compile_source ~name:"metal4-command-render-library" compiler
           render_shader_source)
    in
    let pipeline =
      get
        (Compiler.create_render_pipeline ~label:"Metal 4 executable render"
           ~fragment:"prismel_fragment" compiler ~library
           ~vertex:"prismel_fullscreen_vertex")
    in
    if Render_pipeline.raster_sample_count pipeline <> 1
       || Render_pipeline.color_formats pipeline <> [ Texture.Bgra8_unorm ]
    then fail "Metal 4 render pipeline lost target metadata";
    let encoder =
      get
        (Command4.Render_encoder.create ~label:"Metal 4 render encoder" commands
           ~color_attachments:[ attachment ])
    in
    ignore
      (expect_error Parent_has_dependents (Texture.destroy render_target));
    ignore
      (expect_error Invalid_state
         (Command4.Command_buffer.end_recording commands));
    ignore
      (expect_error Invalid_state
         (Command4.Render_encoder.draw_primitives encoder
            Command4.Render_encoder.Triangle ~vertex_start:0 ~vertex_count:3));
    ignore
      (expect_error Invalid_argument
         (Command4.Render_encoder.set_viewport encoder
            (Command4.Render_encoder.viewport ~x:0. ~y:0. ~width:9. ~height:8.
               ~z_near:0. ~z_far:1.)));
    get (Command4.Render_encoder.set_pipeline encoder pipeline);
    ignore
      (expect_error Invalid_argument
         (Command4.Render_encoder.set_argument_table encoder ~stages:[]
            (Some arguments)));
    ignore
      (expect_error Invalid_argument
         (Command4.Render_encoder.set_argument_table encoder
            ~stages:
              [ Command4.Render_encoder.Fragment
              ; Command4.Render_encoder.Fragment
              ]
            (Some arguments)));
    get
      (Command4.Render_encoder.set_argument_table encoder
         ~stages:[ Command4.Render_encoder.Fragment ] (Some arguments));
    ignore
      (expect_error Parent_has_dependents
         (Command4.Argument_table.destroy arguments));
    get
      (Command4.Render_encoder.set_argument_table encoder
         ~stages:[ Command4.Render_encoder.Fragment ] None);
    get
      (Command4.Render_encoder.set_argument_table encoder
         ~stages:[ Command4.Render_encoder.Fragment ] (Some arguments));
    ignore
      (expect_error Parent_has_dependents (Render_pipeline.destroy pipeline));
    get
      (Command4.Render_encoder.set_viewport encoder
         (Command4.Render_encoder.viewport ~x:0. ~y:0. ~width:8. ~height:8.
            ~z_near:0. ~z_far:1.));
    ignore
      (expect_error Invalid_argument
         (Command4.Render_encoder.draw_primitives encoder
            Command4.Render_encoder.Triangle ~vertex_start:(-1) ~vertex_count:3));
    get
      (Command4.Render_encoder.draw_primitives encoder
         Command4.Render_encoder.Triangle ~vertex_start:0 ~vertex_count:3);
    get (Command4.Render_encoder.end_encoding encoder);
    if not (Command4.Render_encoder.destroyed encoder) then
      fail "ended Metal 4 render encoder remained live";
    get (Command4.Command_buffer.end_recording commands);
    if Command4.Command_buffer.state commands <> Command4.Command_buffer.Ended then
      fail "ended Metal 4 command buffer retained the recording state";
    let empty_commands = get (Command4.Command_buffer.create allocator ()) in
    get (Command4.Command_buffer.end_recording empty_commands);
    get (Command4.Command_buffer.destroy empty_commands);
    ignore (expect_error Invalid_argument (Command4.Queue.commit queue []));
    ignore
      (expect_error Invalid_argument
         (Command4.Queue.commit queue [ commands; commands ]));
    let submission = get (Command4.Queue.commit queue [ commands ]) in
    if Command4.Submission.completed submission
       || not (Device.same device (Command4.Submission.device submission))
       || Command4.Submission.generation submission <= 0L
       || Command4.Command_buffer.state commands
          <> Command4.Command_buffer.Submitted
    then fail "Metal 4 submission metadata is wrong";
    ignore
      (expect_error Parent_has_dependents (Command4.Queue.destroy queue));
    ignore
      (expect_error Invalid_state
         (Command4.Command_buffer.destroy commands));
    ignore
      (expect_error Invalid_state (Command4.Submission.destroy submission));
    get (Command4.Submission.wait submission);
    get (Command4.Submission.wait submission);
    if not (Command4.Submission.completed submission)
       || Command4.Command_buffer.state commands
          <> Command4.Command_buffer.Completed
    then fail "waited Metal 4 submission did not complete";
    let pixels =
      get
        (Texture.read_bytes render_target
           ~region:{ Texture.x = 0; y = 0; z = 0; width = 8; height = 8; depth = 1 }
           ~mip_level:0 ~slice:0 ~bytes_per_row:32 ~bytes_per_image:256)
    in
    for offset = 0 to 63 do
      let pixel = offset * 4 in
      if Char.code (Bytes.get pixels pixel) <> 0
         || Char.code (Bytes.get pixels (pixel + 1)) <> 255
         || Char.code (Bytes.get pixels (pixel + 2)) <> 0
         || Char.code (Bytes.get pixels (pixel + 3)) <> 255
      then fail "Metal 4 offscreen draw produced a wrong pixel at index %d" offset
    done;
    get (Render_pipeline.destroy pipeline);
    get (Texture.destroy render_target);
    get (Texture.destroy non_target);
    get (Command4.Argument_table.destroy arguments);
    if not (Command4.Argument_table.destroyed arguments) then
      fail "destroyed render argument table remained live";
    get (Buffer.destroy tint_buffer);
    get (Command4.Submission.destroy submission);
    get (Command4.Command_buffer.destroy commands);
    if get (Command4.Allocator.allocated_size allocator) < 0L then
      fail "Metal 4 allocator reported a negative size";
    get (Command4.Allocator.reset allocator);
    get (Command4.Queue.destroy queue);
    get (Command4.Allocator.destroy allocator);
    get (Library.destroy library);
    get (Compiler.destroy compiler);
    Printf.printf "Metal 4 offscreen render-command conformance passed\n%!";
    true
  end

let test_metal4_compute_commands device =
  if not (get (Device.supports_family device Device.Metal4)) then false
  else begin
    let compiler = get (Compiler.create device) in
    let library =
      get
        (Compiler.compile_source ~name:"metal4-command-compute-library"
           compiler shader_source)
    in
    let pipeline =
      get
        (Compiler.create_compute_pipeline ~label:"Metal 4 executable compute"
           compiler ~library "increment")
    in
    let buffer =
      get (Buffer.create ~device ~length:16L ~storage:Buffer.Shared ())
    in
    get (Buffer.write_bytes buffer ~dst_offset:0L (input_values ()));
    let arguments =
      get
        (Command4.Argument_table.create ~label:"Metal 4 compute arguments"
           ~max_buffers:1 device ())
    in
    get (Command4.Argument_table.set_buffer arguments ~index:0 buffer);
    let allocator =
      get (Command4.Allocator.create ~label:"Metal 4 compute allocator" device)
    in
    let queue =
      get (Command4.Queue.create ~label:"Metal 4 compute queue" device)
    in
    let commands =
      get
        (Command4.Command_buffer.create allocator
           ~label:"Metal 4 compute commands" ())
    in
    let before_invalid = get (Release_queue.stats ()) in
    ignore
      (expect_error Invalid_argument
         (Command4.Compute_encoder.create ~label:"invalid\000compute" commands));
    let after_invalid = get (Release_queue.stats ()) in
    if after_invalid.total_created <> before_invalid.total_created then
      fail "invalid Metal 4 compute-encoder label allocated a native handle";
    let encoder =
      get
        (Command4.Compute_encoder.create ~label:"Metal 4 compute encoder"
           commands)
    in
    ignore
      (expect_error Invalid_state
         (Command4.Command_buffer.end_recording commands));
    ignore
      (expect_error Invalid_state
         (Command4.Compute_encoder.dispatch_threads encoder
            ~threads:(4, 1, 1) ~threadgroup:(4, 1, 1)));
    get (Command4.Compute_encoder.set_pipeline encoder pipeline);
    ignore
      (expect_error Parent_has_dependents
         (Compute_pipeline.destroy pipeline));
    get (Command4.Compute_encoder.set_argument_table encoder (Some arguments));
    ignore
      (expect_error Parent_has_dependents
         (Command4.Argument_table.destroy arguments));
    ignore (expect_error Parent_has_dependents (Buffer.destroy buffer));
    get (Command4.Compute_encoder.set_argument_table encoder None);
    get (Command4.Compute_encoder.set_argument_table encoder (Some arguments));
    ignore
      (expect_error Invalid_argument
         (Command4.Compute_encoder.dispatch_threads encoder
            ~threads:(0, 1, 1) ~threadgroup:(1, 1, 1)));
    ignore
      (expect_error Invalid_argument
         (Command4.Compute_encoder.dispatch_threads encoder
            ~threads:(4, 1, 1) ~threadgroup:(max_int, 2, 1)));
    ignore
      (expect_error Invalid_argument
         (Command4.Compute_encoder.dispatch_threads encoder
            ~threads:(4, 1, 1)
            ~threadgroup:
              ( Compute_pipeline.max_total_threads_per_threadgroup pipeline + 1
              , 1
              , 1 )));
    get
      (Command4.Compute_encoder.dispatch_threads encoder ~threads:(4, 1, 1)
         ~threadgroup:(4, 1, 1));
    get (Command4.Argument_table.clear_buffer arguments ~index:0);
    ignore (expect_error Parent_has_dependents (Buffer.destroy buffer));
    get (Command4.Compute_encoder.end_encoding encoder);
    if not (Command4.Compute_encoder.destroyed encoder) then
      fail "ended Metal 4 compute encoder remained live";
    get (Command4.Command_buffer.end_recording commands);
    let submission = get (Command4.Queue.commit queue [ commands ]) in
    get (Command4.Submission.wait submission);
    Buffer.read_bytes buffer ~offset:0L ~length:16 |> get |> check_values;
    get (Compute_pipeline.destroy pipeline);
    get (Command4.Argument_table.destroy arguments);
    get (Buffer.destroy buffer);
    get (Command4.Submission.destroy submission);
    get (Command4.Command_buffer.destroy commands);
    get (Command4.Allocator.reset allocator);
    get (Command4.Queue.destroy queue);
    get (Command4.Allocator.destroy allocator);
    get (Library.destroy library);
    get (Compiler.destroy compiler);
    Printf.printf "Metal 4 compute-command conformance passed\n%!";
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
    test_pipeline_assets device;
    ignore (test_metal4_compiler device);
    ignore (test_metal4_render_commands device);
    ignore (test_metal4_compute_commands device);
    test_format_matrix device;
    test_texture_swizzle_and_compression device;
    let residency_sets_supported = test_residency_set device in
    ignore (test_placement_sparse_resources device);
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
    if get (Sampler.label sampler) <> Some "Metal linear sampler"
       || Sampler.descriptor sampler <> sampler_descriptor
    then fail "sampler descriptor did not round-trip";
    let sampler_reduction_supported =
      get (Device.supports_sampler_reduction device)
    in
    if sampler_reduction_supported
       && not (get (Device.supports_family device Device.Apple10))
    then fail "sampler reduction support escaped its Apple10 hardware gate";
    if sampler_reduction_supported then
      List.iter
        (fun (reduction_mode, lod_bias) ->
          let advanced_descriptor =
            { sampler_descriptor with
              reduction_mode
            ; lod_bias
            ; label = Some "Metal reduction sampler"
            }
          in
          let advanced = get (Sampler.create ~device advanced_descriptor) in
          if Sampler.descriptor advanced <> advanced_descriptor
             || get (Sampler.label advanced) <> Some "Metal reduction sampler"
          then fail "Metal 4 sampler descriptor did not round-trip";
          get (Sampler.destroy advanced))
        [ Sampler.Minimum, -16.; Sampler.Maximum, 15.999 ]
    else begin
      let before_unsupported = get (Release_queue.stats ()) in
      ignore
        (expect_error Unsupported
           (Sampler.create ~device
              { sampler_descriptor with
                reduction_mode = Sampler.Minimum
              ; lod_bias = 0.5
              }));
      let after_unsupported = get (Release_queue.stats ()) in
      if after_unsupported.total_created <> before_unsupported.total_created then
        fail "unsupported sampler extensions allocated a native handle"
    end;
    let before_invalid_samplers = get (Release_queue.stats ()) in
    ignore
      (expect_error Invalid_argument
         (Sampler.create ~device { sampler_descriptor with max_anisotropy = 0 }));
    ignore
      (expect_error Invalid_argument
         (Sampler.create ~device { sampler_descriptor with lod_min_clamp = nan }));
    ignore
      (expect_error Invalid_argument
         (Sampler.create ~device { sampler_descriptor with lod_bias = nan }));
    ignore
      (expect_error Invalid_argument
         (Sampler.create ~device { sampler_descriptor with lod_bias = -16.001 }));
    ignore
      (expect_error Invalid_argument
         (Sampler.create ~device { sampler_descriptor with lod_bias = 16. }));
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
    let after_invalid_samplers = get (Release_queue.stats ()) in
    if after_invalid_samplers.total_created <> before_invalid_samplers.total_created
    then fail "invalid sampler inputs allocated native handles";
    get (Sampler.destroy sampler);
    get (Texture.destroy texture);
    let invalid_shader =
      expect_error Native_error
        (Library.compile_source ~device ~label:"invalid shader diagnostic"
           "not a Metal program")
    in
    if invalid_shader.message = ""
       || not
            (contains_substring invalid_shader.message
               "invalid shader diagnostic")
    then fail "shader compilation lost its full labeled diagnostic";
    let library =
      get
        (Library.compile_source ~device ~label:"Metal conformance library"
           shader_source)
    in
    if get (Library.label library) <> Some "Metal conformance library" then
      fail "Metal library label did not round-trip";
    let function_ = get (Function.find ~library "increment") in
    if get (Function.name function_) <> "increment" then
      fail "Metal function name did not round-trip";
    if get (Function.kind function_) <> Function.Kernel
       || get (Function.constants function_) <> []
    then fail "ordinary kernel metadata is wrong";
    let specializable =
      get (Function.find ~library "specialized_increment")
    in
    let constants = get (Function.constants specializable) in
    let expected_constants : Function.constant list =
      [ { name = "increment_amount"
        ; data_type = Shader_type.Scalar Shader_type.Uint
        ; index = 0L
        ; required = true
        }
      ; { name = "apply_twice"
        ; data_type = Shader_type.Scalar Shader_type.Bool
        ; index = 1L
        ; required = true
        }
      ]
    in
    if constants <> expected_constants then
      fail "function-constant metadata did not round-trip";
    let before_invalid_constants = get (Release_queue.stats ()) in
    ignore
      (expect_error Invalid_argument
         (Function.specialize ~library "specialized_increment"
            ~constants:
              [ "increment_amount", Function.Uint32_constant 1L
              ; "increment_amount", Function.Uint32_constant 2L
              ]));
    ignore
      (expect_error Invalid_argument
         (Function.specialize ~library "specialized_increment"
            ~constants:
              [ "increment_amount", Function.Uint32_constant 0x1_0000_0000L
              ]));
    ignore
      (expect_error Invalid_argument
         (Function.specialize ~library ~label:"invalid\000label"
            "specialized_increment" ~constants:[]));
    let after_invalid_constants = get (Release_queue.stats ()) in
    if after_invalid_constants.total_created
       <> before_invalid_constants.total_created
    then fail "invalid function constants allocated native handles";
    let invalid_constant_type =
      expect_error Native_error
        (Function.specialize ~library ~label:"constant type diagnostic"
           "specialized_increment"
           ~constants:[ "increment_amount", Function.Bool_constant true ])
    in
    if not
         (contains_substring invalid_constant_type.message
            "constant type diagnostic")
    then fail "function specialization lost its labeled diagnostic";
    let specialized_function =
      get
        (Function.specialize ~library ~label:"seven twice"
           "specialized_increment"
           ~constants:
             [ "increment_amount", Function.Uint32_constant 7L
             ; "apply_twice", Function.Bool_constant true
             ])
    in
    if get (Function.label specialized_function) <> Some "seven twice"
       || get (Function.kind specialized_function) <> Function.Kernel
    then fail "specialized function metadata did not round-trip";
    let scalar_constant_base =
      get (Function.find ~library "scalar_constant_sum")
    in
    let expected_scalar_types =
      [ "scalar_i8", Shader_type.Char
      ; "scalar_u8", Shader_type.Uchar
      ; "scalar_i16", Shader_type.Short
      ; "scalar_u16", Shader_type.Ushort
      ; "scalar_i32", Shader_type.Int
      ; "scalar_u32", Shader_type.Uint
      ; "scalar_i64", Shader_type.Long
      ; "scalar_u64", Shader_type.Ulong
      ; "scalar_f16", Shader_type.Half
      ; "scalar_f32", Shader_type.Float
      ; "scalar_bool", Shader_type.Bool
      ]
    in
    let scalar_constant_metadata =
      get (Function.constants scalar_constant_base)
    in
    List.iteri
      (fun offset (expected_name, expected_type) ->
        let expected_index = Int64.of_int (offset + 2) in
        match List.nth_opt scalar_constant_metadata offset with
        | Some (constant : Function.constant)
          when constant.name = expected_name
               && constant.data_type = Shader_type.Scalar expected_type
               && constant.index = expected_index && constant.required -> ()
        | _ -> fail "scalar function-constant metadata is wrong at index %Ld"
                 expected_index)
      expected_scalar_types;
    if List.length scalar_constant_metadata <> List.length expected_scalar_types
    then fail "scalar function-constant metadata cardinality is wrong";
    let scalar_constant_function =
      get
        (Function.specialize ~library "scalar_constant_sum"
           ~constants:
             [ "scalar_i8", Function.Int8_constant (-2)
             ; "scalar_u8", Function.Uint8_constant 3
             ; "scalar_i16", Function.Int16_constant (-4)
             ; "scalar_u16", Function.Uint16_constant 5
             ; "scalar_i32", Function.Int32_constant (-6l)
             ; "scalar_u32", Function.Uint32_constant 7L
             ; "scalar_i64", Function.Int64_constant (-8L)
             ; "scalar_u64", Function.Uint64_bits_constant 9L
             ; "scalar_f16", Function.Float16_constant 10.
             ; "scalar_f32", Function.Float32_constant 11.
             ; "scalar_bool", Function.Bool_constant true
             ])
    in
    let linked_function =
      if info.function_pointers then begin
        let linked = get (Function.find ~library "linked_identity") in
        if get (Function.kind linked) <> Function.Visible then
          fail "linked function kind is not visible";
        Some linked
      end
      else None
    in
    ignore
      (expect_error Wrong_domain
         (Domain.spawn (fun () -> Function.constants specializable)
          |> Domain.join));
    let stale_function = get (Function.find ~library "increment") in
    get (Function.destroy stale_function);
    ignore (expect_error Destroyed (Function.constants stale_function));
    ignore
      (expect_error Destroyed (Compute_pipeline.create stale_function));
    let before_invalid_pipeline = get (Release_queue.stats ()) in
    ignore
      (expect_error Invalid_argument
         (Compute_pipeline.create ~label:"invalid\000label"
            specialized_function));
    ignore
      (expect_error Invalid_argument
         (Compute_pipeline.create ~linked_functions:[ function_ ]
            specialized_function));
    Option.iter
      (fun linked ->
        ignore
          (expect_error Invalid_argument
             (Compute_pipeline.create ~linked_functions:[ linked; linked ]
                specialized_function)))
      linked_function;
    let after_invalid_pipeline = get (Release_queue.stats ()) in
    if after_invalid_pipeline.total_created
       <> before_invalid_pipeline.total_created
    then fail "invalid compute descriptors allocated native handles";
    ignore (expect_error Parent_has_dependents (Library.destroy library));
    let pipeline = get (Compute_pipeline.create function_) in
    if Compute_pipeline.thread_execution_width pipeline <= 0
       || Compute_pipeline.max_total_threads_per_threadgroup pipeline <= 0
    then fail "compute pipeline limits are invalid";
    let specialized_pipeline =
      get
        (Compute_pipeline.create ~label:"specialized reflected pipeline"
           ~linked_functions:(Option.to_list linked_function) ~reflection:true
           specialized_function)
    in
    let scalar_constant_pipeline =
      get (Compute_pipeline.create scalar_constant_function)
    in
    if get (Compute_pipeline.label specialized_pipeline)
       <> Some "specialized reflected pipeline"
    then fail "compute pipeline label did not round-trip";
    let reflected_bindings =
      match Compute_pipeline.bindings specialized_pipeline with
      | Some bindings -> bindings
      | None -> fail "requested compute pipeline reflection is missing"
    in
    get
      (Binding.validate_layout reflected_bindings
         ~expected:
           [ { name = "values"
             ; index = 0L
             ; access = Binding.Read_write
             ; kind = Binding.Buffer_layout
             ; data_type = Some (Shader_type.Scalar Shader_type.Uint)
             }
           ]);
    ignore
      (expect_error Invalid_argument
         (Binding.validate_layout reflected_bindings
            ~expected:
              [ { name = "values"
                ; index = 1L
                ; access = Binding.Read_write
                ; kind = Binding.Buffer_layout
                ; data_type = Some (Shader_type.Scalar Shader_type.Uint)
                }
              ]));
    let specialized_buffer =
      get (Buffer.create ~device ~length:4L ~storage:Buffer.Shared ())
    in
    let specialized_input = Bytes.create 4 in
    Bytes.set_int32_le specialized_input 0 10l;
    get (Buffer.write_bytes specialized_buffer ~dst_offset:0L specialized_input);
    let scalar_constant_buffer =
      get (Buffer.create ~device ~length:4L ~storage:Buffer.Shared ())
    in
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
    get (Compute_encoder.set_pipeline encoder specialized_pipeline);
    get (Compute_encoder.set_buffer encoder ~index:0 ~offset:0L specialized_buffer);
    get
      (Compute_encoder.dispatch_threads encoder ~threads:(1, 1, 1)
         ~threadgroup:(1, 1, 1));
    get (Compute_encoder.set_pipeline encoder scalar_constant_pipeline);
    get
      (Compute_encoder.set_buffer encoder ~index:0 ~offset:0L
         scalar_constant_buffer);
    get
      (Compute_encoder.dispatch_threads encoder ~threads:(1, 1, 1)
         ~threadgroup:(1, 1, 1));
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
    let specialized_output =
      get (Buffer.read_bytes specialized_buffer ~offset:0L ~length:4)
    in
    if Bytes.get_int32_le specialized_output 0 <> 24l then
      fail "specialized function constants did not execute on the GPU";
    let scalar_constant_output =
      get (Buffer.read_bytes scalar_constant_buffer ~offset:0L ~length:4)
    in
    if Bytes.get_int32_le scalar_constant_output 0 <> 26l then
      fail "typed scalar function constants did not round-trip to the GPU";
    get (Buffer.destroy scalar_constant_buffer);
    get (Buffer.destroy specialized_buffer);
    get (Buffer.destroy buffer);
    get (Command_buffer.destroy commands);
    get (Command_queue.destroy queue);
    Option.iter
      (fun (_, second) -> get (Residency_set.destroy second))
      queue_residency_sets;
    get (Compute_pipeline.destroy scalar_constant_pipeline);
    get (Compute_pipeline.destroy specialized_pipeline);
    get (Compute_pipeline.destroy pipeline);
    Option.iter (fun value -> get (Function.destroy value)) linked_function;
    get (Function.destroy scalar_constant_function);
    get (Function.destroy scalar_constant_base);
    get (Function.destroy specialized_function);
    get (Function.destroy specializable);
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
      "Metal ARC/device/heap/buffer/texture/sampler/sparse/resource-state/blit/residency/runtime-shader/function-constant/linked/dynamic-library/binary-archive/metal4-compiler/compiler-task/pipeline-dataset/binary-function/static-link/reflection/compute/render/mesh/object/tile/command4-argument-table/compute/render conformance passed on %s\n%!"
      info.name
  end
