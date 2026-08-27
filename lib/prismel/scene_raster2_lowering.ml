type unsupported = Text | Image | View3d | Metadata | Image_transform
type error = Unsupported of unsupported | Resource_failure | Invalid_path of Raster2.Path.error | Invalid_ir of Raster2.Render_ir.error
type image_snapshot={resource_id:int;generation:int64;surface:Raster2.Surface.t}
type text_snapshot={resource_id:int;generation:int64;density:int;atlas:Raster2.Consumer.glyph_atlas;glyphs:Raster2.Render_ir.glyph array}
type resources={image:Image.t->(image_snapshot,error)result;font_text:Font.t->string->int option->Font.alignment option->(text_snapshot,error)result;system_text:int->string->(text_snapshot,error)result;debug_text:string->(text_snapshot,error)result}
type identity=Image_identity of int64|Text_identity of{generation:int64;density:int}
type resource_entry={id:int;identity:identity;value:Raster2.Consumer.resource}
type plan={ir:Raster2.Render_ir.t;resources:resource_entry array}
type resolved=Resolved_image of image_snapshot|Resolved_text of text_snapshot

let packed (color : Color.t) =
  Int32.(logor (shift_left (of_int color.r) 24)
    (logor (shift_left (of_int color.g) 16)
      (logor (shift_left (of_int color.b) 8) (of_int color.a))))
let color = function Some value -> packed value | None -> packed Color.white
let geometry vertices indices color =
  Raster2.Render_ir.Geometry { vertices; indices; color }
let quad x0 y0 x1 y1 color = geometry
  [|float x0;float y0;float x1;float y0;float x1;float y1;float x0;float y1|]
  [|0;1;2;0;2;3|] color
let line (x0,y0) (x1,y1) width color =
  let dx=float(x1-x0)and dy=float(y1-y0)in let length=sqrt(dx*.dx+.dy*.dy)in
  if length=0. then quad x0 y0 (x0+width) (y0+width) color else
  let half=float width*.0.5 and nx=(-.dy/.length)and ny=dx/.length in
  geometry[|float x0+.nx*.half;float y0+.ny*.half;float x1+.nx*.half;float y1+.ny*.half;
    float x1-.nx*.half;float y1-.ny*.half;float x0-.nx*.half;float y0-.ny*.half|][|0;1;2;0;2;3|]color
let blend = function Scene_description.Replace->Raster2.Composite.Copy|Alpha->Source_over|Add->Add|Multiply->Multiply
let point (x,y)={Raster2.Path.x=float x;y=float y}
let path_of_points ~close points=match points with[]->Raster2.Path.of_commands[||]|first::rest->
  let commands=Raster2.Path.Move_to(point first)::List.map(fun p->Raster2.Path.Line_to(point p))rest in
  Raster2.Path.of_commands(Array.of_list(if close then commands@[Raster2.Path.Close]else commands))
let mesh_command (mesh:Raster2.Path.mesh) color=
  let vertices=Array.make(Array.length mesh.vertices*2)0. in
  Array.iteri(fun i(p:Raster2.Path.point)->vertices.(2*i)<-p.x;vertices.(2*i+1)<-p.y)mesh.vertices;
  geometry vertices mesh.indices color
let circle_points ~cx ~cy ~rx ~ry ~start ~finish =
  let span=finish-.start in
  let segments=max 8(min 256(int_of_float(ceil(abs_float span*.float(max 1(max rx ry))/.4.))))in
  List.init(segments+1)(fun i->let angle=start+.span*.float i/.float segments in
    (int_of_float(Float.round(float cx+.cos angle*.float rx)),int_of_float(Float.round(float cy+.sin angle*.float ry))))
let rounded_rect_path x y w h radius =
  let r=max 0(min radius(min(abs w)(abs h)/2))in
  let points=circle_points~cx:(x+w-r)~cy:(y+r)~rx:r~ry:r~start:(-.Float.pi/.2.)~finish:0.
    @circle_points~cx:(x+w-r)~cy:(y+h-r)~rx:r~ry:r~start:0.~finish:(Float.pi/.2.)
    @circle_points~cx:(x+r)~cy:(y+h-r)~rx:r~ry:r~start:(Float.pi/.2.)~finish:Float.pi
    @circle_points~cx:(x+r)~cy:(y+r)~rx:r~ry:r~start:Float.pi~finish:(Float.pi*.1.5)in
  path_of_points~close:true points

