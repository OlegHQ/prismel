type blend=Replace|Alpha|Add|Multiply
type primitive={points:(int*int)list;closed:bool;fill:Color.t option;stroke:Color.t option}
type node=Group of t|Clear of Color.t|Primitive of primitive|Text of int*int*string|Image of Image.t*(int*int)
 |View3d of (int*int*int*int)option*Camera.t*Scene3.t|Region of int*int*int*int*bool
 |Translate of int*int*t|Rotate of float*t|Scale of float*float*t|Clip of int*int*int*int*t|Blend of blend*t
and t=node list
let empty=[]let one n=[n]let group x=Group x let clear c=Clear c
let default_color=Color.white
let point ~at ?(color=default_color)()=Primitive{points=[at];closed=false;fill=None;stroke=Some color}
let line ~from_ ~to_ ?(color=default_color)?(width=1)()=ignore width;Primitive{points=[from_;to_];closed=false;fill=None;stroke=Some color}
let polygon points ?fill ?stroke()=Primitive{points;closed=true;fill;stroke}
let polyline points ?(color=default_color)()=Primitive{points;closed=false;fill=None;stroke=Some color}
let rect ~at:(x,y)~w~h ?fill ?stroke()=polygon[x,y;x+w,y;x+w,y+h;x,y+h]?fill?stroke()
let square ~at ~size ?fill ?stroke()=rect~at~w:size~h:size?fill?stroke()
let rounded_rect ~at ~w ~h ~radius ?fill ?stroke()=ignore radius;rect~at~w~h?fill?stroke()
let ellipse_points (cx,cy) rx ry=List.init 32(fun i->let a=(2.*.Float.pi)*.float i/.32. in cx+int_of_float(float rx*.cos a),cy+int_of_float(float ry*.sin a))
let ellipse ~at ~rx ~ry ?fill ?stroke()=polygon(ellipse_points at rx ry)?fill?stroke()
let circle ~at ~radius ?fill ?stroke()=ellipse~at~rx:radius~ry:radius?fill?stroke()
let triangle a b c ?fill ?stroke()=polygon[a;b;c]?fill?stroke()
let quad a b c d ?fill ?stroke()=polygon[a;b;c;d]?fill?stroke()
let arc ~at:(cx,cy)~radius~from_~to_ ?(color=default_color)()=let points=List.init 33(fun i->let a=from_+.(to_-.from_)*.float i/.32. in cx+int_of_float(float radius*.cos a),cy+int_of_float(float radius*.sin a))in polyline points~color()
let pie ~at ~radius ~from_ ~to_ ?fill ?stroke()=match arc~at~radius~from_~to_()with Primitive p->polygon(at::p.points)?fill?stroke()|_->assert false
let bezier points ?(steps=20)?(color=default_color)()=ignore steps;polyline points~color()
let path ?(steps=20)?(fill_rule=Path.Non_zero)?fill?stroke value=ignore fill_rule;Primitive{points=Path.points~steps value;closed=Path.is_closed value;fill;stroke}
let text ~at:(x,y) ?color ?size value=ignore(color,size);Text(x,y,value)let debug_text ~at ?color value=text~at?color value
let font_text font ~at:(x,y) ?color ?wrap ?align value=ignore(font,color,wrap,align);Text(x,y,value)
let image image ~at ?scale ?angle ?center ?flip_x()=ignore(scale,angle,center,flip_x);Image(image,at)
let view3d ?viewport ~camera scene=View3d(viewport,camera,scene)
let text_input_region ~at:(x,y)~w~h ?(focused=false)()=Region(x,y,w,h,focused)
let translate x y nodes=Translate(x,y,nodes)let rotate a nodes=Rotate(a,nodes)let scale x y nodes=Scale(x,y,nodes)
let clip ~at:(x,y)~w~h nodes=Clip(x,y,w,h,nodes)let blend mode nodes=Blend(mode,nodes)
let rgba c=Int32.logor(Int32.shift_left(Int32.of_int c.Color.r)24)(Int32.logor(Int32.shift_left(Int32.of_int c.g)16)(Int32.logor(Int32.shift_left(Int32.of_int c.b)8)(Int32.of_int c.a)))
let geometry p=let vertices=Array.of_list(List.concat_map(fun(x,y)->[float x;float y])p.points)in let n=List.length p.points in
 let indices=if p.closed&&n>=3 then Array.init((n-2)*3)(fun i->let t=i/3 and k=i mod 3 in if k=0 then 0 else t+k)else if n=1 then[|0|]else Array.init(max 0((n-1)*2))(fun i->if i mod 2=0 then i/2 else i/2+1)in
 Raster2.Render_ir.Geometry{vertices;indices;color=rgba(Option.value p.fill~default:(Option.value p.stroke~default:default_color))}
module Private=struct
 let renderer=ref(fun(_ : t)->())let install_renderer value=renderer:=value
 let rec commands acc=function []->acc|Clear c::xs->commands(Raster2.Render_ir.Clear(rgba c)::acc)xs|Primitive p::xs->commands(geometry p::acc)xs|Group g::xs->commands(commands acc g)xs
  |Translate(x,y,g)::xs->commands(Raster2.Render_ir.Pop_transform::commands(Raster2.Render_ir.Push_transform{xx=1.;xy=0.;yx=0.;yy=1.;tx=float x;ty=float y}::acc)g)xs
  |Scale(x,y,g)::xs->commands(Raster2.Render_ir.Pop_transform::commands(Raster2.Render_ir.Push_transform{xx=x;xy=0.;yx=0.;yy=y;tx=0.;ty=0.}::acc)g)xs
  |Rotate(a,g)::xs->let c=cos a and s=sin a in commands(Raster2.Render_ir.Pop_transform::commands(Raster2.Render_ir.Push_transform{xx=c;xy=s;yx=(-.s);yy=c;tx=0.;ty=0.}::acc)g)xs
  |Clip(x,y,w,h,g)::xs->commands(Raster2.Render_ir.Pop_clip::commands(Raster2.Render_ir.Push_clip{x=float x;y=float y;width=float w;height=float h}::acc)g)xs
  |Blend(mode,g)::xs->let mode=match mode with Replace->Raster2.Composite.Replace|Alpha->Alpha|Add->Add|Multiply->Multiply in commands(commands(Raster2.Render_ir.Set_blend mode::acc)g)xs
  |Image(image,(x,y))::xs->let width,height=Image.get_size image in let rect={Raster2.Render_ir.x=0.;y=0.;width=float width;height=float height}in
    let destination={rect with Raster2.Render_ir.x=float x;y=float y}in commands(Raster2.Render_ir.Image{resource_id=Image.identity image;source=rect;destination}::acc)xs
  |(Text _|View3d _|Region _)::xs->commands acc xs
 let to_ir scene=match Raster2.Render_ir.create(Array.of_list(List.rev(commands[]scene)))with Ok value->Ok value|Error _->Error"invalid scene description"
 let rec text_regions scene=List.concat_map(function Region(x,y,w,h,f)->[x,y,w,h,f]|Group g|Translate(_,_,g)|Rotate(_,g)|Scale(_,_,g)|Clip(_,_,_,_,g)|Blend(_,g)->text_regions g|_->[])scene
 let rec resources scene=List.concat_map(function Image(image,_)->[Image.identity image,Prismel_next_execution.Image image]|Group g|Translate(_,_,g)|Rotate(_,g)|Scale(_,_,g)|Clip(_,_,_,_,g)|Blend(_,g)->resources g|_->[])scene
end
let render scene=(!Private.renderer) scene
