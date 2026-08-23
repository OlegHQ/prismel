type t =
  | A8_unorm
  | R8_unorm
  | R8_unorm_srgb
  | R8_snorm
  | R8_uint
  | R8_sint
  | R16_unorm
  | R16_snorm
  | R16_uint
  | R16_sint
  | R16_float
  | Rg8_unorm
  | Rg8_unorm_srgb
  | Rg8_snorm
  | Rg8_uint
  | Rg8_sint
  | B5g6r5_unorm
  | A1bgr5_unorm
  | Abgr4_unorm
  | Bgr5a1_unorm
  | R32_uint
  | R32_sint
  | R32_float
  | Rg16_unorm
  | Rg16_snorm
  | Rg16_uint
  | Rg16_sint
  | Rg16_float
  | Rgba8_unorm
  | Rgba8_unorm_srgb
  | Rgba8_snorm
  | Rgba8_uint
  | Rgba8_sint
  | Bgra8_unorm
  | Bgra8_unorm_srgb
  | Rgb10a2_unorm
  | Rgb10a2_uint
  | Rg11b10_float
  | Rgb9e5_float
  | Bgr10a2_unorm
  | Bgr10_xr
  | Bgr10_xr_srgb
  | Rg32_uint
  | Rg32_sint
  | Rg32_float
  | Rgba16_unorm
  | Rgba16_snorm
  | Rgba16_uint
  | Rgba16_sint
  | Rgba16_float
  | Bgra10_xr
  | Bgra10_xr_srgb
  | Rgba32_uint
  | Rgba32_sint
  | Rgba32_float
  | Bc1_rgba
  | Bc1_rgba_srgb
  | Bc2_rgba
  | Bc2_rgba_srgb
  | Bc3_rgba
  | Bc3_rgba_srgb
  | Bc4_r_unorm
  | Bc4_r_snorm
  | Bc5_rg_unorm
  | Bc5_rg_snorm
  | Bc6h_rgb_float
  | Bc6h_rgb_ufloat
  | Bc7_rgba_unorm
  | Bc7_rgba_unorm_srgb
  | Eac_r11_unorm
  | Eac_r11_snorm
  | Eac_rg11_unorm
  | Eac_rg11_snorm
  | Eac_rgba8
  | Eac_rgba8_srgb
  | Etc2_rgb8
  | Etc2_rgb8_srgb
  | Etc2_rgb8a1
  | Etc2_rgb8a1_srgb
  | Astc_4x4_srgb
  | Astc_5x4_srgb
  | Astc_5x5_srgb
  | Astc_6x5_srgb
  | Astc_6x6_srgb
  | Astc_8x5_srgb
  | Astc_8x6_srgb
  | Astc_8x8_srgb
  | Astc_10x5_srgb
  | Astc_10x6_srgb
  | Astc_10x8_srgb
  | Astc_10x10_srgb
  | Astc_12x10_srgb
  | Astc_12x12_srgb
  | Astc_4x4_ldr
  | Astc_5x4_ldr
  | Astc_5x5_ldr
  | Astc_6x5_ldr
  | Astc_6x6_ldr
  | Astc_8x5_ldr
  | Astc_8x6_ldr
  | Astc_8x8_ldr
  | Astc_10x5_ldr
  | Astc_10x6_ldr
  | Astc_10x8_ldr
  | Astc_10x10_ldr
  | Astc_12x10_ldr
  | Astc_12x12_ldr
  | Astc_4x4_hdr
  | Astc_5x4_hdr
  | Astc_5x5_hdr
  | Astc_6x5_hdr
  | Astc_6x6_hdr
  | Astc_8x5_hdr
  | Astc_8x6_hdr
  | Astc_8x8_hdr
  | Astc_10x5_hdr
  | Astc_10x6_hdr
  | Astc_10x8_hdr
  | Astc_10x10_hdr
  | Astc_12x10_hdr
  | Astc_12x12_hdr
  | Gbgr422
  | Bgrg422
  | Depth16_unorm
  | Depth32_float
  | Stencil8
  | Depth24_unorm_stencil8
  | Depth32_float_stencil8
  | X32_stencil8
  | X24_stencil8

