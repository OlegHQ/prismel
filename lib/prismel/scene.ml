type blend=Replace|Alpha|Add|Multiply
type primitive={points:(int*int)list;closed:bool;fill:Color.t option;stroke:Color.t option}
type text_node={x:int;y:int;value:string;color:Color.t;size:int;wrap:int option;align:Font.alignment;provided_font:Font.t option;mutable automatic:Font.Private.automatic option;mutable rendered:Image.t option}
and debug_text_node={x:int;y:int;value:string;color:Color.t}
and view3d_node={viewport:(int*int*int*int)option;camera:Camera.t;scene:Scene3.t;mutable rendered3d:Image.t option}
and image_node={image:Image.t;x:int;y:int;scale:float;angle:float;center:(int*int)option;flip_x:bool}
and display_list_node={segment:Scene_command.Display_list.t;
  resources:(int*Prismel_next_execution.resource)list}
and node=Group of t|Clear of Color.t|Primitive of primitive|Geometry of Scene_command.Render_ir.geometry|Text of text_node|Debug_text of debug_text_node|Image of image_node
 |Display_list of display_list_node
 |View3d of view3d_node|Region of int*int*int*int*bool|Layer_break
 |Translate of int*int*t|Rotate of float*t|Scale of float*float*t|Clip of int*int*int*int*t|Blend of blend*t
and t=node list
let empty=[]let one n=[n]let group x=Group x let clear c=Clear c
let default_color=Color.white
let rgba c=Int32.logor(Int32.shift_left(Int32.of_int c.Color.r)24)(Int32.logor(Int32.shift_left(Int32.of_int c.g)16)(Int32.logor(Int32.shift_left(Int32.of_int c.b)8)(Int32.of_int c.a)))
let point2 (x,y)={Scene_command.Path.x=float x;y=float y}
let geometry_of_mesh color (mesh:Scene_command.Path.mesh)=
  let vertices=Array.make(Array.length mesh.vertices*2)0. in
  Array.iteri(fun index (point:Scene_command.Path.point)->vertices.(index*2)<-point.x;vertices.(index*2+1)<-point.y)mesh.vertices;
  Geometry{Scene_command.Render_ir.vertices;indices=mesh.indices;color=rgba color}
let path_error operation=function
  |Ok mesh->mesh|Error Scene_command.Path.Empty_path->{Scene_command.Path.vertices=[||];indices=[||]}
  |Error _->invalid_arg operation
let stroke_path ?(width=1.) color path=geometry_of_mesh color(path_error"Scene path stroke"(Scene_command.Path.stroke~tolerance:0.25~width~cap:Scene_command.Path.Butt~join:Scene_command.Path.Miter~miter_limit:4. path))
type path_geometry_key={points:(int*int)list;closed:bool;stroke_width:int64;
  fill_rgba:int32 option;stroke_rgba:int32 option}
module Path_geometry_key=struct
  type t=path_geometry_key
  let equal left right=
    left.closed=right.closed&&left.stroke_width=right.stroke_width&&
    left.fill_rgba=right.fill_rgba&&left.stroke_rgba=right.stroke_rgba&&
    left.points=right.points
  let hash value=Hashtbl.hash(value.points,value.closed,value.stroke_width,
    value.fill_rgba,value.stroke_rgba)
end
module Path_geometry_table=Hashtbl.Make(Path_geometry_key)
type path_geometry_cache={table:node Path_geometry_table.t;
  order:path_geometry_key option array;mutable next:int}
let path_geometry_cache_capacity=256
let path_geometry_caches=Domain.DLS.new_key(fun()->
  {table=Path_geometry_table.create path_geometry_cache_capacity;
   order=Array.make path_geometry_cache_capacity None;next=0})
let path_geometry_cached key make=
  let cache=Domain.DLS.get path_geometry_caches in
  match Path_geometry_table.find_opt cache.table key with
  |Some value->value
  |None->
      let value=make()in
      Option.iter(Path_geometry_table.remove cache.table)cache.order.(cache.next);
      Path_geometry_table.add cache.table key value;
      cache.order.(cache.next)<-Some key;
      cache.next<-(cache.next+1)mod path_geometry_cache_capacity;
      value
let path_geometry_key ~points ~closed ~width ~fill ~stroke=
  {points;closed;stroke_width=Int64.bits_of_float width;
   fill_rgba=Option.map rgba fill;stroke_rgba=Option.map rgba stroke}
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
  let width=float(max 1 width)and points=[from_;to_]in
  let key=path_geometry_key~points~closed:false~width~fill:None~stroke:(Some color)in
  path_geometry_cached key(fun()->Geometry(Scene_command.Shape2.line ~from_
    ~to_ ~width:(int_of_float width) ~color:(rgba color)))
