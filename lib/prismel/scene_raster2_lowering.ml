type unsupported = Text | Image | View3d | Metadata
type error = Unsupported of unsupported | Invalid_path of Raster2.Path.error | Invalid_ir of Raster2.Render_ir.error

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

let lower scene =
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
    | Text _|Debug_text _|Font_text _->reject Text|Image _->reject Image|View3d _->reject View3d
    | Text_input_region _->reject Metadata
  in nodes Raster2.Composite.Source_over scene;match !failure with Some error->Error error|None->
  match Raster2.Render_ir.create(Array.of_list(List.rev !commands))with Ok value->Ok value|Error error->Error(Invalid_ir error)

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
  match lower[Text((0,0),"resource",Some red,12)]with Error(Unsupported Text)->()|_->failwith"resource node silently lowered"

let () = match Sys.getenv_opt "PRISMEL_TEST_SCENE_RASTER2_LOWERING" with Some "1"->self_test()|_->()