type layout =
  { block_width : int
  ; block_height : int
  ; bytes_per_block : int
  }

let code = function
  | A8_unorm -> 1
  | R8_unorm -> 10
  | R8_unorm_srgb -> 11
  | R8_snorm -> 12
  | R8_uint -> 13
  | R8_sint -> 14
  | R16_unorm -> 20
  | R16_snorm -> 22
  | R16_uint -> 23
  | R16_sint -> 24
  | R16_float -> 25
  | Rg8_unorm -> 30
  | Rg8_unorm_srgb -> 31
  | Rg8_snorm -> 32
  | Rg8_uint -> 33
  | Rg8_sint -> 34
  | B5g6r5_unorm -> 40
  | A1bgr5_unorm -> 41
  | Abgr4_unorm -> 42
  | Bgr5a1_unorm -> 43
  | R32_uint -> 53
  | R32_sint -> 54
  | R32_float -> 55
  | Rg16_unorm -> 60
  | Rg16_snorm -> 62
  | Rg16_uint -> 63
  | Rg16_sint -> 64
  | Rg16_float -> 65
  | Rgba8_unorm -> 70
  | Rgba8_unorm_srgb -> 71
  | Rgba8_snorm -> 72
  | Rgba8_uint -> 73
  | Rgba8_sint -> 74
  | Bgra8_unorm -> 80
  | Bgra8_unorm_srgb -> 81
  | Rgb10a2_unorm -> 90
  | Rgb10a2_uint -> 91
  | Rg11b10_float -> 92
  | Rgb9e5_float -> 93
  | Bgr10a2_unorm -> 94
  | Bgra10_xr -> 552
  | Bgra10_xr_srgb -> 553
  | Bgr10_xr -> 554
  | Bgr10_xr_srgb -> 555
  | Rg32_uint -> 103
  | Rg32_sint -> 104
  | Rg32_float -> 105
  | Rgba16_unorm -> 110
  | Rgba16_snorm -> 112
  | Rgba16_uint -> 113
  | Rgba16_sint -> 114
  | Rgba16_float -> 115
  | Rgba32_uint -> 123
  | Rgba32_sint -> 124
  | Rgba32_float -> 125
  | Bc1_rgba -> 130
  | Bc1_rgba_srgb -> 131
  | Bc2_rgba -> 132
  | Bc2_rgba_srgb -> 133
  | Bc3_rgba -> 134
  | Bc3_rgba_srgb -> 135
  | Bc4_r_unorm -> 140
  | Bc4_r_snorm -> 141
  | Bc5_rg_unorm -> 142
  | Bc5_rg_snorm -> 143
  | Bc6h_rgb_float -> 150
  | Bc6h_rgb_ufloat -> 151
  | Bc7_rgba_unorm -> 152
  | Bc7_rgba_unorm_srgb -> 153
  | Eac_r11_unorm -> 170
  | Eac_r11_snorm -> 172
  | Eac_rg11_unorm -> 174
  | Eac_rg11_snorm -> 176
  | Eac_rgba8 -> 178
  | Eac_rgba8_srgb -> 179
  | Etc2_rgb8 -> 180
  | Etc2_rgb8_srgb -> 181
  | Etc2_rgb8a1 -> 182
  | Etc2_rgb8a1_srgb -> 183
  | Astc_4x4_srgb -> 186
  | Astc_5x4_srgb -> 187
  | Astc_5x5_srgb -> 188
  | Astc_6x5_srgb -> 189
  | Astc_6x6_srgb -> 190
  | Astc_8x5_srgb -> 192
  | Astc_8x6_srgb -> 193
  | Astc_8x8_srgb -> 194
  | Astc_10x5_srgb -> 195
  | Astc_10x6_srgb -> 196
  | Astc_10x8_srgb -> 197
  | Astc_10x10_srgb -> 198
  | Astc_12x10_srgb -> 199
  | Astc_12x12_srgb -> 200
  | Astc_4x4_ldr -> 204
  | Astc_5x4_ldr -> 205
  | Astc_5x5_ldr -> 206
  | Astc_6x5_ldr -> 207
  | Astc_6x6_ldr -> 208
  | Astc_8x5_ldr -> 210
  | Astc_8x6_ldr -> 211
  | Astc_8x8_ldr -> 212
  | Astc_10x5_ldr -> 213
  | Astc_10x6_ldr -> 214
  | Astc_10x8_ldr -> 215
  | Astc_10x10_ldr -> 216
  | Astc_12x10_ldr -> 217
  | Astc_12x12_ldr -> 218
  | Astc_4x4_hdr -> 222
  | Astc_5x4_hdr -> 223
  | Astc_5x5_hdr -> 224
  | Astc_6x5_hdr -> 225
  | Astc_6x6_hdr -> 226
  | Astc_8x5_hdr -> 228
  | Astc_8x6_hdr -> 229
  | Astc_8x8_hdr -> 230
  | Astc_10x5_hdr -> 231
  | Astc_10x6_hdr -> 232
  | Astc_10x8_hdr -> 233
  | Astc_10x10_hdr -> 234
  | Astc_12x10_hdr -> 235
  | Astc_12x12_hdr -> 236
  | Gbgr422 -> 240
  | Bgrg422 -> 241
  | Depth16_unorm -> 250
  | Depth32_float -> 252
  | Stencil8 -> 253
  | Depth24_unorm_stencil8 -> 255
  | Depth32_float_stencil8 -> 260
  | X32_stencil8 -> 261
  | X24_stencil8 -> 262

