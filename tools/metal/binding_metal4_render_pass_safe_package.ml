type sample_position = { x : float; y : float }
type rate_map = { token : int; device : int; screen_width : int; screen_height : int; destroyed : bool }
type attachment_kind = Depth | Stencil
type attachment = { token : int; device : int; kind : attachment_kind; sample_count : int; destroyed : bool }
type t =
  { device : int; width : int; height : int; sample_count : int; max_sample_positions : int
  ; mutable positions : sample_position array; mutable rate_map : rate_map option
  ; mutable depth : attachment option; mutable stencil : attachment option }

let callable_ids =
  [ "method:-[MTL4RenderPassDescriptor getSamplePositions:count:]"
  ; "method:-[MTL4RenderPassDescriptor rasterizationRateMap]"
  ; "method:-[MTL4RenderPassDescriptor setDepthAttachment:]"
  ; "method:-[MTL4RenderPassDescriptor setRasterizationRateMap:]"
  ; "method:-[MTL4RenderPassDescriptor setSamplePositions:count:]"
  ; "method:-[MTL4RenderPassDescriptor setStencilAttachment:]"
  ; "property:MTL4RenderPassDescriptor:rasterizationRateMap" ]

let create ~available ~device ~width ~height ~sample_count ~max_sample_positions =
  if not available then Error "MTL4 render passes require macOS 26"
  else if width <= 0 || height <= 0 || sample_count <= 0 || max_sample_positions < sample_count then
    Error "invalid MTL4 render-pass dimensions/sample capability"
  else Ok { device; width; height; sample_count; max_sample_positions; positions = [||]
          ; rate_map = None; depth = None; stencil = None }

let finite_unit value = Float.is_finite value && value >= 0. && value <= 1.

let set_sample_positions descriptor positions =
  if Array.length positions <> 0 && Array.length positions <> descriptor.sample_count then
    Error "sample-position count must be zero or match pass sample count"
  else if Array.length positions > descriptor.max_sample_positions then Error "sample-position capability exceeded"
  else if Array.exists (fun position -> not (finite_unit position.x && finite_unit position.y)) positions then
    Error "sample position is outside the unit square"
  else begin descriptor.positions <- Array.copy positions; Ok () end

let sample_positions descriptor = Array.copy descriptor.positions

let set_rate_map descriptor (rate_map : rate_map option) =
  match rate_map with
  | Some map when map.destroyed -> Error "destroyed rasterization rate map"
  | Some map when map.device <> descriptor.device -> Error "rasterization rate map belongs to another device"
  | Some map when map.screen_width <> descriptor.width || map.screen_height <> descriptor.height ->
      Error "rasterization rate map screen size mismatch"
  | value -> descriptor.rate_map <- value; Ok ()

let rate_map descriptor = descriptor.rate_map

let set_attachment descriptor expected (value : attachment option) assign =
  match value with
  | Some attachment when attachment.destroyed -> Error "destroyed render-pass attachment"
  | Some attachment when attachment.device <> descriptor.device -> Error "render-pass attachment belongs to another device"
  | Some attachment when attachment.kind <> expected -> Error "render-pass attachment kind mismatch"
  | Some attachment when attachment.sample_count <> descriptor.sample_count -> Error "render-pass attachment sample mismatch"
  | value -> assign value; Ok ()

let set_depth_attachment descriptor value =
  set_attachment descriptor Depth value (fun value -> descriptor.depth <- value)
let set_stencil_attachment descriptor value =
  set_attachment descriptor Stencil value (fun value -> descriptor.stencil <- value)

let retained_tokens descriptor =
  let tokens = match descriptor.rate_map with None -> [] | Some map -> [ map.token ] in
  let tokens = match descriptor.depth with None -> tokens | Some attachment -> attachment.token :: tokens in
  match descriptor.stencil with None -> tokens | Some attachment -> attachment.token :: tokens

let reset descriptor =
  descriptor.positions <- [||]; descriptor.rate_map <- None; descriptor.depth <- None; descriptor.stencil <- None

let validate_handoff () =
  if List.length callable_ids <> 7 || List.length (List.sort_uniq String.compare callable_ids) <> 7 then
    invalid_arg "MTL4RenderPass callable7 drift"
