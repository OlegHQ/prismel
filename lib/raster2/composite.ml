type blend=Source_over|Copy|Replace|Alpha|Add|Multiply|Screen|Subtract
type rect={x:int;y:int;width:int;height:int}
type error=Invalid_extent of{width:int;height:int}
let clamp x=min 255(max 0 x)
let chi c n=(c lsr n)land 255
let rgbai r g b a=(r lsl 24)lor(g lsl 16)lor(b lsl 8)lor a
let over_channel s d sa da oa n=
  if oa=0 then 0 else
    let prem=(chi s n*sa)+((chi d n*da*(255-sa)+127)/255)in
    clamp((prem+(oa/2))/oa)
let overi s d=
  let sa=chi s 0 and da=chi d 0 in
  let oa=sa+((da*(255-sa)+127)/255)in
  rgbai(over_channel s d sa da oa 24)(over_channel s d sa da oa 16)
    (over_channel s d sa da oa 8)oa
let mode_channel mode source destination source_alpha=
  let amount=(source*source_alpha+127)/255 in
  match mode with
  |Add->clamp(destination+amount)
  |Multiply->(destination*((source*source_alpha)+(255*(255-source_alpha)))+32512)/65025
  |Screen->255-(((255-destination)*(255-amount)+127)/255)
  |Subtract->max 0(destination-amount)
  |_->assert false
let blend_int mode s d=match mode with Copy|Replace->s|Source_over|Alpha->overi s d
|Add|Multiply|Screen|Subtract->
  let sa=chi s 0 and da=chi d 0 in
  let alpha=sa*255+da*(255-sa)in
  rgbai(mode_channel mode(chi s 24)(chi d 24)sa)
    (mode_channel mode(chi s 16)(chi d 16)sa)
    (mode_channel mode(chi s 8)(chi d 8)sa)((alpha+127)/255)
let blend mode s d=Int32.of_int(blend_int mode(Int32.to_int s)(Int32.to_int d))
let color ~blend:mode ~source ~destination=blend mode source destination
let pixel_int dst ~blend:mode ~x ~y color=
  if x>=0&&y>=0&&x<Surface.width dst&&y<Surface.height dst then begin
    let old=Surface.Private.get_rgba_int_unchecked dst~x~y in
    Surface.Private.set_rgba_int_unchecked dst~x~y(blend_int mode color old)
  end
let pixel dst ~blend:mode ~x ~y color=
  pixel_int dst~blend:mode~x~y(Int32.to_int color)
let rect dst ~blend r color=if r.width<0||r.height<0 then Error(Invalid_extent{width=r.width;height=r.height})else(let x0=max 0 r.x and y0=max 0 r.y and x1=min(Surface.width dst)(r.x+r.width)and y1=min(Surface.height dst)(r.y+r.height)in for y=y0 to y1-1 do for x=x0 to x1-1 do pixel dst~blend~x~y color done done;Ok())
let blit ~src ~src_rect:r ~dst ~dst_x ~dst_y ~blend:mode=if r.width<0||r.height<0 then Error(Invalid_extent{width=r.width;height=r.height})else let samples=Array.init(r.width*r.height)(fun i->let x=r.x+(i mod r.width)and y=r.y+(i/r.width)in match Surface.get_rgba src~x~y with Ok c->Some c|Error _->None)in Array.iteri(fun i c->match c with None->()|Some color->let x=dst_x+(i mod r.width)and y=dst_y+(i/r.width)in pixel dst~blend:mode~x~y color)samples;Ok()
