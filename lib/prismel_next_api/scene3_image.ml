let render ~width ~height ~camera scene =
  if width<=0||height<=0 then invalid_arg"Scene3_image.render";
  let samples=Scene3.Private.samples scene in
  let factor=int_of_float(sqrt(float samples))in
  if factor*factor<>samples then invalid_arg"Scene3_image.render: sample count";
  if width>max_int/factor||height>max_int/factor then invalid_arg"Scene3_image.render: extent overflow";
  let render_width=width*factor and render_height=height*factor in
  let resources=Scene3_raster2_resources.create()in
  Fun.protect~finally:(fun()->Scene3_raster2_resources.destroy resources)(fun()->
    let prepared=Scene3_raster2_lowering.prepare
      ~resources:(Scene3_raster2_resources.callbacks resources)
      ~camera ~viewport:(0,0,render_width,render_height) scene|>Result.get_ok in
    let color=Raster2.Surface.create~width:render_width~height:render_height()|>Result.get_ok
    and depth=Raster2.Depth_stencil.create~width:render_width~height:render_height()|>Result.get_ok in
    let target:Raster2.Scene3_consumer.target={color;depth=Some depth;multisample=None}in
    let hdr_compatible=Array.for_all(fun(draw:Raster2.Scene3_consumer.draw)->
      draw.mode=Raster2.Scene3_consumer.Faces&&draw.texture=None&&
      draw.lighting.material.diffuse.a=1.&&
      match draw.blend with Raster2.Composite.Copy|Source_over->true|_->false)
      prepared.draws in
    let source=if hdr_compatible then `Float(Result.get_ok
      (Raster2.Scene3_consumer.render_float~target~clear:0x00000000l
        ~clear_depth:prepared.clear_depth~clear_stencil:prepared.clear_stencil
        ~draws:prepared.draws))else begin
      Raster2.Scene3_consumer.render~target~clear:0x00000000l
        ~clear_depth:prepared.clear_depth~clear_stencil:prepared.clear_stencil
        ~draws:prepared.draws|>Result.get_ok;
      `Bytes(Raster2.Surface.bytes color)
    end in
    let rgba=match source with
    |`Bytes source when factor=1->Bytes.copy source
    |source->
      let output=Bytes.create(width*height*4)in
      for y=0 to height-1 do for x=0 to width-1 do for channel=0 to 3 do
        let total=ref 0. in for sy=0 to factor-1 do for sx=0 to factor-1 do
          let offset=(((y*factor+sy)*render_width+(x*factor+sx))*4)+channel in
          total:=!total+.(match source with `Bytes bytes->float(Char.code(Bytes.get bytes offset))/.255.|`Float values->values.(offset))
        done done;
        let average= !total/.float samples in
        let resolved=int_of_float(max 0.(min 1. average)*.255.+.0.5)in
        Bytes.set output((y*width+x)*4+channel)(Char.chr resolved)
      done done done;output in
    Prismel_next_resources.Image.create~width~height~rgba|>Result.get_ok
    |>Image.Private.of_resource)
