let render ~width ~height ~camera scene =
  if width<=0||height<=0 then invalid_arg"Scene3_image.render";
  let resources=Scene3_raster2_resources.create()in
  Fun.protect~finally:(fun()->Scene3_raster2_resources.destroy resources)(fun()->
    let prepared=Scene3_raster2_lowering.prepare
      ~resources:(Scene3_raster2_resources.callbacks resources)
      ~camera ~viewport:(0,0,width,height) scene|>Result.get_ok in
    let color=Raster2.Surface.create~width~height()|>Result.get_ok
    and depth=Raster2.Depth_stencil.create~width~height()|>Result.get_ok in
    let multisample=if prepared.samples=1 then None else
      Some(Raster2.Multisample.create~width~height~samples:prepared.samples()|>Result.get_ok)in
    let target:Raster2.Scene3_consumer.target={color;depth=Some depth;multisample}in
    Raster2.Scene3_consumer.render~target~clear:0x00000000l
      ~clear_depth:prepared.clear_depth~clear_stencil:prepared.clear_stencil
      ~draws:prepared.draws|>Result.get_ok;
    let rgba=Bytes.copy(Raster2.Surface.bytes color)in
    Prismel_next_resources.Image.create~width~height~rgba|>Result.get_ok)
