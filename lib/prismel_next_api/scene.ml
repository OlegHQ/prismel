type blend=Replace|Alpha|Add|Multiply
type primitive={points:(int*int)list;closed:bool;fill:Color.t option;stroke:Color.t option}
type text_node={x:int;y:int;value:string;color:Color.t;size:int;wrap:int option;align:Font.alignment;provided_font:Font.t option;mutable owned_font:Font.t option;mutable rendered:Image.t option}
and view3d_node={viewport:(int*int*int*int)option;camera:Camera.t;scene:Scene3.t;mutable rendered3d:Image.t option}
and node=Group of t|Clear of Color.t|Primitive of primitive|Geometry of Raster2.Render_ir.geometry|Text of text_node|Image of Image.t*(int*int)
 |View3d of view3d_node|Region of int*int*int*int*bool
 |Translate of int*int*t|Rotate of float*t|Scale of float*float*t|Clip of int*int*int*int*t|Blend of blend*t
and t=node list
let empty=[]let one n=[n]let group x=Group x let clear c=Clear c
let default_color=Color.white
let rgba c=Int32.logor(Int32.shift_left(Int32.of_int c.Color.r)24)(Int32.logor(Int32.shift_left(Int32.of_int c.g)16)(Int32.logor(Int32.shift_left(Int32.of_int c.b)8)(Int32.of_int c.a)))
let point2 (x,y)={Raster2.Path.x=float x;y=float y}
let geometry_of_mesh color (mesh:Raster2.Path.mesh)=
  let vertices=Array.make(Array.length mesh.vertices*2)0. in
  Array.iteri(fun index (point:Raster2.Path.point)->vertices.(index*2)<-point.x;vertices.(index*2+1)<-point.y)mesh.vertices;
  Geometry{Raster2.Render_ir.vertices;indices=mesh.indices;color=rgba color}
let path_error operation=function
  |Ok mesh->mesh|Error Raster2.Path.Empty_path->{Raster2.Path.vertices=[||];indices=[||]}
  |Error _->invalid_arg operation
let fill_path color path=geometry_of_mesh color(path_error"Scene path fill"(Raster2.Path.tessellate~tolerance:0.25~fill_rule:Raster2.Path.Non_zero path))
let stroke_path ?(width=1.) color path=geometry_of_mesh color(path_error"Scene path stroke"(Raster2.Path.stroke~tolerance:0.25~width~cap:Raster2.Path.Butt~join:Raster2.Path.Miter~miter_limit:4. path))
let styled_path ?fill ?stroke path=
  let fill=match fill,stroke with None,None->Some default_color|_->fill in
  Group(Option.to_list(Option.map(fun color->fill_path color path)fill)@Option.to_list(Option.map(fun color->stroke_path color path)stroke))
let point ~at ?(color=default_color)()=Primitive{points=[at];closed=false;fill=None;stroke=Some color}
let line ~from_ ~to_ ?(color=default_color)?(width=1)()=
  stroke_path~width:(float(max 1 width))color(Raster2.Path.of_commands[|Raster2.Path.Move_to(point2 from_);Raster2.Path.Line_to(point2 to_)|])
let polygon points ?fill ?stroke()=Primitive{points;closed=true;fill;stroke}
let polyline points ?(color=default_color)()=Primitive{points;closed=false;fill=None;stroke=Some color}
let rect ~at:(x,y)~w~h ?fill ?stroke()=polygon[x,y;x+w,y;x+w,y+h;x,y+h]?fill?stroke()
let square ~at ~size ?fill ?stroke()=rect~at~w:size~h:size?fill?stroke()
let rounded_rect ~at:(x,y) ~w ~h ~radius ?fill ?stroke()=
  let r=float(max 0(min radius(min(abs w)(abs h)/2)))and x=float x and y=float y and w=float w and h=float h in
  let k=0.5522847498307936*.r in
  let p x y={Raster2.Path.x;y}in
  let path=Raster2.Path.of_commands[|
    Raster2.Path.Move_to(p(x+.r)y);Line_to(p(x+.w-.r)y);
    Cubic_to(p(x+.w-.r+.k)y,p(x+.w)(y+.r-.k),p(x+.w)(y+.r));
    Line_to(p(x+.w)(y+.h-.r));Cubic_to(p(x+.w)(y+.h-.r+.k),p(x+.w-.r+.k)(y+.h),p(x+.w-.r)(y+.h));
    Line_to(p(x+.r)(y+.h));Cubic_to(p(x+.r-.k)(y+.h),p x(y+.h-.r+.k),p x(y+.h-.r));
    Line_to(p x(y+.r));Cubic_to(p x(y+.r-.k),p(x+.r-.k)y,p(x+.r)y);Close|]in
  styled_path?fill?stroke path