let lower_internal ~resource_handler scene =
  let commands=ref[]and failure=ref None in
  let emit value=commands:=value::!commands and reject value=if !failure=None then failure:=Some(Unsupported value)in
  let path_error value=if !failure=None then failure:=Some(Invalid_path value)in
  let emit_fill path rule color=match Raster2.Path.tessellate~tolerance:0.25~fill_rule:rule path with Ok mesh->if Array.length mesh.indices>0 then emit(mesh_command mesh(packed color))|Error Raster2.Path.Empty_path->()|Error error->path_error error in
  let emit_stroke path color=match Raster2.Path.stroke~tolerance:0.25~width:1.~cap:Raster2.Path.Butt~join:Miter~miter_limit:4. path with Ok mesh->if Array.length mesh.indices>0 then emit(mesh_command mesh(packed color))|Error Raster2.Path.Empty_path->()|Error error->path_error error in
  let styled_path style rule path=Option.iter(fun c->emit_fill path rule c)style.Scene_description.fill;Option.iter(fun c->emit_stroke path c)style.stroke in
  let rec nodes active_blend values=List.iter(node active_blend)values
  and styled style make = Option.iter(fun fill->emit(make(packed fill)))style.Scene_description.fill
  and node active_blend = function
    | Scene_description.Clear value->emit(Raster2.Render_ir.Clear(packed value))
    | Point((x,y),value)->emit(quad x y(x+1)(y+1)(color value))
    | Line(a,b,value,width)->emit(line a b width(color value))
    | Rect((x,y),w,h,None,style)->styled style(fun c->quad x y(x+w)(y+h)c);Option.iter(fun c->emit_stroke(path_of_points~close:true[(x,y);(x+w,y);(x+w,y+h);(x,y+h)])c)style.stroke
    | Rect((x,y),w,h,Some radius,style)->styled_path style Raster2.Path.Non_zero(rounded_rect_path x y w h radius)
    | Triangle(a,b,c,style)->styled_path style Raster2.Path.Non_zero(path_of_points~close:true[a;b;c])
    | Circle((cx,cy),radius,style)->styled_path style Raster2.Path.Non_zero(path_of_points~close:true(circle_points~cx~cy~rx:radius~ry:radius~start:0.~finish:(2.*.Float.pi)))
    | Ellipse((cx,cy),rx,ry,style)->styled_path style Raster2.Path.Non_zero(path_of_points~close:true(circle_points~cx~cy~rx~ry~start:0.~finish:(2.*.Float.pi)))
    | Polygon(points,style)->styled_path style Raster2.Path.Non_zero(path_of_points~close:true points)
    | Polyline(points,value)->emit_stroke(path_of_points~close:false points)(Option.value value~default:Color.white)
    | Arc((cx,cy),radius,start,finish,value)->emit_stroke(path_of_points~close:false(circle_points~cx~cy~rx:radius~ry:radius~start~finish))(Option.value value~default:Color.white)
    | Pie((cx,cy),radius,start,finish,style)->styled_path style Raster2.Path.Non_zero(path_of_points~close:true((cx,cy)::circle_points~cx~cy~rx:radius~ry:radius~start~finish))
    | Bezier(points,steps,value)->
        let controls=Array.of_list points and steps=max 1 steps in
        let sampled=if Array.length controls=0 then[]else List.init(steps+1)(fun sample->
          let t=float sample/.float steps and xs=Array.map(fun(x,_)->float x)controls and ys=Array.map(fun(_,y)->float y)controls in
          for level=Array.length controls-1 downto 1 do for i=0 to level-1 do
            xs.(i)<-xs.(i)+.t*.(xs.(i+1)-.xs.(i));ys.(i)<-ys.(i)+.t*.(ys.(i+1)-.ys.(i))done done;
          (int_of_float(Float.round xs.(0)),int_of_float(Float.round ys.(0))))in
        emit_stroke(path_of_points~close:false sampled)(Option.value value~default:Color.white)
    | Path(value,steps,fill_rule,style)->
        let contours=Path.contours~steps value in
        let commands=List.concat_map(fun contour->match contour with[]->[]|first::rest->Raster2.Path.Move_to(point first)::List.map(fun p->Raster2.Path.Line_to(point p))rest@[Raster2.Path.Close])contours in
        let rule=match fill_rule with Path.Even_odd->Raster2.Path.Even_odd|Non_zero->Non_zero in
        styled_path style rule(Raster2.Path.of_commands(Array.of_list commands))
    | Group children->nodes active_blend children
    | Translate(x,y,children)->emit(Push_transform{xx=1.;xy=0.;yx=0.;yy=1.;tx=float x;ty=float y});nodes active_blend children;emit Pop_transform
    | Rotate(angle,children)->let c=cos angle and s=sin angle in emit(Push_transform{xx=c;xy=(-.s);yx=s;yy=c;tx=0.;ty=0.});nodes active_blend children;emit Pop_transform
    | Scale(x,y,children)->emit(Push_transform{xx=x;xy=0.;yx=0.;yy=y;tx=0.;ty=0.});nodes active_blend children;emit Pop_transform
    | Clip((x,y),w,h,children)->emit(Push_clip{x=float x;y=float y;width=float w;height=float h});nodes active_blend children;emit Pop_clip
    | Blend(value,children)->let nested=blend value in emit(Set_blend nested);nodes nested children;emit(Set_blend active_blend)
    | (Text _|Debug_text _|Font_text _|Image _)as value->resource_handler emit reject value
    | View3d _->reject View3d
    | Text_input_region _->reject Metadata
  in nodes Raster2.Composite.Source_over scene;match !failure with Some error->Error error|None->
  match Raster2.Render_ir.create(Array.of_list(List.rev !commands))with Ok value->Ok value|Error error->Error(Invalid_ir error)