let block block_width block_height bytes_per_block =
  { block_width; block_height; bytes_per_block }

let layout = function
  | A8_unorm | R8_unorm | R8_unorm_srgb | R8_snorm | R8_uint | R8_sint
  | Stencil8 ->
      { block_width = 1; block_height = 1; bytes_per_block = 1 }
  | R16_unorm | R16_snorm | R16_uint | R16_sint | R16_float | Rg8_unorm
  | Rg8_unorm_srgb | Rg8_snorm | Rg8_uint | Rg8_sint | B5g6r5_unorm
  | A1bgr5_unorm | Abgr4_unorm | Bgr5a1_unorm | Depth16_unorm ->
      { block_width = 1; block_height = 1; bytes_per_block = 2 }
  | R32_uint | R32_sint | R32_float | Rg16_unorm | Rg16_snorm | Rg16_uint
  | Rg16_sint | Rg16_float | Rgba8_unorm | Rgba8_unorm_srgb | Rgba8_snorm
  | Rgba8_uint | Rgba8_sint | Bgra8_unorm | Bgra8_unorm_srgb
  | Rgb10a2_unorm | Rgb10a2_uint | Rg11b10_float | Rgb9e5_float
  | Bgr10a2_unorm | Bgr10_xr | Bgr10_xr_srgb | Bgra10_xr
  | Bgra10_xr_srgb | Depth32_float | Depth24_unorm_stencil8 | X24_stencil8 ->
      { block_width = 1; block_height = 1; bytes_per_block = 4 }
  | Rg32_uint | Rg32_sint | Rg32_float | Rgba16_unorm | Rgba16_snorm
  | Rgba16_uint | Rgba16_sint | Rgba16_float | Depth32_float_stencil8
  | X32_stencil8 ->
      { block_width = 1; block_height = 1; bytes_per_block = 8 }
  | Rgba32_uint | Rgba32_sint | Rgba32_float ->
      { block_width = 1; block_height = 1; bytes_per_block = 16 }
  | Bc1_rgba | Bc1_rgba_srgb | Bc4_r_unorm | Bc4_r_snorm
  | Eac_r11_unorm | Eac_r11_snorm | Etc2_rgb8 | Etc2_rgb8_srgb
  | Etc2_rgb8a1 | Etc2_rgb8a1_srgb -> block 4 4 8
  | Bc2_rgba | Bc2_rgba_srgb | Bc3_rgba | Bc3_rgba_srgb
  | Bc5_rg_unorm | Bc5_rg_snorm | Bc6h_rgb_float | Bc6h_rgb_ufloat
  | Bc7_rgba_unorm | Bc7_rgba_unorm_srgb | Eac_rg11_unorm
  | Eac_rg11_snorm | Eac_rgba8 | Eac_rgba8_srgb -> block 4 4 16
  | Astc_4x4_srgb | Astc_4x4_ldr | Astc_4x4_hdr -> block 4 4 16
  | Astc_5x4_srgb | Astc_5x4_ldr | Astc_5x4_hdr -> block 5 4 16
  | Astc_5x5_srgb | Astc_5x5_ldr | Astc_5x5_hdr -> block 5 5 16
  | Astc_6x5_srgb | Astc_6x5_ldr | Astc_6x5_hdr -> block 6 5 16
  | Astc_6x6_srgb | Astc_6x6_ldr | Astc_6x6_hdr -> block 6 6 16
  | Astc_8x5_srgb | Astc_8x5_ldr | Astc_8x5_hdr -> block 8 5 16
  | Astc_8x6_srgb | Astc_8x6_ldr | Astc_8x6_hdr -> block 8 6 16
  | Astc_8x8_srgb | Astc_8x8_ldr | Astc_8x8_hdr -> block 8 8 16
  | Astc_10x5_srgb | Astc_10x5_ldr | Astc_10x5_hdr -> block 10 5 16
  | Astc_10x6_srgb | Astc_10x6_ldr | Astc_10x6_hdr -> block 10 6 16
  | Astc_10x8_srgb | Astc_10x8_ldr | Astc_10x8_hdr -> block 10 8 16
  | Astc_10x10_srgb | Astc_10x10_ldr | Astc_10x10_hdr -> block 10 10 16
  | Astc_12x10_srgb | Astc_12x10_ldr | Astc_12x10_hdr -> block 12 10 16
  | Astc_12x12_srgb | Astc_12x12_ldr | Astc_12x12_hdr -> block 12 12 16
  | Gbgr422 | Bgrg422 ->
      { block_width = 2; block_height = 1; bytes_per_block = 4 }