let polygon points ?fill ?stroke()=
  let fill=match fill,stroke with None,None->Some default_color|_->fill in
  let key=path_geometry_key~points~closed:true~width:1.~fill~stroke in
  path_geometry_cached key(fun()->Group(Array.to_list(Array.map(fun geometry->
    Geometry geometry)(Scene_command.Shape2.polygon points
      ~fill:(Option.map rgba fill) ~stroke:(Option.map rgba stroke)))))
let polyline points ?(color=default_color)()=
  let key=path_geometry_key~points~closed:false~width:1.~fill:None~stroke:(Some color)in
  path_geometry_cached key(fun()->Geometry(Scene_command.Shape2.polyline points
    ~color:(rgba color)))
let rect ~at:(x,y)~w~h ?fill ?stroke()=polygon[x,y;x+w,y;x+w,y+h;x,y+h]?fill?stroke()
let square ~at ~size ?fill ?stroke()=rect~at~w:size~h:size?fill?stroke()
let rounded_rect ~at:(x,y) ~w ~h ~radius ?fill ?stroke()=
  let radius=max 0(min radius(min(abs w)(abs h)/2))in
  let key=w,h,radius,Option.map rgba fill,Option.map rgba stroke in
  let geometry=rounded_cached key(fun()->
    Array.to_list(Array.map(fun geometry->Geometry geometry)
      (Scene_command.Shape2.rounded_rect ~width:w ~height:h ~radius
        ~fill:(Option.map rgba fill) ~stroke:(Option.map rgba stroke))))in
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
let ellipse ~at:(cx,cy as at) ~rx ~ry ?fill ?stroke()=
  let key=cx,cy,rx,ry,Option.map rgba fill,Option.map rgba stroke in
  ellipse_cached key(fun()->Group(Array.to_list(Array.map(fun geometry->
    Geometry geometry)(Scene_command.Shape2.ellipse ~center:at ~rx ~ry
      ~fill:(Option.map rgba fill) ~stroke:(Option.map rgba stroke)))))
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
        let x,y=values.(0)in {Scene_command.Path.x;y})in
      let commands=Array.of_list(Scene_command.Path.Move_to(point2 first)::List.map(fun p->Scene_command.Path.Line_to p)(List.tl sampled))in
      ignore rest;stroke_path color(Scene_command.Path.of_commands commands))
let path ?(steps=20)?(fill_rule=Path.Non_zero)?fill?stroke value=ignore fill_rule;Primitive{points=Path.points~steps value;closed=Path.is_closed value;fill;stroke}
let text ~at:(x,y) ?(color=default_color) ?(size=16) value=Text{x;y;value;color;size;wrap=None;align=Font.Left;provided_font=None;automatic=None;rendered=None}
let debug_text ~at:(x,y) ?(color=default_color) value=Debug_text{x;y;value;color}
let font_text font ~at:(x,y) ?(color=default_color) ?wrap ?(align=Font.Left) value=Text{x;y;value;color;size=Font.get_size font;wrap;align;provided_font=Some font;automatic=None;rendered=None}
let image image ~at:(x,y) ?(scale=1.) ?(angle=0.) ?center ?(flip_x=false)()=
  if not(Float.is_finite scale&&Float.is_finite angle)||scale<=0. then invalid_arg"Scene.image: invalid transform";
  Image{image;x;y;scale;angle;center;flip_x}
let view3d ?viewport ~camera scene=View3d{viewport;camera;scene;rendered3d=None}
let display_list ?(images=[]) segment=
  let images=Array.of_list images in
  let bound=Hashtbl.create(Array.length images)in
  Array.iter(fun(id,image)->
    if id<=0 then invalid_arg"Scene.display_list: resource ID must be positive";
    if Hashtbl.mem bound id then
      invalid_arg"Scene.display_list: duplicate resource ID";
    Hashtbl.add bound id image)images;
  Array.iter(function
    |Scene_command.Render_ir.Image image->
        if not(Hashtbl.mem bound image.resource_id)then
          invalid_arg"Scene.display_list: unbound image resource"
    |Glyphs glyphs->
        if not(Hashtbl.mem bound glyphs.resource_id)then
          invalid_arg"Scene.display_list: unbound glyph resource"
    |_->())(Scene_command.Render_ir.Private.commands_readonly
      (Scene_command.Display_list.render_ir segment));
  let resources=Array.fold_right(fun(id,image) rest->
    (id,Prismel_next_execution.Image(Image.Private.resource image))::rest)
    images[]in
  Display_list{segment;resources}
