type blend=Replace|Alpha|Add|Multiply
type primitive={points:(int*int)list;closed:bool;fill:Color.t option;stroke:Color.t option}
type text_node={x:int;y:int;value:string;color:Color.t;size:int;wrap:int option;align:Font.alignment;provided_font:Font.t option;mutable automatic:Font.Private.automatic option;mutable rendered:Image.t option}
and debug_text_node={x:int;y:int;value:string;color:Color.t}
and view3d_node={viewport:(int*int*int*int)option;camera:Camera.t;scene:Scene3.t;mutable rendered3d:Image.t option}
and image_node={image:Image.t;x:int;y:int;scale:float;angle:float;center:(int*int)option;flip_x:bool}
and node=Group of t|Clear of Color.t|Primitive of primitive|Geometry of Raster2.Render_ir.geometry|Text of text_node|Debug_text of debug_text_node|Image of image_node
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
type rounded_cache={table:((int*int*int*int32 option*int32 option),t)Hashtbl.t;mutable order:(int*int*int*int32 option*int32 option)list}
let rounded_cache_capacity=256
let rounded_caches=Domain.DLS.new_key(fun()->{table=Hashtbl.create rounded_cache_capacity;order=[]})
let rounded_cached key make=
  let cache=Domain.DLS.get rounded_caches in
  match Hashtbl.find_opt cache.table key with
  |Some value->value
  |None->
      let value=make()in
      (if Hashtbl.length cache.table>=rounded_cache_capacity then
        match List.rev cache.order with
        |[]->()
        |oldest::rest->Hashtbl.remove cache.table oldest;cache.order<-List.rev rest);
      Hashtbl.replace cache.table key value;cache.order<-key::cache.order;value
let point ~at ?(color=default_color)()=Primitive{points=[at];closed=false;fill=None;stroke=Some color}
let line ~from_ ~to_ ?(color=default_color)?(width=1)()=
  stroke_path~width:(float(max 1 width))color(Raster2.Path.of_commands[|Raster2.Path.Move_to(point2 from_);Raster2.Path.Line_to(point2 to_)|])
let polygon points ?fill ?stroke()=Primitive{points;closed=true;fill;stroke}
let polyline points ?(color=default_color)()=Primitive{points;closed=false;fill=None;stroke=Some color}
let rect ~at:(x,y)~w~h ?fill ?stroke()=polygon[x,y;x+w,y;x+w,y+h;x,y+h]?fill?stroke()
let square ~at ~size ?fill ?stroke()=rect~at~w:size~h:size?fill?stroke()
let rounded_rect ~at:(x,y) ~w ~h ~radius ?fill ?stroke()=
  let radius=max 0(min radius(min(abs w)(abs h)/2))in
  let key=w,h,radius,Option.map rgba fill,Option.map rgba stroke in
  let geometry=rounded_cached key(fun()->
    let r=float radius and w=float w and h=float h in
    let k=0.5522847498307936*.r in
    let p x y={Raster2.Path.x;y}in
    let path=Raster2.Path.of_commands[|
      Raster2.Path.Move_to(p r 0.);Line_to(p(w-.r)0.);
      Cubic_to(p(w-.r+.k)0.,p w(r-.k),p w r);
      Line_to(p w(h-.r));Cubic_to(p w(h-.r+.k),p(w-.r+.k)h,p(w-.r)h);
      Line_to(p r h);Cubic_to(p(r-.k)h,p 0.(h-.r+.k),p 0.(h-.r));
      Line_to(p 0. r);Cubic_to(p 0.(r-.k),p(r-.k)0.,p r 0.);Close|]in
    [styled_path?fill?stroke path])in
  Translate(x,y,geometry)
type ellipse_cache={table:((int*int*int*int*int32 option*int32 option),node)Hashtbl.t;
  mutable order:(int*int*int*int*int32 option*int32 option)list}
let ellipse_cache_capacity=256
let ellipse_caches=Domain.DLS.new_key(fun()->
  {table=Hashtbl.create ellipse_cache_capacity;order=[]})
let ellipse_cached key make=
  let cache=Domain.DLS.get ellipse_caches in
  match Hashtbl.find_opt cache.table key with
  |Some value->value
  |None->
      let value=make()in
      (if Hashtbl.length cache.table>=ellipse_cache_capacity then
        match List.rev cache.order with
        |[]->()
        |oldest::rest->Hashtbl.remove cache.table oldest;cache.order<-List.rev rest);
      Hashtbl.replace cache.table key value;cache.order<-key::cache.order;value