let is_depth_or_stencil = function
  | Depth16_unorm | Depth32_float | Stencil8 | Depth24_unorm_stencil8
  | Depth32_float_stencil8 | X32_stencil8 | X24_stencil8 -> true
  | _ -> false

let is_view_only = function X32_stencil8 | X24_stencil8 -> true | _ -> false
let is_subsampled = function Gbgr422 | Bgrg422 -> true | _ -> false

type compression_family =
  | Bc
  | Eac_etc2
  | Astc_ldr
  | Astc_hdr

let compression_family = function
  | Bc1_rgba | Bc1_rgba_srgb | Bc2_rgba | Bc2_rgba_srgb | Bc3_rgba
  | Bc3_rgba_srgb | Bc4_r_unorm | Bc4_r_snorm | Bc5_rg_unorm
  | Bc5_rg_snorm | Bc6h_rgb_float | Bc6h_rgb_ufloat | Bc7_rgba_unorm
  | Bc7_rgba_unorm_srgb -> Some Bc
  | Eac_r11_unorm | Eac_r11_snorm | Eac_rg11_unorm | Eac_rg11_snorm
  | Eac_rgba8 | Eac_rgba8_srgb | Etc2_rgb8 | Etc2_rgb8_srgb
  | Etc2_rgb8a1 | Etc2_rgb8a1_srgb -> Some Eac_etc2
  | Astc_4x4_srgb | Astc_5x4_srgb | Astc_5x5_srgb | Astc_6x5_srgb
  | Astc_6x6_srgb | Astc_8x5_srgb | Astc_8x6_srgb | Astc_8x8_srgb
  | Astc_10x5_srgb | Astc_10x6_srgb | Astc_10x8_srgb | Astc_10x10_srgb
  | Astc_12x10_srgb | Astc_12x12_srgb | Astc_4x4_ldr | Astc_5x4_ldr
  | Astc_5x5_ldr | Astc_6x5_ldr | Astc_6x6_ldr | Astc_8x5_ldr
  | Astc_8x6_ldr | Astc_8x8_ldr | Astc_10x5_ldr | Astc_10x6_ldr
  | Astc_10x8_ldr | Astc_10x10_ldr | Astc_12x10_ldr | Astc_12x12_ldr ->
      Some Astc_ldr
  | Astc_4x4_hdr | Astc_5x4_hdr | Astc_5x5_hdr | Astc_6x5_hdr
  | Astc_6x6_hdr | Astc_8x5_hdr | Astc_8x6_hdr | Astc_8x8_hdr
  | Astc_10x5_hdr | Astc_10x6_hdr | Astc_10x8_hdr | Astc_10x10_hdr
  | Astc_12x10_hdr | Astc_12x12_hdr -> Some Astc_hdr
  | _ -> None

