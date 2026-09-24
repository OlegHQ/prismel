type implementation = Generated_typed_selector | Handwritten_lifecycle
type item = { id : string; implementation : implementation; evidence : string }

let contains text needle =
  let text_length = String.length text and needle_length = String.length needle in
  let rec loop index =
    index + needle_length <= text_length
    && (String.sub text index needle_length = needle || loop (index + 1))
  in loop 0

let lifecycle id =
  List.exists (contains id)
    [ "nextDrawable"; "presentDrawable:"; "addCompletedHandler:"
    ; "addScheduledHandler:"; "renderCommandEncoderWithDescriptor:"
    ; "colorAttachments"; "depthAttachment"; "stencilAttachment"
    ; "visibilityResultBuffer"; "rasterizationRateMap"; "texture"; "layer" ]

let items =
  List.map
    (fun id ->
      if lifecycle id then
        { id; implementation=Handwritten_lifecycle;
          evidence="safe ownership, device validation, and completion retention" }
      else
        { id; implementation=Generated_typed_selector;
          evidence="direct statically typed getter/setter or scalar command selector" })
    Binding_presentation_manifest.ids

let count implementation =
  List.fold_left
    (fun total item -> if item.implementation = implementation then total + 1 else total)
    0 items

let generated_count = count Generated_typed_selector
let handwritten_count = count Handwritten_lifecycle
