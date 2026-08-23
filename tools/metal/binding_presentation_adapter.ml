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

let validate_layer layer =
  if layer.size.width <= 0 || layer.size.height <= 0 then
    Error "drawable size must be positive"
  else if layer.maximum_drawables < 2 || layer.maximum_drawables > 3 then
    Error "maximumDrawableCount must be 2 or 3"
  else Ok ()

let validate_attachment attachment =
  if attachment.index < 0 || attachment.index >= 8 then Error "color attachment index"
  else if attachment.level < 0 || attachment.slice < 0 || attachment.depth_plane < 0
       || attachment.resolve_level < 0 || attachment.resolve_slice < 0
       || attachment.resolve_depth_plane < 0
  then Error "negative attachment subresource" else Ok ()

let validate_render_pass pass =
  if pass.width <= 0 || pass.height <= 0 || pass.array_length <= 0 then
    Error "render target extent must be positive"
  else if pass.sample_count <= 0 then Error "sample count must be positive"
  else if pass.tile_width < 0 || pass.tile_height < 0
       || pass.threadgroup_memory_length < 0 then Error "negative tile configuration"
  else
    let rec loop seen = function
      | [] -> Ok ()
      | attachment :: rest ->
          if List.mem attachment.index seen then Error "duplicate color attachment"
          else Result.bind (validate_attachment attachment)
              (fun () -> loop (attachment.index :: seen) rest)
    in loop [] pass.color_attachments

let classify_drawable_loss ~(size : size) ~attached ~timed_out =
  if size.width = 0 || size.height = 0 then Zero_sized
  else if not attached then Detached
  else if timed_out then Timeout
  else Occluded
