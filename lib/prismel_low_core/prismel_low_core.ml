type error = Invalid_argument of string | Unavailable of string | Backend of string

let backend operation error =
  Backend (operation ^ ": " ^ Ogpu.Error.to_string error)

module Window = struct
  type config = { width:int; height:int; title:string; resizable:bool;
    fullscreen:bool; x:int option; y:int option; vsync:bool; highdpi:bool;
    multisampling:int option }
  type t = { target:Runtime_next_orchestrator.t; config:config;
    execution:Prismel_next_execution.t; mutable title:string;
    mutable fullscreen:bool; mutable width:int; mutable height:int;
    mutable destroyed:bool; resources:(int,Prismel_next_execution.resource)Hashtbl.t }
  let default_config = { width=800; height=600; title="Prismel";
    resizable=true; fullscreen=false; x=None; y=None; vsync=true; highdpi=true;
    multisampling=None }
  let create ?(config=default_config) () =
    if config.width <= 0 || config.height <= 0 then
      Error (Invalid_argument "Window.create: dimensions must be positive")
    else
      let configuration = Runtime_next_orchestrator.{
        logical_width=config.width; logical_height=config.height;
        drawable_width=config.width; drawable_height=config.height;vsync=true } in
      match Runtime_next_orchestrator.create configuration with
      | Error value -> Error (backend "Window.create" value)
      | Ok target ->
          let execution_config = Prismel_next_execution.{ default_configuration
            with logical_width=config.width; logical_height=config.height;
            drawable_width=config.width; drawable_height=config.height;
            title=config.title } in
          match Prismel_next_execution.create execution_config with
          | Error error ->
              ignore (Runtime_next_orchestrator.destroy target);
              Error (Backend (Format.asprintf "Window.create: %a"
                Prismel_next_execution.pp_error error))
          | Ok execution -> Ok { target; execution; config; title=config.title;
              fullscreen=config.fullscreen; width=config.width;
              height=config.height; destroyed=false;resources=Hashtbl.create 32 }
  let width value = value.width
  let height value = value.height
  let size value = value.width, value.height
  let drawable_size value = match Runtime_next_orchestrator.facts value.target with
    | Ok facts -> facts.drawable_width, facts.drawable_height
    | Error _ -> value.width, value.height
  let pixel_scale value = let dw,dh = drawable_size value in
    float dw /. float value.width, float dh /. float value.height
  let title value = value.title
  let is_resizable value = value.config.resizable
  let is_fullscreen value = value.fullscreen
  let call name value f = if value.destroyed then Error (Unavailable (name ^ ": destroyed"))
    else match f value.target with Ok () -> Ok () | Error e -> Error (backend name e)
  let set_title value title = match call "Window.set_title" value
      (fun t -> Runtime_next_orchestrator.set_title t title) with
    | Error _ as error -> error | Ok () -> value.title <- title; Ok ()
  let set_size value width height =
    if width <= 0 || height <= 0 then Error (Invalid_argument "Window.set_size") else
    match call "Window.set_size" value (fun t -> Runtime_next_orchestrator.resize t
      ~logical_width:width ~logical_height:height ~drawable_width:width ~drawable_height:height) with
    | Error _ as error -> error
    | Ok () -> begin match Prismel_next_execution.resize value.execution
        ~logical_width:width ~logical_height:height ~drawable_width:width
        ~drawable_height:height with
      | Error e -> Error (Backend (Format.asprintf "Window.set_size: %a"
          Prismel_next_execution.pp_error e))
      | Ok () -> value.width <- width; value.height <- height; Ok ()
      end
  let set_position value x y = call "Window.set_position" value (fun t -> Runtime_next_orchestrator.set_position t ~x ~y)
  let center value = call "Window.center" value Runtime_next_orchestrator.center
  let set_fullscreen value enabled = match call "Window.set_fullscreen" value
      (fun t -> Runtime_next_orchestrator.set_fullscreen t enabled) with
    | Error _ as error -> error | Ok () -> value.fullscreen <- enabled; Ok ()
  let show value = call "Window.show" value Runtime_next_orchestrator.show
  let hide value = call "Window.hide" value Runtime_next_orchestrator.hide
  let minimize value = call "Window.minimize" value Runtime_next_orchestrator.minimize
  let maximize value = call "Window.maximize" value Runtime_next_orchestrator.maximize
  let restore value = call "Window.restore" value Runtime_next_orchestrator.restore
  let capture value = if value.destroyed then Error (Unavailable "Window.capture: destroyed") else
    match Prismel_next_execution.capture value.execution with
    | Ok bytes -> Ok bytes
    | Error e -> Error (Backend (Format.asprintf "Window.capture: %a"
        Prismel_next_execution.pp_error e))
  let register_image value image=if value.destroyed then Error(Unavailable"Window.register_image: destroyed")else
    let id=Prismel_next_resources.Image.identity image in Hashtbl.replace value.resources id(Prismel_next_execution.Image image);Ok id
  let valid_id operation id=if id<=0 then Error(Invalid_argument(operation^": resource id must be positive"))else Ok()
  let register_text value ~id text=match valid_id"Window.register_text"id with Error _ as e->e|Ok()->
    if value.destroyed then Error(Unavailable"Window.register_text: destroyed")else(Hashtbl.replace value.resources id(Prismel_next_execution.Text text);Ok())
  let register_canvas value ~id canvas=match valid_id"Window.register_canvas"id with Error _ as e->e|Ok()->
    if value.destroyed then Error(Unavailable"Window.register_canvas: destroyed")else(Hashtbl.replace value.resources id(Prismel_next_execution.Canvas canvas);Ok())
  let remove_resource value id=Hashtbl.remove value.resources id
  let present value ir =
    if value.destroyed then Error (Unavailable "Window.present: destroyed") else
    match Prismel_next_execution.lower_scene2 value.execution~density:(max 1(int_of_float(fst(pixel_scale value)+.0.5)))
      ~resource:(Hashtbl.find_opt value.resources)ir with
    | Error e -> Error (Backend (Format.asprintf "%a" Prismel_next_execution.pp_error e))
    | Ok draws -> match Prismel_next_execution.step value.execution draws with
      | Ok _ -> Ok true
      | Error e -> Error (Backend (Format.asprintf "%a"
          Prismel_next_execution.pp_error e))
  let destroy value = if value.destroyed then Ok () else
    match Prismel_next_execution.destroy value.execution with
    | Error e -> Error (Backend (Format.asprintf "Window.destroy: %a"
        Prismel_next_execution.pp_error e))
    | Ok () -> match Runtime_next_orchestrator.destroy value.target with
      | Error e -> Error (backend "Window.destroy" e)
      | Ok () -> Hashtbl.clear value.resources;value.destroyed <- true; Ok ()
  let exists value = not value.destroyed
