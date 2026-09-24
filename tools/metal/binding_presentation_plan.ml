type ownership = Scalar | Copied | Retained | Borrowed | Completion_retained
type lane = Mechanical | Lifecycle
type entry = { owner : string; property : string; ownership : ownership; lane : lane }

let property owner property ownership lane = { owner; property; ownership; lane }

let properties =
  [ property "CAMetalLayer" "device" Retained Lifecycle
  ; property "CAMetalLayer" "colorspace" Retained Lifecycle
  ; property "CAMetalLayer" "drawableSize" Scalar Mechanical
  ; property "CAMetalLayer" "pixelFormat" Scalar Mechanical
  ; property "CAMetalLayer" "maximumDrawableCount" Scalar Mechanical
  ; property "CAMetalLayer" "allowsNextDrawableTimeout" Scalar Lifecycle
  ; property "CAMetalDrawable" "texture" Borrowed Lifecycle
  ; property "MTLRenderPassDescriptor" "colorAttachments" Retained Lifecycle
  ; property "MTLRenderPassDescriptor" "depthAttachment" Copied Lifecycle
  ; property "MTLRenderPassDescriptor" "stencilAttachment" Copied Lifecycle
  ; property "MTLRenderPassDescriptor" "visibilityResultBuffer" Retained Lifecycle
  ; property "MTLCommandBuffer" "presentDrawable:" Completion_retained Lifecycle ]

let lifecycle_requirements =
  [ "validate positive finite drawable sizes before mutating the layer"
  ; "treat nil nextDrawable as recoverable drawable loss"
  ; "keep drawable, texture, and presentation command alive through completion"
  ; "reject layer/device and attachment/device mismatches"
  ; "restore colorspace and pixel format coherently across resize"
  ; "exercise timeout-enabled loss without blocking the initial domain"
  ; "prove bounded ownership over 10000 acquire/render/present frames" ]
