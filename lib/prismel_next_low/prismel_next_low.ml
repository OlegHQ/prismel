type error = Invalid_argument of string | Unavailable of string | Backend of string

let backend operation error =
  Backend (operation ^ ": " ^ Ogpu.Error.to_string error)

module Window = struct
  type config = { width:int; height:int; title:string; resizable:bool;
    fullscreen:bool; x:int option; y:int option; vsync:bool; highdpi:bool;
    multisampling:int option }
  type t = { target:Runtime_next_orchestrator.t; config:config;
    mutable width:int; mutable height:int; mutable destroyed:bool }
  let default_config = { width=800; height=600; title="Prismel";
    resizable=true; fullscreen=false; x=None; y=None; vsync=true; highdpi=true;
    multisampling=None }
  let create ?(config=default_config) () =
    if config.width <= 0 || config.height <= 0 then
      Error (Invalid_argument "Window.create: dimensions must be positive")
    else
      let selected_target = match Runtime_next_orchestrator.selected () with
        | Ok value -> value | Error message -> raise (Failure message) in
      let configuration = Runtime_next_orchestrator.{ target=selected_target;
        logical_width=config.width; logical_height=config.height;
        drawable_width=config.width; drawable_height=config.height;
        web_configuration=None } in
      match Runtime_next_orchestrator.create configuration with
      | Error value -> Error (backend "Window.create" value)
      | Ok target ->
          Ok { target; config; width=config.width; height=config.height;
            destroyed=false }
  let width value = value.width
  let height value = value.height
  let size value = value.width, value.height
  let drawable_size value = match Runtime_next_orchestrator.facts value.target with
    | Ok facts -> facts.drawable_width, facts.drawable_height
    | Error _ -> value.width, value.height
  let pixel_scale value = let dw,dh = drawable_size value in
    float dw /. float value.width, float dh /. float value.height
  let title value = value.config.title
  let is_resizable value = value.config.resizable
  let is_fullscreen value = value.config.fullscreen
  let call name value f = if value.destroyed then Error (Unavailable (name ^ ": destroyed"))
    else match f value.target with Ok () -> Ok () | Error e -> Error (backend name e)
  let set_title value title = call "Window.set_title" value (fun t -> Runtime_next_orchestrator.set_title t title)
  let set_size value width height =
    if width <= 0 || height <= 0 then Error (Invalid_argument "Window.set_size") else
    match call "Window.set_size" value (fun t -> Runtime_next_orchestrator.resize t
      ~logical_width:width ~logical_height:height ~drawable_width:width ~drawable_height:height) with
    | Error _ as error -> error | Ok () -> value.width <- width; value.height <- height; Ok ()
  let set_position value x y = call "Window.set_position" value (fun t -> Runtime_next_orchestrator.set_position t ~x ~y)
  let center value = call "Window.center" value Runtime_next_orchestrator.center
  let set_fullscreen value enabled = call "Window.set_fullscreen" value (fun t -> Runtime_next_orchestrator.set_fullscreen t enabled)
  let show value = call "Window.show" value Runtime_next_orchestrator.show
  let hide value = call "Window.hide" value Runtime_next_orchestrator.hide
  let minimize value = call "Window.minimize" value Runtime_next_orchestrator.minimize
  let maximize value = call "Window.maximize" value Runtime_next_orchestrator.maximize
  let restore value = call "Window.restore" value Runtime_next_orchestrator.restore
  let capture value = if value.destroyed then Error (Unavailable "Window.capture: destroyed") else
    match Runtime_next_orchestrator.capture value.target ~bytes_per_row:(value.width*4) with
    | Ok bytes -> Ok bytes | Error e -> Error (backend "Window.capture" e)
  let present value ir =
    if value.destroyed then Error (Unavailable "Window.present: destroyed") else
    match Prismel_next_execution.scene2_ir ir with
    | Error e -> Error (Backend (Format.asprintf "%a" Prismel_next_execution.pp_error e))
    | Ok draws -> match Prismel_next_execution.create Prismel_next_execution.{
        default_configuration with target=(match Runtime_next_orchestrator.target value.target with Native->Native|Headless->Headless|Web->Web);
        logical_width=value.width; logical_height=value.height;
        drawable_width=value.width; drawable_height=value.height } with
      | Error e -> Error (Backend (Format.asprintf "%a" Prismel_next_execution.pp_error e))
      | Ok execution ->
          let result = match Prismel_next_execution.step execution draws with
            | Ok _ -> Ok true | Error e -> Error (Backend (Format.asprintf "%a" Prismel_next_execution.pp_error e)) in
          ignore (Prismel_next_execution.destroy execution); result
  let destroy value = if value.destroyed then Ok () else
    match Runtime_next_orchestrator.destroy value.target with
    | Error e -> Error (backend "Window.destroy" e)
    | Ok () -> value.destroyed <- true; Ok ()
  let exists value = not value.destroyed
