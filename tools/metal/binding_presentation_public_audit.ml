let selector_reachable =
  [ "method:-[CAMetalLayer setDevice:]"
  ; "method:-[CAMetalLayer setDrawableSize:]"
  ; "method:-[CAMetalLayer setPixelFormat:]"
  ; "method:-[CAMetalLayer setFramebufferOnly:]"
  ; "method:-[CAMetalLayer setMaximumDrawableCount:]"
  ; "method:-[CAMetalLayer setAllowsNextDrawableTimeout:]"
  ; "method:-[CAMetalLayer setDisplaySyncEnabled:]"
  ; "method:-[CAMetalLayer setPresentsWithTransaction:]"
  ; "method:-[CAMetalLayer nextDrawable]"
  ; "method:-[CAMetalDrawable texture]"
  ; "method:-[MTLCommandBuffer presentDrawable:]"
  ; "method:-[MTLCommandBuffer presentDrawable:atTime:]"
  ; "method:-[MTLCommandBuffer presentDrawable:afterMinimumDuration:]"
  ; "method:-[MTLCommandBuffer addScheduledHandler:]"
  ; "method:-[MTLCommandBuffer addCompletedHandler:]"
  ; "method:-[MTLCommandBuffer renderCommandEncoderWithDescriptor:]"
  ; "method:+[MTLRenderPassDescriptor renderPassDescriptor]"
  ; "method:-[MTLRenderPassDescriptor setRenderTargetWidth:]"
  ; "method:-[MTLRenderPassDescriptor setRenderTargetHeight:]"
  ; "method:-[MTLRenderPassDescriptor setRenderTargetArrayLength:]"
  ; "method:-[MTLRenderPassDescriptor setDefaultRasterSampleCount:]" ]

let property_companions =
  [ "property:CAMetalLayer:device"; "property:CAMetalLayer:drawableSize"
  ; "property:CAMetalLayer:pixelFormat"; "property:CAMetalLayer:framebufferOnly"
  ; "property:CAMetalLayer:maximumDrawableCount"
  ; "property:CAMetalLayer:allowsNextDrawableTimeout"
  ; "property:CAMetalLayer:displaySyncEnabled"
  ; "property:CAMetalLayer:presentsWithTransaction"
  ; "property:CAMetalDrawable:texture"
  ; "property:MTLRenderPassDescriptor:renderTargetWidth"
  ; "property:MTLRenderPassDescriptor:renderTargetHeight"
  ; "property:MTLRenderPassDescriptor:renderTargetArrayLength"
  ; "property:MTLRenderPassDescriptor:defaultRasterSampleCount" ]

let safe_reachable = List.sort_uniq String.compare (selector_reachable @ property_companions)
let missing_public =
  Binding_presentation_manifest.ids
  |> List.filter (fun id -> not (List.mem id safe_reachable))
  |> List.sort String.compare