let is_compressed format = Option.is_some (compression_family format)

let supports_buffer_backing format =
  not
    (is_depth_or_stencil format || is_subsampled format
     || is_compressed format)

let view_class = function
  | R8_unorm | R8_unorm_srgb -> Some 1
  | Rg8_unorm | Rg8_unorm_srgb -> Some 2
  | Rgba8_unorm | Rgba8_unorm_srgb -> Some 3
  | Bgra8_unorm | Bgra8_unorm_srgb -> Some 4
  | Bgr10_xr | Bgr10_xr_srgb -> Some 5
  | Bgra10_xr | Bgra10_xr_srgb -> Some 6
  | Bc1_rgba | Bc1_rgba_srgb -> Some 7
  | Bc2_rgba | Bc2_rgba_srgb -> Some 8
  | Bc3_rgba | Bc3_rgba_srgb -> Some 9
  | Bc7_rgba_unorm | Bc7_rgba_unorm_srgb -> Some 10
  | Eac_rgba8 | Eac_rgba8_srgb -> Some 11
  | Etc2_rgb8 | Etc2_rgb8_srgb -> Some 12
  | Etc2_rgb8a1 | Etc2_rgb8a1_srgb -> Some 13
  | Astc_4x4_srgb | Astc_4x4_ldr -> Some 14
  | Astc_5x4_srgb | Astc_5x4_ldr -> Some 15
  | Astc_5x5_srgb | Astc_5x5_ldr -> Some 16
  | Astc_6x5_srgb | Astc_6x5_ldr -> Some 17
  | Astc_6x6_srgb | Astc_6x6_ldr -> Some 18
  | Astc_8x5_srgb | Astc_8x5_ldr -> Some 19
  | Astc_8x6_srgb | Astc_8x6_ldr -> Some 20
  | Astc_8x8_srgb | Astc_8x8_ldr -> Some 21
  | Astc_10x5_srgb | Astc_10x5_ldr -> Some 22
  | Astc_10x6_srgb | Astc_10x6_ldr -> Some 23
  | Astc_10x8_srgb | Astc_10x8_ldr -> Some 24
  | Astc_10x10_srgb | Astc_10x10_ldr -> Some 25
  | Astc_12x10_srgb | Astc_12x10_ldr -> Some 26
  | Astc_12x12_srgb | Astc_12x12_ldr -> Some 27
  | _ -> None

let compatible_view source target =
  source = target
  ||
  match view_class source, view_class target with
  | Some source_class, Some target_class -> source_class = target_class
  | _ ->
      (match source, target with
       | Depth32_float_stencil8, X32_stencil8
       | X32_stencil8, Depth32_float_stencil8
       | Depth24_unorm_stencil8, X24_stencil8
       | X24_stencil8, Depth24_unorm_stencil8 -> true
       | _ -> false)