let lower scene=lower_internal~resource_handler:(fun _ reject->function Image _->reject Image|_->reject Text)scene

let lower_with_resources callbacks scene =
  let resolved=ref[]and failure=ref None in
  let add result=match result with Ok value->resolved:=value::!resolved|Error error->if !failure=None then failure:=Some error in
  let rec preflight values=if !failure<>None then()else match values with
    | []->()
    | Scene_description.Image(value,_,scale,angle,_,_)::rest->
        if not (Float.is_finite (Option.value scale ~default:1.) &&
            Float.is_finite (Option.value angle ~default:0.)) then
          failure:=Some(Unsupported Image_transform)
        else add(Result.map(fun value->Resolved_image value)(callbacks.image value));preflight rest
    | Text(_,value,_,size)::rest->if value<>""then add(Result.map(fun value->Resolved_text value)(callbacks.system_text size value));preflight rest
    | Debug_text(_,value,_)::rest->if value<>""then add(Result.map(fun value->Resolved_text value)(callbacks.debug_text value));preflight rest
    | Font_text(font,_,value,_,wrap,align)::rest->if value<>""then add(Result.map(fun value->Resolved_text value)(callbacks.font_text font value wrap align));preflight rest
    | Group children::rest|Translate(_,_,children)::rest|Rotate(_,children)::rest|Scale(_,_,children)::rest|Clip(_,_,_,children)::rest|Blend(_,children)::rest->preflight children;preflight rest
    | _::rest->preflight rest in
  preflight scene;match !failure with Some error->Error error|None->
  let pending=ref(List.rev !resolved)and entries=ref[]in
  let register entry=match List.find_opt(fun value->value.id=entry.id)!entries with None->entries:=entry::!entries|Some value->if value.identity<>entry.identity then failure:=Some Resource_failure in
  let take()=match !pending with value::rest->pending:=rest;Some value|[]->None in
  let handler emit reject=function
    | Scene_description.Image(_, (x,y),scale,angle,center,flip)->begin match take()with Some(Resolved_image value)->
        let width=Raster2.Surface.width value.surface and height=Raster2.Surface.height value.surface and scale=Option.value scale~default:1. in
        register{id=value.resource_id;identity=Image_identity value.generation;value=Raster2.Consumer.Image value.surface};
        let destination={Raster2.Render_ir.x=float x;y=float y;
          width=float width*.scale;height=float height*.scale}in
        let angle=(Option.value angle~default:0.)*.Float.pi/.180. in
        let flipped=Option.value flip~default:false in
        if angle<>0.||flipped||center<>None then begin
          let cx,cy=match center with
            | None->destination.width*.0.5,destination.height*.0.5
            | Some(cx,cy)->float cx*.scale,float cy*.scale in
          let px=destination.x+.cx and py=destination.y+.cy in
          let cosine=cos angle and sine=sin angle
          and sx=if flipped then -.1. else 1. in
          let xx=cosine*.sx and xy=(-.sine)and yx=sine*.sx and yy=cosine in
          emit(Raster2.Render_ir.Push_transform{xx;xy;yx;yy;
            tx=px-.xx*.px-.xy*.py;ty=py-.yx*.px-.yy*.py})
        end;
        emit(Raster2.Render_ir.Image{resource_id=value.resource_id;
          source={x=0.;y=0.;width=float width;height=float height};destination});
        if angle<>0.||flipped||center<>None then emit Raster2.Render_ir.Pop_transform
      |_->failure:=Some Resource_failure end
    | Scene_description.Text((x,y),value,color_opt,_)|Scene_description.Debug_text((x,y),value,color_opt)->if value<>""then begin match take()with Some(Resolved_text snapshot)->
        register{id=snapshot.resource_id;identity=Text_identity{generation=snapshot.generation;density=snapshot.density};value=Glyph_atlas snapshot.atlas};
        emit(Glyphs{resource_id=snapshot.resource_id;color=color color_opt;glyphs=Array.map(fun(g:Raster2.Render_ir.glyph)->{g with x=g.x+.float x;y=g.y+.float y})snapshot.glyphs})
      |_->failure:=Some Resource_failure end
    | Scene_description.Font_text(_, (x,y),value,color_opt,_,_)->if value<>""then begin match take()with Some(Resolved_text snapshot)->
        register{id=snapshot.resource_id;identity=Text_identity{generation=snapshot.generation;density=snapshot.density};value=Glyph_atlas snapshot.atlas};
        emit(Glyphs{resource_id=snapshot.resource_id;color=color color_opt;glyphs=Array.map(fun(g:Raster2.Render_ir.glyph)->{g with x=g.x+.float x;y=g.y+.float y})snapshot.glyphs})
      |_->failure:=Some Resource_failure end
    | _->reject Metadata in
  match lower_internal~resource_handler:handler scene with Error error->Error error|Ok ir->
  match !failure with Some error->Error error|None->Ok{ir;resources=Array.of_list(List.rev !entries)}

