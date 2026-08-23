type drawable = Drawable of nativeint
type layer = Layer of nativeint
type command_buffer = Command_buffer of nativeint
type texture = Texture of nativeint
type render_pass = Render_pass of nativeint
let _constructor_evidence =
  ( Drawable Nativeint.zero, Layer Nativeint.zero
  , Command_buffer Nativeint.zero, Texture Nativeint.zero
  , Render_pass Nativeint.zero )
type loss = Timeout | Occluded | Zero_sized | Detached
type acquisition = Drawable_available of drawable * texture | Drawable_unavailable of loss
type present_time = Immediate | At_time of float | After_minimum_duration of float
type window_state =
  { attached : bool; visible : bool; minimized : bool
  ; pixel_width : int; pixel_height : int }

let classify_nil state ~timed_out =
  if not state.attached then Detached
  else if state.pixel_width = 0 || state.pixel_height = 0 then Zero_sized
  else if state.minimized || not state.visible then Occluded
  else if timed_out then Timeout else Occluded

let finite value =
  match classify_float value with FP_normal | FP_subnormal | FP_zero -> true
  | FP_infinite | FP_nan -> false

let validate_present_time = function
  | Immediate -> Ok ()
  | At_time value when finite value && value >= 0. -> Ok ()
  | After_minimum_duration value when finite value && value >= 0. -> Ok ()
  | At_time _ -> Error "presentation time must be finite and non-negative"
  | After_minimum_duration _ ->
      Error "minimum presentation duration must be finite and non-negative"

let selector_contract =
  [ "[layer nextDrawable] -> nullable retained completion owner"
  ; "[drawable texture] -> borrowed from drawable"
  ; "[drawable layer] -> borrowed from drawable"
  ; "[commandBuffer presentDrawable:drawable] -> completion retained"
  ; "[commandBuffer presentDrawable:drawable atTime:t] -> completion retained"
  ; "[commandBuffer presentDrawable:drawable afterMinimumDuration:d] -> completion retained"
  ; "[commandBuffer renderCommandEncoderWithDescriptor:pass] -> child encoder"
  ; "[MTLRenderPassDescriptor renderPassDescriptor] -> owned descriptor graph" ]

let sdl3_attached_window_strategy =
  [ "create one hidden SDL3 Metal-capable window on the initial domain"
  ; "obtain and retain its CAMetalLayer through SDL_Metal_GetLayer"
  ; "drive drawableSize only from SDL_GetWindowSizeInPixels resize events"
  ; "acquire and present three warm-up drawables before the loss matrix"
  ; "minimize/hide window, drain in-flight completions, then accept nil as Occluded"
  ; "set drawableSize to zero and accept nil as Zero_sized without blocking"
  ; "detach layer from the native view and accept nil as Detached"
  ; "with allowsNextDrawableTimeout=true exhaust in-flight pool and accept nil as Timeout"
  ; "restore attachment/size/visibility, reacquire, render, and present successfully"
  ; "repeat loss/recovery with BGRA8, BGRA8_sRGB, P3, and extended-linear colorspaces"
  ; "run on the initial domain and destroy the window only after completion drain" ]
