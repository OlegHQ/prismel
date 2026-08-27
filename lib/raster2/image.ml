type filter=Nearest|Bilinear type rect={x:int;y:int;width:int;height:int} type error=Invalid_extent|Invalid_pitch|Storage_too_small
let ch c n=Int32.(to_int(logand(shift_right_logical c n)0xffl))
let color r g b a=Int32.(logor(shift_left(of_int r)24)(logor(shift_left(of_int g)16)(logor(shift_left(of_int b)8)(of_int a))))
let alpha_mask_blend ~blend ~dst ~dst_x ~dst_y ~width ~height ~pitch bytes ~color:c=if width<0||height<0 then Error Invalid_extent else if pitch<width then Error Invalid_pitch else if height<>0&&(pitch>max_int/height||Bytes.length bytes<pitch*height)then Error Storage_too_small else(let a=ch c 0 in for y=0 to height-1 do let py=dst_y+y in if py>=0&&py<Surface.height dst then for x=0 to width-1 do let px=dst_x+x in if px>=0&&px<Surface.width dst then let coverage=Char.code(Bytes.unsafe_get bytes(y*pitch+x))in Composite.pixel dst~blend~x:px~y:py(color(ch c 24)(ch c 16)(ch c 8)((a*coverage+127)/255))done done;Ok())
let alpha_mask ~dst ~dst_x ~dst_y ~width ~height ~pitch bytes ~color=alpha_mask_blend~blend:Composite.Source_over~dst~dst_x~dst_y~width~height~pitch bytes~color
let sample_int s x y=
  if x<0||y<0||x>=Surface.width s||y>=Surface.height s then 0
  else Surface.Private.get_rgba_int_unchecked s~x~y
let lerp a b w=((a*(65536-w))+(b*w)+32768)lsr 16
let chi c n=(c lsr n)land 255
let color_int r g b a=(r lsl 24)lor(g lsl 16)lor(b lsl 8)lor a
let bilinear_channel a b c d wx wy n=
  lerp(lerp(chi a n)(chi b n)wx)(lerp(chi c n)(chi d n)wx)wy
let bilinear_int s fx fy=let x=fx asr 16 and y=fy asr 16 and wx=fx land 65535 and wy=fy land 65535 in let x1=min(Surface.width s-1)(x+1)and y1=min(Surface.height s-1)(y+1)in let a=sample_int s x y and b=sample_int s x1 y and c=sample_int s x y1 and d=sample_int s x1 y1 in color_int(bilinear_channel a b c d wx wy 24)(bilinear_channel a b c d wx wy 16)(bilinear_channel a b c d wx wy 8)(bilinear_channel a b c d wx wy 0)
let blit_scaled_blend ~blend ~src ~src_rect:s ~dst ~dst_rect:d ~filter=if s.width<=0||s.height<=0||d.width<=0||d.height<=0 then Error Invalid_extent else let x0=max 0 d.x and y0=max 0 d.y and x1=min(Surface.width dst)(d.x+d.width)and y1=min(Surface.height dst)(d.y+d.height)in for y=y0 to y1-1 do for x=x0 to x1-1 do let rx=x-d.x and ry=y-d.y in let fx=(s.x lsl 16)+((rx*s.width lsl 16)/d.width)and fy=(s.y lsl 16)+((ry*s.height lsl 16)/d.height)in let c=match filter with Nearest->sample_int src(fx asr 16)(fy asr 16)|Bilinear->bilinear_int src fx fy in Composite.pixel_int dst~blend~x~y c done done;Ok()
let blit_affine_blend ~blend ~src ~src_rect:s ~dst ~dst_rect:d ~xx ~xy ~yx ~yy ~tx ~ty ~filter=
 if s.width<=0||s.height<=0||d.width<=0||d.height<=0 then Error Invalid_extent else
 if xx=1.&&xy=0.&&yx=0.&&yy=1.&&tx=0.&&ty=0. then
  blit_scaled_blend~blend~src~src_rect:s~dst~dst_rect:d~filter else
 let determinant=xx*.yy-.xy*.yx in if not(Float.is_finite determinant)||abs_float determinant<1e-15 then Error Invalid_extent else
 let corner x y=(xx*.x+.xy*.y+.tx,yx*.x+.yy*.y+.ty)in
 let corners=[corner(float d.x)(float d.y);corner(float(d.x+d.width))(float d.y);corner(float d.x)(float(d.y+d.height));corner(float(d.x+d.width))(float(d.y+d.height))]in
 let min_x=List.fold_left(fun v(x,_)->min v x)infinity corners and max_x=List.fold_left(fun v(x,_)->max v x)neg_infinity corners and min_y=List.fold_left(fun v(_,y)->min v y)infinity corners and max_y=List.fold_left(fun v(_,y)->max v y)neg_infinity corners in
 let x0=max 0(int_of_float(floor min_x))and y0=max 0(int_of_float(floor min_y))and x1=min(Surface.width dst)(int_of_float(ceil max_x))and y1=min(Surface.height dst)(int_of_float(ceil max_y))in
 for y=y0 to y1-1 do for x=x0 to x1-1 do
  let px=float x+.0.5-.tx and py=float y+.0.5-.ty in
  let local_x=(yy*.px-.xy*.py)/.determinant and local_y=(-.yx*.px+.xx*.py)/.determinant in
  if local_x>=float d.x&&local_x<float(d.x+d.width)&&local_y>=float d.y&&local_y<float(d.y+d.height)then
   let rx=local_x-.float d.x and ry=local_y-.float d.y in
   let fx=(s.x lsl 16)+int_of_float(rx*.float s.width/.float d.width*.65536.)and fy=(s.y lsl 16)+int_of_float(ry*.float s.height/.float d.height*.65536.)in
   let c=match filter with Nearest->sample_int src(fx asr 16)(fy asr 16)|Bilinear->bilinear_int src fx fy in Composite.pixel_int dst~blend~x~y c
 done done;Ok()
let blit_scaled ~src ~src_rect ~dst ~dst_rect ~filter=blit_scaled_blend~blend:Composite.Copy~src~src_rect~dst~dst_rect~filter