let ellipse_points (cx,cy) rx ry=List.init 32(fun i->let a=(2.*.Float.pi)*.float i/.32. in cx+int_of_float(float rx*.cos a),cy+int_of_float(float ry*.sin a))
let ellipse ~at:(cx,cy as at) ~rx ~ry ?fill ?stroke()=
  let key=cx,cy,rx,ry,Option.map rgba fill,Option.map rgba stroke in
  ellipse_cached key(fun()->polygon(ellipse_points at rx ry)?fill?stroke())
let circle ~at ~radius ?fill ?stroke()=ellipse~at~rx:radius~ry:radius?fill?stroke()
let triangle a b c ?fill ?stroke()=polygon[a;b;c]?fill?stroke()
let quad a b c d ?fill ?stroke()=polygon[a;b;c;d]?fill?stroke()
let arc ~at:(cx,cy)~radius~from_~to_ ?(color=default_color)()=let points=List.init 33(fun i->let a=from_+.(to_-.from_)*.float i/.32. in cx+int_of_float(float radius*.cos a),cy+int_of_float(float radius*.sin a))in polyline points~color()
let pie ~at ~radius ~from_ ~to_ ?fill ?stroke()=match arc~at~radius~from_~to_()with Primitive p->polygon(at::p.points)?fill?stroke()|_->assert false
type bezier_cache={table:(((int*int)list*int*int32),node)Hashtbl.t;
  mutable order:((int*int)list*int*int32)list}
let bezier_cache_capacity=256
let bezier_caches=Domain.DLS.new_key(fun()->
  {table=Hashtbl.create bezier_cache_capacity;order=[]})
let bezier_cached key make=
  let cache=Domain.DLS.get bezier_caches in
  match Hashtbl.find_opt cache.table key with
  |Some value->value
  |None->
      let value=make()in
      (if Hashtbl.length cache.table>=bezier_cache_capacity then
        match List.rev cache.order with
        |[]->()
        |oldest::rest->Hashtbl.remove cache.table oldest;cache.order<-List.rev rest);
      Hashtbl.replace cache.table key value;cache.order<-key::cache.order;value
let bezier points ?(steps=20)?(color=default_color)()=
  let steps=max 1 steps in
  match points with
  |[]->Group[]|[p0]->point~at:p0~color()
  |first::rest->
      bezier_cached(points,steps,rgba color)(fun()->
      let controls=Array.of_list points in
      let sampled=List.init(steps+1)(fun sample->let t=float sample/.float steps in
        let values=Array.map(fun(x,y)->float x,float y)controls in
        for level=Array.length values-1 downto 1 do for index=0 to level-1 do
          let x0,y0=values.(index)and x1,y1=values.(index+1)in
          values.(index)<-(x0+.t*.(x1-.x0),y0+.t*.(y1-.y0))done done;
        let x,y=values.(0)in {Raster2.Path.x;y})in
      let commands=Array.of_list(Raster2.Path.Move_to(point2 first)::List.map(fun p->Raster2.Path.Line_to p)(List.tl sampled))in
      ignore rest;stroke_path color(Raster2.Path.of_commands commands))
let path ?(steps=20)?(fill_rule=Path.Non_zero)?fill?stroke value=ignore fill_rule;Primitive{points=Path.points~steps value;closed=Path.is_closed value;fill;stroke}
let text ~at:(x,y) ?(color=default_color) ?(size=16) value=Text{x;y;value;color;size;wrap=None;align=Font.Left;provided_font=None;automatic=None;rendered=None}
let debug_text ~at:(x,y) ?(color=default_color) value=Debug_text{x;y;value;color}
let font_text font ~at:(x,y) ?(color=default_color) ?wrap ?(align=Font.Left) value=Text{x;y;value;color;size=Font.get_size font;wrap;align;provided_font=Some font;automatic=None;rendered=None}
let image image ~at:(x,y) ?(scale=1.) ?(angle=0.) ?center ?(flip_x=false)()=
  if not(Float.is_finite scale&&Float.is_finite angle)||scale<=0. then invalid_arg"Scene.image: invalid transform";
  Image{image;x;y;scale;angle;center;flip_x}
