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
    Raster2.Scene3_consumer.render~target~clear:0x00000000l
      ~clear_depth:prepared.clear_depth~clear_stencil:prepared.clear_stencil
      ~draws:prepared.draws|>Result.get_ok;
    let rgba=if factor=1 then Bytes.copy(Raster2.Surface.bytes color)else
      let source=Raster2.Surface.bytes color and output=Bytes.create(width*height*4)and half=samples/2 in
      for y=0 to height-1 do for x=0 to width-1 do for channel=0 to 3 do
        let total=ref 0 in for sy=0 to factor-1 do for sx=0 to factor-1 do
          total:=!total+Char.code(Bytes.get source((((y*factor+sy)*render_width+(x*factor+sx))*4)+channel))
        done done;
        Bytes.set output((y*width+x)*4+channel)(Char.chr((!total+half)/samples))
      done done done;output in
    Prismel_next_resources.Image.create~width~height~rgba|>Result.get_ok
    |>Image.Private.of_resource)