let self_test () =
  let red=Color.rgba 255 0 0 255 and white=Color.white in
  let scene=[Scene_description.Clear red;Blend(Add,[Translate(2,3,[Clip((0,0),8,7,
    [Point((1,1),Some white);Line((0,0),(4,0),Some red,2);
     Rect((1,2),3,4,None,{fill=Some red;stroke=None});
     Triangle((0,0),(2,0),(1,2),{fill=Some white;stroke=None})])])])]in
  match lower scene with Error _->failwith"private Scene lowering failed"|Ok lowered->
  let commands=Raster2.Render_ir.commands lowered in
  if Array.length commands<>11 then failwith"private Scene lowering cardinality";
  begin match commands.(0),commands.(1),commands.(2),commands.(8),commands.(9),commands.(10)with
  | Clear 0xff0000ffl,Set_blend Raster2.Composite.Add,Push_transform _,Pop_clip,Pop_transform,Set_blend Raster2.Composite.Source_over->()
  | _->failwith"private Scene lowering order"end;
  let expected=Raster2.Render_ir.serialize lowered in
  let workers=Array.init 4(fun _->Domain.spawn(fun()->match lower scene with Ok value->Raster2.Render_ir.serialize value|Error _->Bytes.empty))in
  Array.iter(fun worker->if Domain.join worker<>expected then failwith"private Scene lowering domain drift")workers;
  let style:Scene_description.style={fill=Some red;stroke=Some white}in
  let remaining:Scene_description.node list=[Circle((4,4),3,style);Ellipse((4,4),3,2,style);Polygon([(0,0);(4,0);(4,4);(0,4)],style);
    Polyline([(0,0);(3,2);(5,1)],Some red);Arc((4,4),3,0.,Float.pi,Some red);Pie((4,4),3,0.,Float.pi,style);
    Bezier([(0,0);(2,4);(4,0)],8,Some red);Rect((0,0),6,4,Some 1,style)]in
  List.iter(fun value->match lower[value]with Ok _->()|Error _->failwith"pure Scene constructor not lowered")remaining;
  let authored=Path.(empty|>move_to 0. 0.|>line_to 8. 0.|>line_to 8. 8.|>line_to 0. 8.|>close|>move_to 2. 2.|>line_to 2. 6.|>line_to 6. 6.|>line_to 6. 2.|>close)in
  let hole:Scene_description.node=Path(authored,8,Path.Even_odd,{fill=Some red;stroke=Some white})in
  let framed frame=match lower[Rotate(float frame*.0.,[hole])]with Ok value->Raster2.Render_ir.serialize value|Error _->Bytes.empty in
  let expected=framed 1 in
  for frame=1 to 600 do if framed frame<>expected then failwith"frame drift"done;
  let workers=Array.init 4(fun _->Domain.spawn(fun()->framed 1))in
  Array.iter(fun worker->if Domain.join worker<>expected then failwith"path domain drift")workers;
  begin match lower[Text((0,0),"resource",Some red,12)]with Error(Unsupported Text)->()|_->failwith"resource node silently lowered"end;
  let image_surface=match Raster2.Surface.create~width:2~height:2()with Ok value->Raster2.Surface.clear value 0x00ff00ffl;value|Error _->failwith"image fixture"in
  let generation=ref 1L and calls=ref 0 in
  let atlas={Raster2.Consumer.width=1;height=1;pitch=1;bytes=Bytes.of_string"\255";cell_width=1;cell_height=1}in
  let text_snapshot()={resource_id=2;generation=3L;density=2;atlas;glyphs=[|{Raster2.Render_ir.glyph_id=0;x=0.;y=0.}|]}in
  let callbacks={image=(fun _->incr calls;Ok{resource_id=1;generation = !generation;surface=image_surface});
    font_text=(fun _ _ _ _->incr calls;Ok(text_snapshot()));system_text=(fun _ _->incr calls;Ok(text_snapshot()));debug_text=(fun _->incr calls;Ok(text_snapshot()))}in
  let resource_scene:Scene_description.node list=[Translate(1,2,[Image(Obj.magic 0,(2,3),Some 2.,Some 90.,Some(1,1),Some true);
    Text((4,5),"A",Some red,12);Debug_text((5,6),"",None);Font_text(Obj.magic 0,(6,7),"B",Some white,None,None)])]in
  let first=match lower_with_resources callbacks resource_scene with Ok value->value|Error _->failwith"resource lowering"in
  if !calls<>3||Array.length first.resources<>2 then failwith"resource callback cardinality";
  let encode value=(Raster2.Render_ir.serialize value.ir,Array.map(fun entry->entry.id,entry.identity)value.resources)in
  let fixed_callbacks={image=(fun _->Ok{resource_id=1;generation=1L;surface=image_surface});
    font_text=(fun _ _ _ _->Ok(text_snapshot()));system_text=(fun _ _->Ok(text_snapshot()));
    debug_text=(fun _->Ok(text_snapshot()))}in
  let stable=encode first in
  for _frame=1 to 600 do match lower_with_resources fixed_callbacks resource_scene with Ok value when encode value=stable->()|_->failwith"resource frame drift"done;
  let domains=Array.init 4(fun _->Domain.spawn(fun()->match lower_with_resources fixed_callbacks resource_scene with Ok value->encode value|Error _->Bytes.empty,[||]))in
  Array.iter(fun worker->if Domain.join worker<>stable then failwith"resource domain drift")domains;
  let commands=Raster2.Render_ir.commands first.ir in
  if Array.length commands<>7 then failwith"resource command ordering";
  begin match commands.(1),commands.(2),commands.(3)with
  | Raster2.Render_ir.Push_transform matrix,Raster2.Render_ir.Image image,
      Raster2.Render_ir.Pop_transform
      when abs_float matrix.xx < 1e-12 && matrix.xy = -1. &&
        matrix.yx = -1. && abs_float matrix.yy < 1e-12 &&
        image.destination.width = 4. && image.destination.height = 4. -> ()
  | _ -> failwith "image affine transform drift"
  end;
  let target=match Raster2.Surface.create~width:16~height:16()with Ok value->value|Error _->failwith"resource target"in
  let lookup id=Array.find_opt(fun value->value.id=id)first.resources|>Option.map(fun value->value.value)in
  begin match Raster2.Consumer.execute~lookup~target first.ir with Ok()->()|Error _->failwith"resource consumer"end;
  generation:=2L;let second=match lower_with_resources callbacks resource_scene with Ok value->value|Error _->failwith"reload"in
  if first.resources.(0).identity=second.resources.(0).identity then failwith"watched generation lost";
  let before = !calls in ignore(match lower_with_resources callbacks[Text((0,0),"",None,12)]with Ok _->()|Error _->failwith"empty text");if !calls<>before then failwith"empty text callback";
  let rejecting={callbacks with image=(fun _->Error Resource_failure)}in
  match lower_with_resources rejecting resource_scene with Error Resource_failure->()|_->failwith"SDL resource not rejected atomically"

let () = match Sys.getenv_opt "PRISMEL_TEST_SCENE_RASTER2_LOWERING" with Some "1"->self_test()|_->()
