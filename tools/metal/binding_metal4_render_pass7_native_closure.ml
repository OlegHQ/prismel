let ids =
  [ "method:-[MTL4RenderPassDescriptor getSamplePositions:count:]"
  ; "method:-[MTL4RenderPassDescriptor rasterizationRateMap]"
  ; "method:-[MTL4RenderPassDescriptor setDepthAttachment:]"
  ; "method:-[MTL4RenderPassDescriptor setRasterizationRateMap:]"
  ; "method:-[MTL4RenderPassDescriptor setSamplePositions:count:]"
  ; "method:-[MTL4RenderPassDescriptor setStencilAttachment:]"
  ; "property:MTL4RenderPassDescriptor:rasterizationRateMap" ]

let existing_sample_symbol = "caml_prismel_metal4_render_pass_sample_positions"

let () =
  if List.length ids <> 7 || List.length (List.sort_uniq String.compare ids) <> 7
     || existing_sample_symbol = ""
  then invalid_arg "MTL4RenderPass7 native closure drift"