let ellipse_points (cx,cy) rx ry=List.init 32(fun i->let a=(2.*.Float.pi)*.float i/.32. in cx+int_of_float(float rx*.cos a),cy+int_of_float(float ry*.sin a))
let ellipse ~at ~rx ~ry ?fill ?stroke()=polygon(ellipse_points at rx ry)?fill?stroke()
let circle ~at ~radius ?fill ?stroke()=ellipse~at~rx:radius~ry:radius?fill?stroke()
let triangle a b c ?fill ?stroke()=polygon[a;b;c]?fill?stroke()
let quad a b c d ?fill ?stroke()=polygon[a;b;c;d]?fill?stroke()
let arc ~at:(cx,cy)~radius~from_~to_ ?(color=default_color)()=let points=List.init 33(fun i->let a=from_+.(to_-.from_)*.float i/.32. in cx+int_of_float(float radius*.cos a),cy+int_of_float(float radius*.sin a))in polyline points~color()
let pie ~at ~radius ~from_ ~to_ ?fill ?stroke()=match arc~at~radius~from_~to_()with Primitive p->polygon(at::p.points)?fill?stroke()|_->assert false
let bezier points ?(steps=20)?(color=default_color)()=
  let steps=max 1 steps in
  match points with
  |[]->Group[]|[p0]->point~at:p0~color()
  |first::rest->
      let controls=Array.of_list points in
      let sampled=List.init(steps+1)(fun sample->let t=float sample/.float steps in
        let values=Array.map(fun(x,y)->float x,float y)controls in
        for level=Array.length values-1 downto 1 do for index=0 to level-1 do
          let x0,y0=values.(index)and x1,y1=values.(index+1)in
          values.(index)<-(x0+.t*.(x1-.x0),y0+.t*.(y1-.y0))done done;
        let x,y=values.(0)in {Raster2.Path.x;y})in
      let commands=Array.of_list(Raster2.Path.Move_to(point2 first)::List.map(fun p->Raster2.Path.Line_to p)(List.tl sampled))in
      ignore rest;stroke_path color(Raster2.Path.of_commands commands)
let path ?(steps=20)?(fill_rule=Path.Non_zero)?fill?stroke value=ignore fill_rule;Primitive{points=Path.points~steps value;closed=Path.is_closed value;fill;stroke}
let text ~at:(x,y) ?(color=default_color) ?(size=16) value=Text{x;y;value;color;size;wrap=None;align=Font.Left;provided_font=None;owned_font=None;rendered=None}
let debug_text ~at ?color value=text~at?color~size:8 value
let font_text font ~at:(x,y) ?(color=default_color) ?wrap ?(align=Font.Left) value=Text{x;y;value;color;size=Font.get_size font;wrap;align;provided_font=Some font;owned_font=None;rendered=None}
let image image ~at ?scale ?angle ?center ?flip_x()=ignore(scale,angle,center,flip_x);Image(image,at)
let view3d ?viewport ~camera scene=View3d{viewport;camera;scene;rendered3d=None}
let text_input_region ~at:(x,y)~w~h ?(focused=false)()=Region(x,y,w,h,focused)
let translate x y nodes=Translate(x,y,nodes)let rotate a nodes=Rotate(a,nodes)let scale x y nodes=Scale(x,y,nodes)
let clip ~at:(x,y)~w~h nodes=Clip(x,y,w,h,nodes)let blend mode nodes=Blend(mode,nodes)
let geometry p=let vertices=Array.of_list(List.concat_map(fun(x,y)->[float x;float y])p.points)in let n=List.length p.points in
 let indices=if p.closed&&n>=3 then Array.init((n-2)*3)(fun i->let t=i/3 and k=i mod 3 in if k=0 then 0 else t+k)else if n=1 then[|0|]else Array.init(max 0((n-1)*2))(fun i->if i mod 2=0 then i/2 else i/2+1)in
 Raster2.Render_ir.Geometry{vertices;indices;color=rgba(Option.value p.fill~default:(Option.value p.stroke~default:default_color))}
