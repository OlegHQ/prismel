(* Painter-ordered batches. Only adjacent marks of the same color merge. *)
type t = {builder:Scene_command.Display_list.Builder.t;
  mutable vertices:float array;mutable indices:int array;
  mutable vertex_length:int;mutable index_length:int;mutable color:int32;
  mutable populated:bool;mutable ids:int64 array;version:int64;mutable segment:int;
  mutable clip:(int*int*int*int) option}

let create ?(ids=[||]) ?(version=0L) ?clip () = {builder=Scene_command.Display_list.Builder.create ();
  vertices=Array.make 1024 0.;indices=Array.make 768 0;
  vertex_length=0;index_length=0;color=0l;populated=false;ids;version;segment=0;clip}

let set_clip t clip =
  if t.populated then invalid_arg "Ink.set_clip: publish pending marks first";
  t.clip<-clip

let set_ids t ids =
  if t.populated then invalid_arg "Ink.set_ids";
  t.ids<-ids;t.segment<-0

let flush t =
  if t.index_length>0 then begin
    Scene_command.Display_list.Builder.geometry t.builder
      {vertices=Array.sub t.vertices 0 t.vertex_length;
       indices=Array.sub t.indices 0 t.index_length;color=t.color};
    t.vertex_length<-0;t.index_length<-0
  end

let reserve t vertices indices color =
  if not t.populated then Option.iter (fun (x,y,width,height) ->
    Scene_command.Display_list.Builder.push_clip t.builder
      ~x:(float x) ~y:(float y) ~width:(float width) ~height:(float height)) t.clip;
  if color<>t.color then (flush t;t.color<-color);
  let needed=t.vertex_length+vertices in
  if needed>Array.length t.vertices then begin
    let next=Array.make (max needed (Array.length t.vertices*2)) 0. in
    Array.blit t.vertices 0 next 0 t.vertex_length;t.vertices<-next
  end;
  let needed=t.index_length+indices in
  if needed>Array.length t.indices then begin
    let next=Array.make (max needed (Array.length t.indices*2)) 0 in
    Array.blit t.indices 0 next 0 t.index_length;t.indices<-next
  end;
  t.populated<-true

let rgba (c:Color.t) =
  Int32.logor (Int32.shift_left (Int32.of_int c.r) 24)
    (Int32.of_int ((c.g lsl 16) lor (c.b lsl 8) lor c.a))

let rectf t x y width height color =
  if width>0. && height>0. then begin
    reserve t 8 6 (rgba color);
    let p=t.vertex_length and i=t.index_length in
    let right=x+.width and bottom=y+.height in
    t.vertices.(p)<-x;t.vertices.(p+1)<-y;
    t.vertices.(p+2)<-right;t.vertices.(p+3)<-y;
    t.vertices.(p+4)<-right;t.vertices.(p+5)<-bottom;
    t.vertices.(p+6)<-x;t.vertices.(p+7)<-bottom;
    let base=p/2 in
    t.indices.(i)<-base;t.indices.(i+1)<-base+1;t.indices.(i+2)<-base+2;
    t.indices.(i+3)<-base;t.indices.(i+4)<-base+2;t.indices.(i+5)<-base+3;
    t.vertex_length<-p+8;t.index_length<-i+6
  end

let rect t x y width height color =
  rectf t (float x) (float y) (float width) (float height) color

let geometry t (geometry:Scene_command.Render_ir.geometry) =
  let nv=Array.length geometry.vertices and ni=Array.length geometry.indices in
  reserve t nv ni geometry.color;
  Array.blit geometry.vertices 0 t.vertices t.vertex_length nv;
  let base=t.vertex_length/2 in
  for i=0 to ni-1 do t.indices.(t.index_length+i)<-base+geometry.indices.(i) done;
  t.vertex_length<-t.vertex_length+nv;t.index_length<-t.index_length+ni

let line t x y x2 y2 color =
  geometry t (Scene_command.Shape2.line ~from_:(x,y) ~to_:(x2,y2) ~width:1 ~color:(rgba color))

let linef t x y x2 y2 color =
  let module Path=Scene_command.Path in
  let path=Path.of_commands [|Path.Move_to {x;y};Path.Line_to {x=x2;y=y2}|] in
  match Path.stroke ~tolerance:0.25 ~width:1. ~cap:Path.Butt ~join:Path.Miter
    ~miter_limit:4. path with
  |Error Path.Empty_path -> ()
  |Error _ -> invalid_arg "Ink.linef: invalid path"
  |Ok mesh ->
      let vertices=Array.make (Array.length mesh.vertices*2) 0. in
      Array.iteri (fun i (p:Path.point) -> vertices.(i*2)<-p.x;vertices.(i*2+1)<-p.y)
        mesh.vertices;
      geometry t {vertices;indices=mesh.indices;color=rgba color}

let outline t x y width height color =
  Array.iter (geometry t) (Scene_command.Shape2.rect ~x ~y ~width ~height
    ~fill:None ~stroke:(Some (rgba color)))

let take t =
  if not t.populated then None else begin
    flush t;
    Option.iter (fun _ -> Scene_command.Display_list.Builder.pop_clip t.builder) t.clip;
    let id=if t.segment<Array.length t.ids then t.ids.(t.segment)
      else Scene_command.Display_list.fresh_id () in
    t.segment<-t.segment+1;
    let value=Result.get_ok (Scene_command.Display_list.Builder.publish t.builder
      ~id ~version:t.version) in
    Scene_command.Display_list.Builder.reset t.builder;
    t.populated<-false;
    Some (Scene.Private.display_list value)
  end

let fresh_id=Scene_command.Display_list.fresh_id
