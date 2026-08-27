type blend=Source_over|Copy|Replace|Alpha|Add|Multiply|Screen|Subtract
type rect={x:int;y:int;width:int;height:int}
type error=Invalid_extent of{width:int;height:int}
let ch c n=Int32.(to_int(logand(shift_right_logical c n)0xffl))
let rgba r g b a=Int32.(logor(shift_left(of_int r)24)(logor(shift_left(of_int g)16)(logor(shift_left(of_int b)8)(of_int a))))
let clamp x=min 255(max 0 x)
let over s d=let sa=ch s 0 and da=ch d 0 in let oa=sa+((da*(255-sa)+127)/255)in let c n=if oa=0 then 0 else let prem=(ch s n*sa)+((ch d n*da*(255-sa)+127)/255)in clamp((prem+(oa/2))/oa)in rgba(c 24)(c 16)(c 8)oa
let blend mode s d=match mode with Copy|Replace->s|Source_over|Alpha->over s d|Add|Multiply|Screen|Subtract->let sa=ch s 0 and da=ch d 0 in let amount value=(value*sa+127)/255 in let f n=let source=ch s n and destination=ch d n in match mode with Add->clamp(destination+amount source)|Multiply->clamp((destination*((source*sa)+(255*(255-sa)))+32512)/65025)|Screen->clamp(255-(((255-destination)*(255-amount source)+127)/255))|Subtract->clamp(destination-amount source)|_->assert false in rgba(f 24)(f 16)(f 8)(sa+((da*(255-sa)+127)/255))
let color ~blend:mode ~source ~destination=blend mode source destination
let pixel dst ~blend:mode ~x ~y color=match Surface.get_rgba dst~x~y with Error _->()|Ok old->ignore(Surface.set_rgba dst~x~y(blend mode color old))
let rect dst ~blend r color=if r.width<0||r.height<0 then Error(Invalid_extent{width=r.width;height=r.height})else(let x0=max 0 r.x and y0=max 0 r.y and x1=min(Surface.width dst)(r.x+r.width)and y1=min(Surface.height dst)(r.y+r.height)in for y=y0 to y1-1 do for x=x0 to x1-1 do pixel dst~blend~x~y color done done;Ok())
let blit ~src ~src_rect:r ~dst ~dst_x ~dst_y ~blend:mode=if r.width<0||r.height<0 then Error(Invalid_extent{width=r.width;height=r.height})else let samples=Array.init(r.width*r.height)(fun i->let x=r.x+(i mod r.width)and y=r.y+(i/r.width)in match Surface.get_rgba src~x~y with Ok c->Some c|Error _->None)in Array.iteri(fun i c->match c with None->()|Some color->let x=dst_x+(i mod r.width)and y=dst_y+(i/r.width)in pixel dst~blend:mode~x~y color)samples;Ok()