let text_input_region ~at:(x,y)~w~h ?(focused=false)()=Region(x,y,w,h,focused)
let translate x y nodes=Translate(x,y,nodes)let rotate a nodes=Rotate(a,nodes)let scale x y nodes=Scale(x,y,nodes)
let clip ~at:(x,y)~w~h nodes=Clip(x,y,w,h,nodes)let blend mode nodes=Blend(mode,nodes)
let geometry_uncached (p:primitive)=
 let n=List.length p.points in
 let vertices=Array.make(n*2)0. in
 let rec fill index=function
  |[]->()
  |(x,y)::rest->vertices.(index)<-float x;vertices.(index+1)<-float y;
      fill(index+2)rest in
 fill 0 p.points;
 let indices=if p.closed&&n>=3 then Array.init((n-2)*3)(fun i->let t=i/3 and k=i mod 3 in if k=0 then 0 else t+k)else if n=1 then[|0|]else Array.init(max 0((n-1)*2))(fun i->if i mod 2=0 then i/2 else i/2+1)in
 Scene_command.Render_ir.Geometry{vertices;indices;color=rgba(Option.value p.fill~default:(Option.value p.stroke~default:default_color))}
type primitive_cache={primitive_table:(primitive,Scene_command.Render_ir.command)Hashtbl.t;
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
 let layer_break=Layer_break
 type native_layer=
  |Scene2_layer of Scene_command.Render_ir.t*(int*Prismel_next_execution.resource)list
  |Scene2_segment of Scene_command.Display_list.t*
      (int*Prismel_next_execution.resource)list
  |Scene3_layer of Scene_execution.prepared_scene3
 type staged_native={clear:float*float*float*float;scene2:Scene_command.Render_ir.t;
   resources:(int*Prismel_next_execution.resource)list;
   scene3:Scene_execution.prepared_scene3 list;layers:native_layer list;
   retained:(string*int64)option}
 let native_segment_version segment resources=
   let mix stamp value=Int64.logxor(Int64.mul stamp 0x100000001b3L)
       (Int64.of_int value)in
   Int64.logand Int64.max_int(List.fold_left(fun stamp->function
     |_,Prismel_next_execution.Image image->
         mix(mix stamp(Prismel_next_resources.Image.identity image))
           (Prismel_next_resources.Image.generation image)
     |_,Text text->
         mix(mix stamp(Prismel_next_resources.Text.Private.identity text))
           (Prismel_next_resources.Text.generation text)
     |_,Canvas canvas->
         mix(mix stamp(Prismel_next_resources.Canvas.Private.identity canvas))
           (Prismel_next_resources.Canvas.generation canvas))
     (Scene_command.Display_list.version segment)resources)
 let renderer=ref(fun(_ : t)->())let install_renderer value=renderer:=value
 let text_image ?(density=1) (node : text_node) =
   match node.rendered with
   | Some image -> image
   | None ->
       let image=match node.provided_font with
       |Some font->Result.get_ok(Font.cached_text?wrap:node.wrap~align:node.align~density font node.value(Font.Solid node.color))
       |None->let automatic=Result.get_ok(Font.Private.borrow_automatic?wrap:node.wrap~align:node.align~density~size:node.size node.value(Font.Solid node.color))in
         node.automatic<-Some automatic;Font.Private.automatic_image automatic in
       node.rendered <- Some image;
       image

 type command_builder={mutable values:Scene_command.Render_ir.command array;
   mutable length:int}
 let command_builder()={values=Array.make 32(Scene_command.Render_ir.Clear 0l);length=0}
 let emit builder command=
   if builder.length=Array.length builder.values then(
     let values=Array.make(2*builder.length)(Scene_command.Render_ir.Clear 0l)in
     Array.blit builder.values 0 values 0 builder.length;builder.values<-values);
   Array.unsafe_set builder.values builder.length command;
   builder.length<-builder.length+1
 let image_command builder image x y scale angle center flip_x=
  let width,height=Image.get_size image in let rect={Scene_command.Render_ir.x=0.;y=0.;width=float width;height=float height}in
    let destination={Scene_command.Render_ir.x=float x;y=float y;width=float width*.scale;height=float height*.scale}in
    let command=Scene_command.Render_ir.Image{resource_id=Image.Private.identity image;source=rect;destination}in
    let transformed=angle<>0.||flip_x||center<>None in
    if transformed then(
      let cx,cy=match center with None->destination.width*.0.5,destination.height*.0.5|Some(cx,cy)->float cx,float cy in
      let px=destination.x+.cx and py=destination.y+.cy and c=cos angle and s=sin angle and sx=if flip_x then -.1. else 1. in
      let xx=c*.sx and xy=(-.s)and yx=s*.sx and yy=c in
      emit builder(Scene_command.Render_ir.Push_transform{xx;xy;yx;yy;tx=px-.xx*.px-.xy*.py;ty=py-.yx*.px-.yy*.py});
      emit builder command;emit builder Scene_command.Render_ir.Pop_transform)
    else emit builder command
 let commands ?(density=1) scene=
  let builder=command_builder()in
  let rec nodes=function
   |[]->()
   |Clear c::xs->emit builder(Scene_command.Render_ir.Clear(rgba c));nodes xs
   |Primitive p::xs->emit builder(geometry p);nodes xs
   |Geometry g::xs->emit builder(Scene_command.Render_ir.Geometry g);nodes xs
   |Debug_text node::xs->emit builder(Scene_command.Render_ir.Debug_text{x=float node.x;y=float node.y;text=node.value;color=rgba node.color});nodes xs
   |Display_list node::xs->
       Array.iter (emit builder) (Scene_command.Render_ir.Private.commands_readonly
         (Scene_command.Display_list.render_ir node.segment));
       nodes xs
   |Image node::xs->image_command builder node.image node.x node.y node.scale node.angle node.center node.flip_x;nodes xs
   |Text node::xs->
       let scale=1./.float(max 1 density)in
       image_command builder(text_image~density node)node.x node.y scale 0. None false;nodes xs
   |Group g::xs->nodes g;nodes xs
   |Translate(x,y,g)::xs->emit builder(Scene_command.Render_ir.Push_transform{xx=1.;xy=0.;yx=0.;yy=1.;tx=float x;ty=float y});nodes g;emit builder Scene_command.Render_ir.Pop_transform;nodes xs
   |Scale(x,y,g)::xs->emit builder(Scene_command.Render_ir.Push_transform{xx=x;xy=0.;yx=0.;yy=y;tx=0.;ty=0.});nodes g;emit builder Scene_command.Render_ir.Pop_transform;nodes xs
   |Rotate(a,g)::xs->let c=cos a and s=sin a in emit builder(Scene_command.Render_ir.Push_transform{xx=c;xy=s;yx=(-.s);yy=c;tx=0.;ty=0.});nodes g;emit builder Scene_command.Render_ir.Pop_transform;nodes xs
   |Clip(x,y,w,h,g)::xs->emit builder(Scene_command.Render_ir.Push_clip{x=float x;y=float y;width=float w;height=float h});nodes g;emit builder Scene_command.Render_ir.Pop_clip;nodes xs
   |Blend(mode,g)::xs->let mode=match mode with Replace->Scene_command.Render_ir.Replace|Alpha->Alpha|Add->Add|Multiply->Multiply in emit builder(Scene_command.Render_ir.Set_blend mode);nodes g;emit builder(Scene_command.Render_ir.Set_blend Scene_command.Render_ir.Alpha);nodes xs
   |(View3d _|Region _|Layer_break)::xs->nodes xs in
  nodes scene;Array.sub builder.values 0 builder.length
 let rec text_regions scene=List.concat_map(function Region(x,y,w,h,f)->[x,y,w,h,f]|Group g|Translate(_,_,g)|Rotate(_,g)|Scale(_,_,g)|Clip(_,_,_,_,g)|Blend(_,g)->text_regions g|_->[])scene
 let image_resources ?(density=1) scene=
   let rec nodes acc=function
    |[]->acc
    |Image node::rest->nodes((Image.Private.identity node.image,Prismel_next_execution.Image(Image.Private.resource node.image))::acc)rest
    |Text node::rest->let image=text_image ~density node in nodes((Image.Private.identity image,Prismel_next_execution.Image(Image.Private.resource image))::acc)rest
    |Display_list node::rest->nodes(List.rev_append node.resources acc)rest
    |Group nested::rest|Translate(_,_,nested)::rest|Rotate(_,nested)::rest
    |Scale(_,_,nested)::rest|Clip(_,_,_,_,nested)::rest|Blend(_,nested)::rest->
        nodes(nodes acc nested)rest
    |_::rest->nodes acc rest in
   List.rev(nodes[]scene)

 let stage_materialized ?(density=1) scene =
   match scene with
   |[Display_list node]->Ok(Scene_command.Display_list.render_ir node.segment,
      node.resources)
   |_->
      try
        match Scene_command.Render_ir.Private.create_owned
          (commands ~density scene)with
        |Error _->Error "invalid scene description"
        |Ok ir->Ok(ir,image_resources ~density scene)
      with
      |Failure message->Error message
      |Invalid_argument message->Error message

 let stage ?(density=1) ~width ~height scene =
   if width <= 0 || height <= 0 then Error "invalid scene extent"
   else
     try stage_materialized ~density scene with
     |Failure message->Error message
     |Invalid_argument message->Error message

 let unpack_clear color=
   let channel shift=Int32.(to_int(logand(shift_right_logical color shift)0xffl))in
   float(channel 24)/.255.,float(channel 16)/.255.,
   float(channel 8)/.255.,float(channel 0)/.255.

 type layer_item=Two_node of node|Segment_node of display_list_node
   |Three_node of view3d_node|Break
 let ordered_items scene=
   let rec add wrap direct acc nodes=List.fold_left(fun acc node->match node with
     |View3d view->Three_node view::acc
     |Display_list node when direct->Segment_node node::acc
     |Layer_break->Break::acc
     |Group nodes->add wrap direct acc nodes
     |Translate(x,y,nodes)->add(fun node->wrap(Translate(x,y,[node])))false acc nodes
     |Rotate(angle,nodes)->add(fun node->wrap(Rotate(angle,[node])))false acc nodes
     |Scale(x,y,nodes)->add(fun node->wrap(Scale(x,y,[node])))false acc nodes
     |Clip(x,y,w,h,nodes)->add(fun node->wrap(Clip(x,y,w,h,[node])))false acc nodes
     |Blend(mode,nodes)->add(fun node->wrap(Blend(mode,[node])))false acc nodes
     |node->Two_node(wrap node)::acc)acc nodes in
   List.rev(add Fun.id true[]scene)

 let grouped_items items=
   let flush nodes acc=if nodes=[]then acc else `Two(List.rev nodes)::acc in
   let rec loop nodes acc=function
     |[]->List.rev(flush nodes acc)
     |Two_node node::rest->loop(node::nodes)acc rest
     |Segment_node node::rest->loop[](`Segment node::flush nodes acc)rest
     |Three_node view::rest->loop[](`Three view::flush nodes acc)rest
     |Break::rest->loop[](flush nodes acc)rest in
   loop[][]items

 let rec same_native_scene left right=
   left==right||match left,right with
   |[],[]->true
   |left::lefts,right::rights->same_native_node left right&&
       same_native_scene lefts rights
   |_ ->false
 and same_native_node left right=
   left==right||match left,right with
   |Clear left,Clear right->left=right
   |Primitive left,Primitive right->left==right||left=right
   |Geometry left,Geometry right->left==right||left=right
   |Debug_text left,Debug_text right->left=right
   |Display_list left,Display_list right->
       left.segment==right.segment&&left.resources==right.resources
   |Image left,Image right->left.image==right.image&&left.x=right.x&&
       left.y=right.y&&left.scale=right.scale&&left.angle=right.angle&&
       left.center=right.center&&left.flip_x=right.flip_x
   |Text left,Text right->left.x=right.x&&left.y=right.y&&
       left.value=right.value&&left.color=right.color&&left.size=right.size&&
       left.wrap=right.wrap&&left.align=right.align&&
       left.provided_font==right.provided_font
   |Group left,Group right->same_native_scene left right
   |Translate(lx,ly,left),Translate(rx,ry,right)->lx=rx&&ly=ry&&
       same_native_scene left right
   |Rotate(la,left),Rotate(ra,right)->la=ra&&same_native_scene left right
   |Scale(lx,ly,left),Scale(rx,ry,right)->lx=rx&&ly=ry&&
       same_native_scene left right
   |Clip(lx,ly,lw,lh,left),Clip(rx,ry,rw,rh,right)->
       lx=rx&&ly=ry&&lw=rw&&lh=rh&&same_native_scene left right
   |Blend(lm,left),Blend(rm,right)->lm=rm&&same_native_scene left right
   |View3d left,View3d right->left.viewport=right.viewport&&
       left.camera==right.camera&&left.scene==right.scene
   |Region(lx,ly,lw,lh,lf),Region(rx,ry,rw,rh,rf)->
       lx=rx&&ly=ry&&lw=rw&&lh=rh&&lf=rf
   |Layer_break,Layer_break->true
   |_ ->false

 type scene2_layer_cache_entry={layer_scene:t;layer_density:int;
   layer_ir:Scene_command.Render_ir.t;
   layer_bytes:int}
 let scene2_layer_cache_capacity=64
 let scene2_layer_cache_byte_capacity=64*1024*1024
 let scene2_layer_caches=Domain.DLS.new_key(fun()->ref[])
 let scene2_layer_bytes ir=Array.fold_left(fun total->function
   |Scene_command.Render_ir.Geometry geometry->total+
       Array.length geometry.vertices*(Sys.word_size/8)+
       Array.length geometry.indices*(Sys.word_size/8)
   |_->total+32)0(Scene_command.Render_ir.Private.commands_readonly ir)
 let trim_scene2_layer_cache values=
   let rec loop count bytes kept=function
   |[]->List.rev kept
   |entry::rest when count<scene2_layer_cache_capacity&&
       entry.layer_bytes<=scene2_layer_cache_byte_capacity-bytes->
       loop(count+1)(bytes+entry.layer_bytes)(entry::kept)rest
   |_::rest->loop count bytes kept rest in
   loop 0 0[]values
 let stage_scene2_layer ~density nodes=
   let cache=Domain.DLS.get scene2_layer_caches in
   match List.find_opt(fun entry->entry.layer_density=density&&
       same_native_scene entry.layer_scene nodes)
       !cache with
   |Some entry->Ok(entry.layer_ir,image_resources~density nodes)
   |None->
       match stage_materialized ~density nodes with
       |Error _ as error->error
       |Ok(ir,_)as result->
           let entry={layer_scene=nodes;layer_density=density;layer_ir=ir;
             layer_bytes=scene2_layer_bytes ir}in
           cache:=entry::List.filter(fun old->
             old.layer_density<>density||
             not(same_native_scene old.layer_scene nodes))!cache;
           cache:=trim_scene2_layer_cache!cache;
           result

 let empty_ir=Result.get_ok(Scene_command.Render_ir.Private.create_owned[||])
 let stage_native_uncached_with ~aggregate ?(density=1) ~width ~height scene =
   if width<=0||height<=0 then Error "invalid scene extent"else
   let grouped=grouped_items(ordered_items scene)in
   let materialized=match grouped with
   |[`Two _]->stage_materialized ~density scene
   |_->if aggregate then stage_materialized ~density scene else Ok(empty_ir,[])in
   match materialized with Error _ as error->error
   |Ok(scene2,resources)->
   let failure=ref None in
   let callbacks:Scene3_native_lowering.resources={
     texture=(fun value->let levels=Texture.Private.levels value.Scene3.value|>Array.map(fun(w,h,pixels)->let bytes=Bytes.create(w*h*4)in Array.iteri(fun index color->Bytes.set_int32_be bytes(index*4)(Int32.of_int((color.Color.r lsl 24)lor(color.g lsl 16)lor(color.b lsl 8)lor color.a)))pixels;{Scene_execution.width=w;height=h;bytes})in let address=function Texture.Clamp->Ogpu.Types.Clamp_to_edge|Repeat->Repeat|Mirror->Mirror_repeat in let min_filter,mag_filter,mip_filter=match value.filter with Texture.Nearest->Ogpu.Types.Nearest,Ogpu.Types.Nearest,Ogpu.Types.No_mip|Texture.Bilinear->Ogpu.Types.Linear,Ogpu.Types.Linear,Ogpu.Types.No_mip|Texture.Trilinear->Ogpu.Types.Linear,Ogpu.Types.Linear,Ogpu.Types.Linear_mip in let sampler:Ogpu.Types.sampler_descriptor={label=Some"scene3-texture";min_filter;mag_filter;mip_filter;address_u=address value.wrap_u;address_v=address value.wrap_v;lod_min=0.;lod_max=float(Array.length levels-1);max_anisotropy=1}in Ok{Scene_execution.key=Digest.to_hex(Digest.string(Marshal.to_string levels[]));levels;sampler});
     shadow=(fun value->let source=Shadow3.Private.snapshot value in let matrix=Array.init 16(fun index->Mat4.get source.view_projection~row:(index/4)~column:(index mod 4))in let snapshot:Scene_execution.shadow_snapshot={width=source.width;height=source.height;depths=source.depths;matrix;bias={constant=source.bias;slope=source.normal_bias};kernel=(match source.filter with Hard->Tap1|Pcf_3x3->Tap9|Pcf_5x5->Tap25);strength=source.strength}in match Scene_execution.shadow_resource~key:(Digest.to_hex(Digest.string(Marshal.to_string snapshot[])))snapshot with Error _->Error Unsupported_shadow|Ok resource->Ok{Scene_execution.key=resource.texture.key;buffer=resource.parameters;texture=resource.texture})}in
   let layers=match grouped with
   |[`Two _]->[Scene2_layer(scene2,resources)]
   |_->List.filter_map(fun item->if!failure<>None then None else match item with
       |`Two nodes->(match stage_scene2_layer ~density nodes with
         |Ok(ir,resources)->Some(Scene2_layer(ir,resources))
         |Error message->failure:=Some message;None)
       |`Segment node->Some(Scene2_segment(node.segment,node.resources))
       |`Three node->
         let viewport=Option.value node.viewport~default:(0,0,width,height)in
         (match Scene3_native_lowering.prepare~resources:callbacks~camera:node.camera
            ~viewport node.scene with
          |Ok prepared->Some(Scene3_layer prepared)
          |Error _->failure:=Some"native View3d lowering failed";None))grouped in
   let clear=ref(0.,0.,0.,0.)and seen_draw=ref false in
   List.iter(function
     |Scene3_layer _->seen_draw:=true
     |Scene2_segment(segment,_)->
         Array.iter(function
           |Scene_command.Render_ir.Clear color->
               if!seen_draw then failure:=Some"native Clear after drawing is unsupported"
               else clear:=unpack_clear color
           |Geometry _|Debug_text _|Image _|Glyphs _->seen_draw:=true
           |Set_blend _|Push_clip _|Pop_clip|Push_transform _|Pop_transform->())
           (Scene_command.Render_ir.Private.commands_readonly
             (Scene_command.Display_list.render_ir segment))
     |Scene2_layer(ir,_)->Array.iter(function
       |Scene_command.Render_ir.Clear color->
          if!seen_draw then failure:=Some"native Clear after drawing is unsupported"
          else clear:=unpack_clear color
       |Geometry _|Debug_text _|Image _|Glyphs _->seen_draw:=true
       |Set_blend _|Push_clip _|Pop_clip|Push_transform _|Pop_transform->())
       (Scene_command.Render_ir.Private.commands_readonly ir))layers;
   match!failure with Some message->Error message|None->
   let scene3=List.filter_map(function Scene3_layer prepared->Some prepared|_->None)layers in
   let retained=match layers with
   |[Scene2_segment(segment,resources)]->Some
       ("scene2-segment:"^Int64.to_string(Scene_command.Display_list.id segment),
        native_segment_version segment resources)
   |_->None in
   Ok{clear= !clear;scene2;resources;scene3;layers;retained}

 let stage_native_uncached ?density ~width ~height scene=
   stage_native_uncached_with ~aggregate:true ?density ~width ~height scene
 let stage_native_render_uncached ?density ~width ~height scene=
   stage_native_uncached_with ~aggregate:false ?density ~width ~height scene

 type native_stage_cache_entry={cached_scene:t;cached_density:int;
   cached_width:int;cached_height:int;cached_resource_stamp:int;
   cached_aggregate:bool;
   cached_stage:staged_native}
 let native_stage_cache_capacity=16
 let native_stage_cache_byte_capacity=256*1024*1024
 let native_stage_caches=Domain.DLS.new_key(fun()->ref[])
 let native_stage_hits=ref 0 and native_stage_misses=ref 0
 let native_stage_hit_bytes=ref 0.
 let native_stage_profile_enabled=
   Sys.getenv_opt"PRISMEL_RENDERER_PHASE_PROFILE"=Some"1"
 let ()=at_exit(fun()->if native_stage_profile_enabled
   then Printf.eprintf"native-stage-cache hits %d misses %d hit-bytes %.1f\n%!"
     !native_stage_hits !native_stage_misses
     (if !native_stage_hits=0 then 0. else
       !native_stage_hit_bytes/.float!native_stage_hits))
 let next_native_stage_identity=ref 0L
 let native_stage_bytes stage=List.fold_left(fun total->function
   |Scene2_segment(segment,_)->total+Scene_command.Display_list.source_bytes segment
   |Scene2_layer(ir,_)->total+Array.fold_left(fun total->function
       |Scene_command.Render_ir.Geometry geometry->total+
           Array.length geometry.vertices*(Sys.word_size/8)+
           Array.length geometry.indices*(Sys.word_size/8)
       |_->total+32)0(Scene_command.Render_ir.Private.commands_readonly ir)
   |Scene3_layer prepared->total+Array.fold_left(fun total entry->
       total+Bytes.length entry.Scene_execution.draw.mesh.vertices+
       Bytes.length entry.draw.mesh.indices+
       Option.fold~none:0~some:Bytes.length entry.draw.state.transform_uniforms)
       0 prepared.Scene_execution.entries)0 stage.layers
 let trim_native_stage_cache values=
   let rec loop count bytes kept=function
   |[]->List.rev kept
   |entry::rest->
       let size=native_stage_bytes entry.cached_stage in
       if count<native_stage_cache_capacity&&
          size<=native_stage_cache_byte_capacity-bytes
       then loop(count+1)(bytes+size)(entry::kept)rest
       else loop count bytes kept rest in
   loop 0 0[]values
 let rec resource_stamp_loop stamp=function
  |[]->stamp
  |(id,Prismel_next_execution.Image image)::rest->
      resource_stamp_loop
        ((((stamp*65599)lxor id)*65599 lxor
          Prismel_next_resources.Image.identity image)*65599 lxor
          Prismel_next_resources.Image.generation image)rest
  |(id,Text text)::rest->resource_stamp_loop
      ((((stamp*65599)lxor id)*65599 lxor
        Prismel_next_resources.Text.Private.identity text)*65599 lxor
        Prismel_next_resources.Text.generation text)rest
  |(id,Canvas canvas)::rest->resource_stamp_loop
      ((((stamp*65599)lxor id)*65599 lxor
        Prismel_next_resources.Canvas.Private.identity canvas)*65599 lxor
        Prismel_next_resources.Canvas.generation canvas)rest
 let resource_stamp resources=resource_stamp_loop 0x345678 resources
 let rec find_native_stage aggregate scene density width height=function
  |[]->None
  |entry::rest->
      if entry.cached_aggregate=aggregate&&
         same_native_scene entry.cached_scene scene&&
         entry.cached_density=density&&
         entry.cached_width=width&&entry.cached_height=height&&
         entry.cached_resource_stamp=resource_stamp entry.cached_stage.resources
      then Some entry else
        find_native_stage aggregate scene density width height rest
 let native_scene_cacheable scene=
   let rec nodes=function
    |[]->true
    |View3d view::rest->Scene3.Private.cacheable view.scene&&nodes rest
    |Group nested::rest|Translate(_,_,nested)::rest|Rotate(_,nested)::rest
    |Scale(_,_,nested)::rest|Clip(_,_,_,_,nested)::rest|Blend(_,nested)::rest->
        nodes nested&&nodes rest
    |Display_list _::rest|Region _::rest|Layer_break::rest|Clear _::rest
    |Primitive _::rest|Geometry _::rest|Text _::rest|Debug_text _::rest
    |Image _::rest->nodes rest in
   nodes scene
 let stage_native_internal ~aggregate ?(density=1) ~width ~height scene =
   let profile=native_stage_profile_enabled in
   let before=if profile then Gc.allocated_bytes()else 0. in
   let cacheable=match scene with
   |[Clear _;View3d view]->Scene3.Private.cacheable view.scene
   |_->native_scene_cacheable scene in
   let uncached=if aggregate then stage_native_uncached
     else stage_native_render_uncached in
   if not cacheable then uncached~density~width~height scene else
   let cache=Domain.DLS.get native_stage_caches in
   match find_native_stage aggregate scene density width height !cache with
   |Some entry->
       if profile then begin
         incr native_stage_hits;
         native_stage_hit_bytes:= !native_stage_hit_bytes+.
           Gc.allocated_bytes()-.before
       end;
       Ok entry.cached_stage
   |None->
       if profile then incr native_stage_misses;
       match uncached~density~width~height scene with
       |Error _ as error->error
       |Ok stage->
           let stage=match stage.retained with
           |Some _->stage
           |None->
               next_native_stage_identity:=Int64.succ!next_native_stage_identity;
               {stage with retained=Some
                 ("scene-stage:"^Int64.to_string!next_native_stage_identity,1L)}in
           let stamp=resource_stamp stage.resources in
           cache:=List.filter(fun entry->not(same_native_scene entry.cached_scene scene&&
             entry.cached_aggregate=aggregate&&
             entry.cached_density=density&&entry.cached_width=width&&
             entry.cached_height=height))!cache;
           cache:={cached_scene=scene;cached_density=density;cached_width=width;
             cached_height=height;cached_resource_stamp=stamp;
             cached_aggregate=aggregate;
             cached_stage=stage}::!cache;
           cache:=trim_native_stage_cache!cache;
           Ok stage

 let stage_native ?density ~width ~height scene=
   stage_native_internal ~aggregate:true ?density ~width ~height scene
 let stage_native_render ?density ~width ~height scene=
   stage_native_internal ~aggregate:false ?density ~width ~height scene

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
       | Clear _ | Primitive _ | Geometry _ | Debug_text _ | Image _
       | Display_list _ | Region _
       | Layer_break -> ())
     scene
end
let render scene=(!Private.renderer) scene
