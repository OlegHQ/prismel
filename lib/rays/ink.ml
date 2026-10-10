(* Painter-ordered batches. Only adjacent marks of the same color merge. *)
type t = {builder:Scene_command.Display_list.Builder.t;
  mutable vertices:float array;mutable indices:int array;
  mutable vertex_length:int;mutable index_length:int;mutable color:int32;
  mutable populated:bool;ids:int64 array;version:int64;mutable segment:int;
  clip:(int*int*int*int) option}

let create ?(ids=[||]) ?(version=0L) ?clip () = {builder=Scene_command.Display_list.Builder.create ();
  vertices=Array.make 1024 0.;indices=Array.make 768 0;
  vertex_length=0;index_length=0;color=0l;populated=false;ids;version;segment=0;clip}

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