let view3d ?viewport ~camera scene=View3d{viewport;camera;scene;rendered3d=None}
let text_input_region ~at:(x,y)~w~h ?(focused=false)()=Region(x,y,w,h,focused)
let translate x y nodes=Translate(x,y,nodes)let rotate a nodes=Rotate(a,nodes)let scale x y nodes=Scale(x,y,nodes)
let clip ~at:(x,y)~w~h nodes=Clip(x,y,w,h,nodes)let blend mode nodes=Blend(mode,nodes)
let geometry_uncached p=
 let n=List.length p.points in
 let vertices=Array.make(n*2)0. in
 let rec fill index=function
  |[]->()
  |(x,y)::rest->vertices.(index)<-float x;vertices.(index+1)<-float y;
      fill(index+2)rest in
 fill 0 p.points;
 let indices=if p.closed&&n>=3 then Array.init((n-2)*3)(fun i->let t=i/3 and k=i mod 3 in if k=0 then 0 else t+k)else if n=1 then[|0|]else Array.init(max 0((n-1)*2))(fun i->if i mod 2=0 then i/2 else i/2+1)in
 Raster2.Render_ir.Geometry{vertices;indices;color=rgba(Option.value p.fill~default:(Option.value p.stroke~default:default_color))}
type primitive_cache={primitive_table:(primitive,Raster2.Render_ir.command)Hashtbl.t;
  mutable primitive_order:primitive list}
let primitive_cache_capacity=256
let primitive_caches=Domain.DLS.new_key(fun()->
  {primitive_table=Hashtbl.create primitive_cache_capacity;primitive_order=[]})
let geometry p=
  let cache=Domain.DLS.get primitive_caches in
  match Hashtbl.find_opt cache.primitive_table p with
  |Some command->command
  |None->
      let command=geometry_uncached p in
      (if Hashtbl.length cache.primitive_table>=primitive_cache_capacity then
        match List.rev cache.primitive_order with
        |[]->()
        |oldest::rest->
            Hashtbl.remove cache.primitive_table oldest;
            cache.primitive_order<-List.rev rest);
      Hashtbl.replace cache.primitive_table p command;
      cache.primitive_order<-p::cache.primitive_order;
      command