end

module Graphics = struct
  type color = int32
  type blend = Scene_command.Render_ir.blend
  type matrix = { xx:float; xy:float; yx:float; yy:float; tx:float; ty:float }
  type t = { capacity:int; mutable commands:Scene_command.Render_ir.command list;
    mutable count:int; mutable peak:int; mutable color:color; mutable matrix:matrix;
    mutable stack:matrix list; mutable clip:(int*int*int*int) option;
    mutable rotation:int; mutable destroyed:bool }
  let identity = {xx=1.;xy=0.;yx=0.;yy=1.;tx=0.;ty=0.}
  let create ?(capacity=65536) () = if capacity <= 0 then Error (Invalid_argument "Graphics.create") else
    Ok {capacity;commands=[];count=0;peak=0;color=Int32.minus_one;matrix=identity;
      stack=[];clip=None;rotation=0;destroyed=false}
  let add t command = if t.destroyed then Error (Unavailable "Graphics: destroyed")
    else if t.count=t.capacity then Error (Unavailable "Graphics: command capacity") else
    (t.commands<-command::t.commands;t.count<-t.count+1;t.peak<-max t.peak t.count;Ok ())
  let clear t c = add t (Scene_command.Render_ir.Clear c)
  let set_color t c = t.color<-c
  let get_color t ?color () = Option.value color ~default:t.color
  let set_blend t b = add t (Set_blend b)
  let transform t (x,y) = let m=t.matrix in
    m.xx*.float x +. m.xy*.float y +. m.tx, m.yx*.float x +. m.yy*.float y +. m.ty
  let geometry t ?color vertices indices = add t (Geometry {vertices;indices;color=get_color t ?color ()})
  let point t ~x ~y ?color () = let x,y=transform t (x,y) in geometry t ?color [|x;y;x+.1.;y;x;y+.1.|] [|0;1;2|]
  let line t ~x1 ~y1 ~x2 ~y2 ?color () = let a,b=transform t (x1,y1) and c,d=transform t (x2,y2) in geometry t ?color [|a;b;c;d;c;d+.1.;a;b+.1.|] [|0;1;2;0;2;3|]
  let bind result next = match result with Ok value -> next value | Error _ as error -> error
  let rect t ~pos:(x,y) ~w ~h ?(filled=true) ?color () = if not filled then
      bind (line t ~x1:x ~y1:y ~x2:(x+w) ~y2:y ?color ()) (fun () ->
      bind (line t ~x1:(x+w) ~y1:y ~x2:(x+w) ~y2:(y+h) ?color ()) (fun () ->
      bind (line t ~x1:(x+w) ~y1:(y+h) ~x2:x ~y2:(y+h) ?color ())
        (fun () -> line t ~x1:x ~y1:(y+h) ~x2:x ~y2:y ?color ())))
    else let a,b=transform t (x,y) and c,d=transform t (x+w,y+h) in geometry t ?color [|a;b;c;b;c;d;a;d|] [|0;1;2;0;2;3|]
  let polygon t ~points ?(filled=true) ?color () = match points with
    | []|[_] -> Ok () | first::rest when not filled ->
        let rec loop previous = function
          | [] -> Ok ()
          | p::ps -> bind (line t ~x1:(fst previous) ~y1:(snd previous)
              ~x2:(fst p) ~y2:(snd p) ?color ()) (fun () -> loop p ps)
        in
        loop first (rest @ [first])
    | _ -> let points=Array.of_list points in let vertices=Array.make (Array.length points*2) 0. in Array.iteri (fun i p->let x,y=transform t p in vertices.(2*i)<-x;vertices.(2*i+1)<-y) points; let indices=Array.init ((Array.length points-2)*3) (fun i->match i mod 3 with 0->0|1->i/3+1|_->i/3+2) in geometry t ?color vertices indices
  let polyline t ~points ?color () = polygon t ~points ~filled:false ?color ()
  let triangle t ~p1 ~p2 ~p3 ?(filled=true) ?color () = polygon t ~points:[p1;p2;p3] ~filled ?color ()
  let circle t ~center:(cx,cy) ~radius ?(filled=true) ?color () = if radius<0 then Error (Invalid_argument "Graphics.circle") else let n=max 12 (radius*2) in let points=List.init n (fun i->let a=2.*.Float.pi*.float i/.float n in cx+int_of_float(float radius*.cos a),cy+int_of_float(float radius*.sin a)) in polygon t ~points ~filled ?color ()
  let ellipse_points ~center:(cx,cy) ~rx ~ry ~from_ ~to_ ~steps =
    List.init (steps + 1) (fun index ->
      let amount = float index /. float steps in
      let angle = from_ +. ((to_ -. from_) *. amount) in
      cx + int_of_float (cos angle *. float rx),
      cy + int_of_float (sin angle *. float ry))
  let ellipse t ~center ~rx ~ry ?(filled=true) ?color () =
    if rx < 0 || ry < 0 then Error (Invalid_argument "Graphics.ellipse")
    else
      let steps = max 24 (min 128 (max rx ry * 2)) in
      polygon t ~points:(ellipse_points ~center ~rx ~ry ~from_:0.
        ~to_:(2. *. Float.pi) ~steps) ~filled ?color ()
  let rounded_rect t ~pos:(x,y) ~w ~h ~radius ?(filled=true) ?color () =
    if w < 0 || h < 0 || radius < 0 then
      Error (Invalid_argument "Graphics.rounded_rect")
    else
      let radius = min radius (min (w / 2) (h / 2)) in
      if radius = 0 then rect t ~pos:(x,y) ~w ~h ~filled ?color ()
      else
        let steps = max 4 (min 32 ((radius + 1) / 2)) in
        let quarter center from_ to_ = ellipse_points ~center ~rx:radius
            ~ry:radius ~from_ ~to_ ~steps in
        polygon t ~filled ?color ~points:(
          quarter (x+radius,y+radius) Float.pi (1.5*.Float.pi)
          @ quarter (x+w-radius,y+radius) (1.5*.Float.pi) (2.*.Float.pi)
          @ quarter (x+w-radius,y+h-radius) 0. (0.5*.Float.pi)
          @ quarter (x+radius,y+h-radius) (0.5*.Float.pi) Float.pi) ()
  let thick_line t ~x1 ~y1 ~x2 ~y2 ~width ?color () =
    if width <= 0 then Error (Invalid_argument "Graphics.thick_line")
    else
      let dx=float(x2-x1) and dy=float(y2-y1) in
      let length=Float.hypot dx dy in
      if length=0. then circle t ~center:(x1,y1) ~radius:(width/2)
          ~filled:true ?color ()
      else
        let ox=(-.dy/.length*.float width/.2.) and oy=(dx/.length*.float width/.2.) in
        let p x y = int_of_float x,int_of_float y in
        polygon t ~filled:true ?color ~points:[p(float x1+.ox)(float y1+.oy);
          p(float x2+.ox)(float y2+.oy);p(float x2-.ox)(float y2-.oy);
          p(float x1-.ox)(float y1-.oy)] ()
  let arc t ~center ~radius ~start_angle ~end_angle ?color () =
    if radius < 0 || not (Float.is_finite start_angle && Float.is_finite end_angle)
    then Error (Invalid_argument "Graphics.arc")
    else let span=abs_float(end_angle-.start_angle) in
      polyline t ?color ~points:(ellipse_points ~center ~rx:radius ~ry:radius
        ~from_:start_angle ~to_:end_angle
        ~steps:(max 8 (int_of_float(span*.float radius/.4.)))) ()
  let pie t ~center:(cx,cy) ~radius ~start_angle ~end_angle ?(filled=true)
      ?color () =
    if radius < 0 then Error (Invalid_argument "Graphics.pie")
    else let span=abs_float(end_angle-.start_angle) in
      polygon t ~filled ?color ~points:((cx,cy)::ellipse_points ~center:(cx,cy)
        ~rx:radius ~ry:radius ~from_:start_angle ~to_:end_angle
        ~steps:(max 8 (int_of_float(span*.float radius/.2.)))) ()
  let bezier t ~points ~steps ?color () =
    if steps <= 0 then Error (Invalid_argument "Graphics.bezier") else
    match points with
    | [] -> Ok ()
    | _ ->
        let source=Array.of_list points and count=List.length points in
        let choose n k =
          let result=ref 1. in for i=1 to k do
            result:=!result*.float(n-k+i)/.float i done; !result in
        let sampled=List.init(steps+1)(fun step ->
          let u=float step/.float steps in let x=ref 0. and y=ref 0. in
          Array.iteri(fun i(px,py)->let weight=choose(count-1)i*.
            ((1.-.u)**float(count-1-i))*.(u**float i) in
            x:=!x+.weight*.float px;y:=!y+.weight*.float py)source;
          int_of_float !x,int_of_float !y) in
        polyline t ~points:sampled ?color ()
  let path_geometry t ?color mesh =
    let vertices=Array.make(Array.length mesh.Scene_command.Path.vertices*2)0. in
    Array.iteri(fun i point -> let x,y=transform t
      (int_of_float point.Scene_command.Path.x,int_of_float point.y) in
      vertices.(2*i)<-x;vertices.(2*i+1)<-y)mesh.vertices;
    geometry t ?color vertices mesh.indices
  let fill_contours t contours ~rule ~color =
    let commands = List.concat_map (function []->[]|first::rest ->
      Scene_command.Path.Move_to {x=float(fst first);y=float(snd first)} ::
      List.map(fun(x,y)->Scene_command.Path.Line_to{x=float x;y=float y})rest @
      [Scene_command.Path.Close]) contours |> Array.of_list in
    match Scene_command.Path.tessellate ~tolerance:0.25 ~fill_rule:rule
      (Scene_command.Path.of_commands commands) with
    | Ok mesh -> path_geometry t ~color mesh
    | Error _ -> Error (Invalid_argument "Graphics.fill_contours")
  let stroke_path t commands ~width ~cap ~join ?color () =
    match Scene_command.Path.stroke ~tolerance:0.25 ~width ~cap ~join
      ~miter_limit:4. (Scene_command.Path.of_commands commands) with
    | Ok mesh -> path_geometry t ?color mesh
    | Error _ -> Error (Invalid_argument "Graphics.stroke_path")
  let push_matrix t = t.stack<-t.matrix::t.stack; add t (Push_transform {xx=t.matrix.xx;xy=t.matrix.xy;yx=t.matrix.yx;yy=t.matrix.yy;tx=t.matrix.tx;ty=t.matrix.ty})
  let pop_matrix t = match t.stack with []->Error (Invalid_argument "Graphics.pop_matrix")|m::rest->t.matrix<-m;t.stack<-rest;add t Pop_transform
  let translate t ~dx ~dy = t.matrix <- {t.matrix with tx=t.matrix.tx+.float dx;ty=t.matrix.ty+.float dy}
  let rotate t ~angle = let c=cos angle and s=sin angle and m=t.matrix in t.matrix<-{m with xx=m.xx*.c+.m.xy*.s;xy=(-.m.xx*.s)+.m.xy*.c;yx=m.yx*.c+.m.yy*.s;yy=(-.m.yx*.s)+.m.yy*.c}
  let scale t ~sx ~sy = let m=t.matrix in t.matrix<-{m with xx=m.xx*.sx;xy=m.xy*.sy;yx=m.yx*.sx;yy=m.yy*.sy}
  let reset_transform t = t.matrix<-identity;t.stack<-[]
  let get_clip t=t.clip
  let set_clip t value =
    let command = match t.clip, value with
      | Some _, None -> Some Scene_command.Render_ir.Pop_clip
      | _, Some (x,y,w,h) -> Some (Scene_command.Render_ir.Push_clip
          {x=float x; y=float y; width=float w; height=float h})
      | None, None -> None
    in
    t.clip <- value;
    match command with None -> Ok () | Some command -> add t command
  let draw_image t image ~pos:(x,y) = match Prismel_next_resources.Image.size image with Error _->Error(Unavailable "Graphics.draw_image")|Ok(w,h)->add t(Image{resource_id=Prismel_next_resources.Image.identity image;source={x=0.;y=0.;width=float w;height=float h};destination={x=float x;y=float y;width=float w;height=float h}})
  let draw_sub_image t image ~src_rect:(sx,sy,sw,sh)
      ~dst_rect:(dx,dy,dw,dh) =
    add t (Image {resource_id=Prismel_next_resources.Image.identity image;
      source={x=float sx;y=float sy;width=float sw;height=float sh};
      destination={x=float dx;y=float dy;width=float dw;height=float dh}})
  let draw_image_ex t image ~pos:(x,y) ?(scale=1.) ?(angle=0.) ?center
      ?(flip=false) () =
    if not(Float.is_finite scale&&Float.is_finite angle)||scale<=0. then
      Error(Invalid_argument "Graphics.draw_image_ex")
    else match Prismel_next_resources.Image.size image with
    | Error _ -> Error(Unavailable "Graphics.draw_image_ex")
    | Ok(w,h) ->
        let cx,cy=Option.value center ~default:(w/2,h/2) in
        let cosine=cos angle*.scale and sine=sin angle*.scale in
        let xx=if flip then -.cosine else cosine
        and yx=if flip then -.sine else sine in
        let transform=Scene_command.Render_ir.{xx;xy=(-.sine);yx;yy=cosine;
          tx=float x -. (float cx *. xx) -. (float cy *. (-. sine));
          ty=float y -. (float cx *. yx) -. (float cy *. cosine)} in
        bind (add t (Push_transform transform)) (fun () ->
        bind (add t (Image{resource_id=Prismel_next_resources.Image.identity image;
          source={x=0.;y=0.;width=float w;height=float h};
          destination={x=0.;y=0.;width=float w;height=float h}})) (fun () ->
        add t Pop_transform))
  let draw_text t font ~pos:(x,y) ~text ?color () = if text="" then Ok() else let glyphs=Array.init(String.length text)(fun i->{Scene_command.Render_ir.glyph_id=Char.code text.[i];x=float(x+i*8);y=float y}) in add t(Glyphs{resource_id=Prismel_next_resources.Font.generation font;color=get_color t ?color ();glyphs})
  let draw_text_snapshot t ~resource_id text ~pos:(x,y) =
    match Prismel_next_resources.Text.size text with Error _->Error(Unavailable"Graphics.draw_text_snapshot")|Ok _->
    add t(Glyphs{resource_id;color=Int32.minus_one;glyphs=[|{glyph_id=0;x=float x;y=float y}|]})
  let draw_canvas t ~resource_id canvas ~pos:(x,y) =
    match Prismel_next_resources.Canvas.size canvas with Error _->Error(Unavailable"Graphics.draw_canvas")|Ok(w,h)->
    add t(Image{resource_id;source={x=0.;y=0.;width=float w;height=float h};destination={x=float x;y=float y;width=float w;height=float h}})
  let set_gfx_font_rotation t value = if value<0||value>3 then Error(Invalid_argument "Graphics.set_gfx_font_rotation") else (t.rotation<-value;Ok())
  let draw_gfx_text t ~pos:(x,y) ~text ?color () = let glyphs=Array.init(String.length text)(fun i->{Scene_command.Render_ir.glyph_id=Char.code text.[i];x=float(x+i*8);y=float y}) in add t(Glyphs{resource_id=1+t.rotation;color=get_color t ?color ();glyphs})
  let flush t = if t.stack<>[] then Error(Invalid_argument "Graphics.flush: unbalanced matrix") else match Scene_command.Render_ir.create(Array.of_list(List.rev t.commands)) with Error _->Error(Invalid_argument "Graphics.flush: invalid stream")|Ok ir->t.commands<-[];t.count<-0;Ok ir
  let command_count t=t.count
  let peak_commands t=t.peak
  let destroy t=t.destroyed<-true;t.commands<-[];t.count<-0;t.stack<-[]
end
