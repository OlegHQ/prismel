type unsupported = Rounded_rect | Styled_primitive | Circle | Ellipse | Polygon | Polyline |
  Arc | Pie | Bezier | Path | Text | Image | View3d | Metadata
type error = Unsupported of unsupported | Invalid_ir of Raster2.Render_ir.error

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

let lower scene =
  let commands=ref[]and failure=ref None in
  let emit value=commands:=value::!commands and reject value=if !failure=None then failure:=Some(Unsupported value)in
  let rec nodes active_blend values=List.iter(node active_blend)values
  and styled style make = match style.Scene_description.fill,style.stroke with
    | Some fill,None->emit(make(packed fill))|_->reject Styled_primitive
  and node active_blend = function
    | Scene_description.Clear value->emit(Raster2.Render_ir.Clear(packed value))
    | Point((x,y),value)->emit(quad x y(x+1)(y+1)(color value))
    | Line(a,b,value,width)->emit(line a b width(color value))
    | Rect((x,y),w,h,None,style)->styled style(fun c->quad x y(x+w)(y+h)c)
    | Rect(_,_,_,Some _,_)->reject Rounded_rect
    | Triangle((ax,ay),(bx,by),(cx,cy),style)->styled style(fun c->geometry[|float ax;float ay;float bx;float by;float cx;float cy|][|0;1;2|]c)
    | Group children->nodes active_blend children
    | Translate(x,y,children)->emit(Push_transform{xx=1.;xy=0.;yx=0.;yy=1.;tx=float x;ty=float y});nodes active_blend children;emit Pop_transform
    | Rotate(angle,children)->let c=cos angle and s=sin angle in emit(Push_transform{xx=c;xy=(-.s);yx=s;yy=c;tx=0.;ty=0.});nodes active_blend children;emit Pop_transform
    | Scale(x,y,children)->emit(Push_transform{xx=x;xy=0.;yx=0.;yy=y;tx=0.;ty=0.});nodes active_blend children;emit Pop_transform
    | Clip((x,y),w,h,children)->emit(Push_clip{x=float x;y=float y;width=float w;height=float h});nodes active_blend children;emit Pop_clip
    | Blend(value,children)->let nested=blend value in emit(Set_blend nested);nodes nested children;emit(Set_blend active_blend)
    | Circle _->reject Circle|Ellipse _->reject Ellipse|Polygon _->reject Polygon|Polyline _->reject Polyline
    | Arc _->reject Arc|Pie _->reject Pie|Bezier _->reject Bezier|Path _->reject Path
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
  match lower[Circle((0,0),1,{fill=Some red;stroke=None})]with Error(Unsupported Circle)->()|_->failwith"unsupported Scene node silently lowered"

let () = match Sys.getenv_opt "PRISMEL_TEST_SCENE_RASTER2_LOWERING" with Some "1"->self_test()|_->()