module Private=struct
 type staged_native={scene2:Raster2.Render_ir.t;
   resources:(int*Prismel_next_execution.resource)list;
   scene3:Scene_execution.prepared_scene3 list}
 let renderer=ref(fun(_ : t)->())let install_renderer value=renderer:=value
 let rec commands acc=function []->acc|Clear c::xs->commands(Raster2.Render_ir.Clear(rgba c)::acc)xs|Primitive p::xs->commands(geometry p::acc)xs|Geometry g::xs->commands(Raster2.Render_ir.Geometry g::acc)xs|Group g::xs->commands(commands acc g)xs
  |Debug_text node::xs->commands(Raster2.Render_ir.Debug_text{x=float node.x;y=float node.y;text=node.value;color=rgba node.color}::acc)xs
  |Translate(x,y,g)::xs->commands(Raster2.Render_ir.Pop_transform::commands(Raster2.Render_ir.Push_transform{xx=1.;xy=0.;yx=0.;yy=1.;tx=float x;ty=float y}::acc)g)xs
  |Scale(x,y,g)::xs->commands(Raster2.Render_ir.Pop_transform::commands(Raster2.Render_ir.Push_transform{xx=x;xy=0.;yx=0.;yy=y;tx=0.;ty=0.}::acc)g)xs
  |Rotate(a,g)::xs->let c=cos a and s=sin a in commands(Raster2.Render_ir.Pop_transform::commands(Raster2.Render_ir.Push_transform{xx=c;xy=s;yx=(-.s);yy=c;tx=0.;ty=0.}::acc)g)xs
  |Clip(x,y,w,h,g)::xs->commands(Raster2.Render_ir.Pop_clip::commands(Raster2.Render_ir.Push_clip{x=float x;y=float y;width=float w;height=float h}::acc)g)xs
  |Blend(mode,g)::xs->let mode=match mode with Replace->Raster2.Composite.Replace|Alpha->Alpha|Add->Add|Multiply->Multiply in commands(commands(Raster2.Render_ir.Set_blend mode::acc)g)xs
  |Image node::xs->let width,height=Image.get_size node.image in let rect={Raster2.Render_ir.x=0.;y=0.;width=float width;height=float height}in
    let destination={Raster2.Render_ir.x=float node.x;y=float node.y;width=float width*.node.scale;height=float height*.node.scale}in
    let command=Raster2.Render_ir.Image{resource_id=Image.Private.identity node.image;source=rect;destination}in
    let transformed=node.angle<>0.||node.flip_x||node.center<>None in
    let acc=if transformed then
      let cx,cy=match node.center with None->destination.width*.0.5,destination.height*.0.5|Some(cx,cy)->float cx,float cy in
      let px=destination.x+.cx and py=destination.y+.cy and c=cos node.angle and s=sin node.angle and sx=if node.flip_x then -.1. else 1. in
      let xx=c*.sx and xy=(-.s)and yx=s*.sx and yy=c in
      Raster2.Render_ir.Pop_transform::command::Raster2.Render_ir.Push_transform{xx;xy;yx;yy;tx=px-.xx*.px-.xy*.py;ty=py-.yx*.px-.yy*.py}::acc
    else command::acc in
    commands acc xs
  |(Text _|View3d _|Region _)::xs->commands acc xs
 let rec text_regions scene=List.concat_map(function Region(x,y,w,h,f)->[x,y,w,h,f]|Group g|Translate(_,_,g)|Rotate(_,g)|Scale(_,_,g)|Clip(_,_,_,_,g)|Blend(_,g)->text_regions g|_->[])scene
 let rec image_resources scene=List.concat_map(function Image node->[Image.Private.identity node.image,Prismel_next_execution.Image(Image.Private.resource node.image)]|Group g|Translate(_,_,g)|Rotate(_,g)|Scale(_,_,g)|Clip(_,_,_,_,g)|Blend(_,g)->image_resources g|_->[])scene

 let text_image (node : text_node) =
   match node.rendered with
   | Some image -> image
   | None ->
       let image=match node.provided_font with
       |Some font->Result.get_ok(Font.cached_text?wrap:node.wrap~align:node.align font node.value(Font.Solid node.color))
       |None->let automatic=Result.get_ok(Font.Private.borrow_automatic?wrap:node.wrap~align:node.align~size:node.size node.value(Font.Solid node.color))in
         node.automatic<-Some automatic;Font.Private.automatic_image automatic in
       node.rendered <- Some image;
       image

 let rec materialize ~width ~height = function
   | [] -> []
   | Text node :: rest ->
       Image {image=text_image node;x=node.x;y=node.y;scale=1.;angle=0.;center=None;flip_x=false}
       :: materialize ~width ~height rest
   | View3d node :: rest -> View3d node :: materialize ~width ~height rest
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
       match Raster2.Render_ir.Private.create_owned (Array.of_list (List.rev (commands [] scene))) with
       | Error _ -> Error "invalid scene description"
       | Ok ir -> Ok (ir, image_resources scene)
     with
     | Failure message -> Error message
     | Invalid_argument message -> Error message

 let stage_native ~width ~height scene =
   match stage ~width ~height scene with Error _ as error->error|Ok(scene2,resources)->
   let lowered=ref[]and failure=ref None in
   let callbacks:Scene3_native_lowering.resources={
     texture=(fun _->Error Unsupported_texture);
     shadow=(fun _->Error Unsupported_shadow)}in
   let rec visit=function
     |[]->()|View3d node::rest->
       let viewport=Option.value node.viewport~default:(0,0,width,height)in
       (match Scene3_native_lowering.prepare~resources:callbacks~camera:node.camera
          ~viewport node.scene with Ok prepared->lowered:=prepared::!lowered
        |Error _->failure:=Some"native View3d lowering failed");visit rest
     |Group nodes::rest|Translate(_,_,nodes)::rest|Rotate(_,nodes)::rest
     |Scale(_,_,nodes)::rest|Clip(_,_,_,_,nodes)::rest|Blend(_,nodes)::rest->
       visit nodes;visit rest
     |_::rest->visit rest in
   visit scene;match!failure with Some message->Error message
   |None->Ok{scene2;resources;scene3=List.rev!lowered}

 let to_ir scene = Result.map fst (stage ~width:640 ~height:480 scene)
 let resources scene =
   match stage ~width:640 ~height:480 scene with
   | Ok (_, resources) -> resources
   | Error _ -> []

 let rec release scene =
   List.iter
     (function
       | Text node ->
           Option.iter Font.Private.release_automatic node.automatic;
           node.automatic <- None;
           node.rendered <- None
       | View3d node ->
           Option.iter Image.destroy node.rendered3d;
           node.rendered3d <- None
       | Group nodes | Translate (_, _, nodes) | Rotate (_, nodes)
       | Scale (_, _, nodes) | Clip (_, _, _, _, nodes) | Blend (_, nodes) ->
           release nodes
       | Clear _ | Primitive _ | Geometry _ | Debug_text _ | Image _ | Region _ -> ())
     scene
end
let render scene=(!Private.renderer) scene
