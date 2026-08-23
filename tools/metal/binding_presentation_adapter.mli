type size = { width : int; height : int }
type pixel_format = Bgra8_unorm | Bgra8_unorm_srgb | Rgba16_float
type colorspace = Srgb | Display_p3 | Extended_linear_srgb
type drawable_loss = Timeout | Occluded | Zero_sized | Detached

type layer =
  { size : size; pixel_format : pixel_format; colorspace : colorspace option
  ; framebuffer_only : bool; maximum_drawables : int
  ; allows_timeout : bool; display_sync : bool; presents_with_transaction : bool }

type attachment =
  { index : int; level : int; slice : int; depth_plane : int
  ; resolve_level : int; resolve_slice : int; resolve_depth_plane : int }

type render_pass =
  { width : int; height : int; array_length : int; sample_count : int
  ; tile_width : int; tile_height : int; threadgroup_memory_length : int
  ; color_attachments : attachment list }

val validate_layer : layer -> (unit, string) result
val validate_render_pass : render_pass -> (unit, string) result
val classify_drawable_loss : size:size -> attached:bool -> timed_out:bool -> drawable_loss