end

module Graphics = struct
  type color = int32
  type blend = Raster2.Composite.blend
  type matrix = { xx:float; xy:float; yx:float; yy:float; tx:float; ty:float }
  type t = { capacity:int; mutable commands:Raster2.Render_ir.command list;
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
  let clear t c = add t (Raster2.Render_ir.Clear c)
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
  let push_matrix t = t.stack<-t.matrix::t.stack; add t (Push_transform {xx=t.matrix.xx;xy=t.matrix.xy;yx=t.matrix.yx;yy=t.matrix.yy;tx=t.matrix.tx;ty=t.matrix.ty})
  let pop_matrix t = match t.stack with []->Error (Invalid_argument "Graphics.pop_matrix")|m::rest->t.matrix<-m;t.stack<-rest;add t Pop_transform
  let translate t ~dx ~dy = t.matrix <- {t.matrix with tx=t.matrix.tx+.float dx;ty=t.matrix.ty+.float dy}
  let rotate t ~angle = let c=cos angle and s=sin angle and m=t.matrix in t.matrix<-{m with xx=m.xx*.c+.m.xy*.s;xy=(-.m.xx*.s)+.m.xy*.c;yx=m.yx*.c+.m.yy*.s;yy=(-.m.yx*.s)+.m.yy*.c}
  let scale t ~sx ~sy = let m=t.matrix in t.matrix<-{m with xx=m.xx*.sx;xy=m.xy*.sy;yx=m.yx*.sx;yy=m.yy*.sy}
  let reset_transform t = t.matrix<-identity;t.stack<-[]
  let get_clip t=t.clip
  let set_clip t value =
    let command = match t.clip, value with
      | Some _, None -> Some Raster2.Render_ir.Pop_clip
      | _, Some (x,y,w,h) -> Some (Raster2.Render_ir.Push_clip
          {x=float x; y=float y; width=float w; height=float h})
      | None, None -> None
    in
    t.clip <- value;
    match command with None -> Ok () | Some command -> add t command
  let draw_image t image ~pos:(x,y) = match Prismel_next_resources.Image.size image with Error _->Error(Unavailable "Graphics.draw_image")|Ok(w,h)->add t(Image{resource_id=Prismel_next_resources.Image.identity image;source={x=0.;y=0.;width=float w;height=float h};destination={x=float x;y=float y;width=float w;height=float h}})
  let draw_text t font ~pos:(x,y) ~text ?color () = if text="" then Ok() else let glyphs=Array.init(String.length text)(fun i->{Raster2.Render_ir.glyph_id=Char.code text.[i];x=float(x+i*8);y=float y}) in add t(Glyphs{resource_id=Prismel_next_resources.Font.generation font;color=get_color t ?color ();glyphs})
  let set_gfx_font_rotation t value = if value<0||value>3 then Error(Invalid_argument "Graphics.set_gfx_font_rotation") else (t.rotation<-value;Ok())
  let draw_gfx_text t ~pos:(x,y) ~text ?color () = let glyphs=Array.init(String.length text)(fun i->{Raster2.Render_ir.glyph_id=Char.code text.[i];x=float(x+i*8);y=float y}) in add t(Glyphs{resource_id=1+t.rotation;color=get_color t ?color ();glyphs})
  let flush t = if t.stack<>[] then Error(Invalid_argument "Graphics.flush: unbalanced matrix") else match Raster2.Render_ir.create(Array.of_list(List.rev t.commands)) with Error _->Error(Invalid_argument "Graphics.flush: invalid stream")|Ok ir->t.commands<-[];t.count<-0;Ok ir
  let command_count t=t.count
  let peak_commands t=t.peak
  let destroy t=t.destroyed<-true;t.commands<-[];t.count<-0;t.stack<-[]
end