let all =
  [ A8_unorm; R8_unorm; R8_unorm_srgb; R8_snorm; R8_uint; R8_sint
  ; R16_unorm; R16_snorm; R16_uint; R16_sint; R16_float; Rg8_unorm
  ; Rg8_unorm_srgb; Rg8_snorm; Rg8_uint; Rg8_sint; B5g6r5_unorm
  ; A1bgr5_unorm; Abgr4_unorm; Bgr5a1_unorm; R32_uint; R32_sint
  ; R32_float; Rg16_unorm; Rg16_snorm; Rg16_uint; Rg16_sint
  ; Rg16_float; Rgba8_unorm; Rgba8_unorm_srgb; Rgba8_snorm; Rgba8_uint
  ; Rgba8_sint; Bgra8_unorm; Bgra8_unorm_srgb; Rgb10a2_unorm
  ; Rgb10a2_uint; Rg11b10_float; Rgb9e5_float; Bgr10a2_unorm; Bgr10_xr
  ; Bgr10_xr_srgb; Rg32_uint; Rg32_sint; Rg32_float; Rgba16_unorm
  ; Rgba16_snorm; Rgba16_uint; Rgba16_sint; Rgba16_float; Bgra10_xr
  ; Bgra10_xr_srgb; Rgba32_uint; Rgba32_sint; Rgba32_float
  ; Bc1_rgba; Bc1_rgba_srgb; Bc2_rgba; Bc2_rgba_srgb; Bc3_rgba
  ; Bc3_rgba_srgb; Bc4_r_unorm; Bc4_r_snorm; Bc5_rg_unorm; Bc5_rg_snorm
  ; Bc6h_rgb_float; Bc6h_rgb_ufloat; Bc7_rgba_unorm
  ; Bc7_rgba_unorm_srgb; Eac_r11_unorm; Eac_r11_snorm; Eac_rg11_unorm
  ; Eac_rg11_snorm; Eac_rgba8; Eac_rgba8_srgb; Etc2_rgb8
  ; Etc2_rgb8_srgb; Etc2_rgb8a1; Etc2_rgb8a1_srgb; Astc_4x4_srgb
  ; Astc_5x4_srgb; Astc_5x5_srgb; Astc_6x5_srgb; Astc_6x6_srgb
  ; Astc_8x5_srgb; Astc_8x6_srgb; Astc_8x8_srgb; Astc_10x5_srgb
  ; Astc_10x6_srgb; Astc_10x8_srgb; Astc_10x10_srgb; Astc_12x10_srgb
  ; Astc_12x12_srgb; Astc_4x4_ldr; Astc_5x4_ldr; Astc_5x5_ldr
  ; Astc_6x5_ldr; Astc_6x6_ldr; Astc_8x5_ldr; Astc_8x6_ldr; Astc_8x8_ldr
  ; Astc_10x5_ldr; Astc_10x6_ldr; Astc_10x8_ldr; Astc_10x10_ldr
  ; Astc_12x10_ldr; Astc_12x12_ldr; Astc_4x4_hdr; Astc_5x4_hdr
  ; Astc_5x5_hdr; Astc_6x5_hdr; Astc_6x6_hdr; Astc_8x5_hdr
  ; Astc_8x6_hdr; Astc_8x8_hdr; Astc_10x5_hdr; Astc_10x6_hdr
  ; Astc_10x8_hdr; Astc_10x10_hdr; Astc_12x10_hdr; Astc_12x12_hdr
  ; Gbgr422; Bgrg422; Depth16_unorm; Depth32_float; Stencil8
  ; Depth24_unorm_stencil8; Depth32_float_stencil8; X32_stencil8
  ; X24_stencil8
  ]

let of_code requested =
  List.find_opt (fun format -> code format = requested) all