module Private=struct
 let renderer=ref(fun(_ : t)->())let install_renderer value=renderer:=value
 let rec commands acc=function []->acc|Clear c::xs->commands(Raster2.Render_ir.Clear(rgba c)::acc)xs|Primitive p::xs->commands(geometry p::acc)xs|Geometry g::xs->commands(Raster2.Render_ir.Geometry g::acc)xs|Group g::xs->commands(commands acc g)xs
  |Translate(x,y,g)::xs->commands(Raster2.Render_ir.Pop_transform::commands(Raster2.Render_ir.Push_transform{xx=1.;xy=0.;yx=0.;yy=1.;tx=float x;ty=float y}::acc)g)xs
  |Scale(x,y,g)::xs->commands(Raster2.Render_ir.Pop_transform::commands(Raster2.Render_ir.Push_transform{xx=x;xy=0.;yx=0.;yy=y;tx=0.;ty=0.}::acc)g)xs
  |Rotate(a,g)::xs->let c=cos a and s=sin a in commands(Raster2.Render_ir.Pop_transform::commands(Raster2.Render_ir.Push_transform{xx=c;xy=s;yx=(-.s);yy=c;tx=0.;ty=0.}::acc)g)xs
  |Clip(x,y,w,h,g)::xs->commands(Raster2.Render_ir.Pop_clip::commands(Raster2.Render_ir.Push_clip{x=float x;y=float y;width=float w;height=float h}::acc)g)xs
  |Blend(mode,g)::xs->let mode=match mode with Replace->Raster2.Composite.Replace|Alpha->Alpha|Add->Add|Multiply->Multiply in commands(commands(Raster2.Render_ir.Set_blend mode::acc)g)xs
  |Image(image,(x,y))::xs->let width,height=Image.get_size image in let rect={Raster2.Render_ir.x=0.;y=0.;width=float width;height=float height}in
    let destination={rect with Raster2.Render_ir.x=float x;y=float y}in commands(Raster2.Render_ir.Image{resource_id=Image.identity image;source=rect;destination}::acc)xs
  |(Text _|View3d _|Region _)::xs->commands acc xs
 let rec text_regions scene=List.concat_map(function Region(x,y,w,h,f)->[x,y,w,h,f]|Group g|Translate(_,_,g)|Rotate(_,g)|Scale(_,_,g)|Clip(_,_,_,_,g)|Blend(_,g)->text_regions g|_->[])scene
 let rec image_resources scene=List.concat_map(function Image(image,_)->[Image.identity image,Prismel_next_execution.Image image]|Group g|Translate(_,_,g)|Rotate(_,g)|Scale(_,_,g)|Clip(_,_,_,_,g)|Blend(_,g)->image_resources g|_->[])scene

 let text_image (node : text_node) =
   match node.rendered with
   | Some image -> image
   | None ->
       let font =
         match node.provided_font, node.owned_font with
         | Some font, _ -> font
         | None, Some font -> font
         | None, None ->
             let font = Result.get_ok (Font.system ~size:node.size ()) in
             node.owned_font <- Some font;
             font
       in
       let image =
         Result.get_ok
           (Font.cached_text ?wrap:node.wrap ~align:node.align font node.value
              (Font.Solid node.color))
       in
       node.rendered <- Some image;
       image

 let view_image ~width ~height (node : view3d_node) =
   match node.rendered3d with
   | Some image -> image
   | None ->
       let x, y, view_width, view_height =
         Option.value node.viewport ~default:(0, 0, width, height)
       in
       let framebuffer =
         Framebuffer3.render ~width:view_width ~height:view_height
           ~camera:node.camera node.scene
       in
       let image = Result.get_ok (Framebuffer3.to_image framebuffer) in
       node.rendered3d <- Some image;
       ignore (x, y);
       image

 let rec materialize ~width ~height = function
   | [] -> []
   | Text node :: rest ->
       Image (text_image node, (node.x, node.y))
       :: materialize ~width ~height rest
   | View3d node :: rest ->
       let x, y, _, _ =
         Option.value node.viewport ~default:(0, 0, width, height)
       in
       Image (view_image ~width ~height node, (x, y))
       :: materialize ~width ~height rest
   | Group nodes :: rest ->
       Group (materialize ~width ~height nodes)
       :: materialize ~width ~height rest
   | Translate (x, y, nodes) :: rest ->
       Translate (x, y, materialize ~width ~height nodes)
       :: materialize ~width ~height rest
   | Rotate (angle, nodes) :: rest ->
       Rotate (angle, materialize ~width ~height nodes)
       :: materialize ~width ~height rest
   | Scale (x, y, nodes) :: rest ->
       Scale (x, y, materialize ~width ~height nodes)
       :: materialize ~width ~height rest
   | Clip (x, y, w, h, nodes) :: rest ->
       Clip (x, y, w, h, materialize ~width ~height nodes)
       :: materialize ~width ~height rest
   | Blend (mode, nodes) :: rest ->
       Blend (mode, materialize ~width ~height nodes)
       :: materialize ~width ~height rest
   | node :: rest -> node :: materialize ~width ~height rest

 let stage ~width ~height scene =
   if width <= 0 || height <= 0 then Error "invalid scene extent"
   else
     try
       let scene = materialize ~width ~height scene in
       match Raster2.Render_ir.create (Array.of_list (List.rev (commands [] scene))) with
       | Error _ -> Error "invalid scene description"
       | Ok ir -> Ok (ir, image_resources scene)
     with
     | Failure message -> Error message
     | Invalid_argument message -> Error message

 let to_ir scene = Result.map fst (stage ~width:640 ~height:480 scene)
 let resources scene =
   match stage ~width:640 ~height:480 scene with
   | Ok (_, resources) -> resources
   | Error _ -> []

 let rec release scene =
   List.iter
     (function
       | Text node ->
           (match node.owned_font with
           | Some font -> Font.destroy font
           | None -> ());
           node.owned_font <- None;
           node.rendered <- None
       | View3d node ->
           Option.iter Image.destroy node.rendered3d;
           node.rendered3d <- None
       | Group nodes | Translate (_, _, nodes) | Rotate (_, nodes)
       | Scale (_, _, nodes) | Clip (_, _, _, _, nodes) | Blend (_, nodes) ->
           release nodes
       | Clear _ | Primitive _ | Geometry _ | Image _ | Region _ -> ())
     scene
end
let render scene=(!Private.renderer) scene
