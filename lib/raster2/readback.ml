type orientation=Top_down|Bottom_up
type format=Rgba|Bgra
type t={mutable storage:bytes;hard_capacity:int;mutable length:int;mutable growths:int}
type frame={storage:bytes;width:int;height:int;pitch:int;length:int}
type metrics={capacity:int;length:int;growths:int}
type error=Invalid_capacity|Size_overflow|Capacity_exceeded
let create ~initial_capacity ~hard_capacity=if initial_capacity<0||hard_capacity<0||initial_capacity>hard_capacity then Error Invalid_capacity else Ok{storage=Bytes.create initial_capacity;hard_capacity;length=0;growths=0}
let read scratch ~orientation ~format surface=
 let width=Surface.width surface and height=Surface.height surface in
 if width>max_int/4 then Error Size_overflow else let pitch=width*4 in
 if height<>0&&pitch>max_int/height then Error Size_overflow else let length=pitch*height in
 if length>scratch.hard_capacity then Error Capacity_exceeded else begin
  if length>Bytes.length scratch.storage then(let capacity=ref(max 1(Bytes.length scratch.storage))in while !capacity<length do capacity:=min scratch.hard_capacity(max(!capacity+1)(2* !capacity))done;scratch.storage<-Bytes.create !capacity;scratch.growths<-scratch.growths+1);
  let source=Surface.bytes surface in
  for output_y=0 to height-1 do let source_y=match orientation with Top_down->output_y|Bottom_up->height-1-output_y in let source_row=source_y*Surface.pitch surface and output_row=output_y*pitch in
   match format with Rgba->Bytes.blit source source_row scratch.storage output_row pitch|Bgra->for x=0 to width-1 do let si=source_row+x*4 and di=output_row+x*4 in Bytes.set scratch.storage di(Bytes.get source(si+2));Bytes.set scratch.storage(di+1)(Bytes.get source(si+1));Bytes.set scratch.storage(di+2)(Bytes.get source si);Bytes.set scratch.storage(di+3)(Bytes.get source(si+3))done
  done;scratch.length<-length;Ok{storage=scratch.storage;width;height;pitch;length}
 end
let width (f:frame)=f.width
let height (f:frame)=f.height
let pitch (f:frame)=f.pitch
let length (f:frame)=f.length
let bytes (f:frame)=f.storage
let hash (frame:frame)=let value=ref 0xcbf29ce484222325L in for i=0 to frame.length-1 do value:=Int64.mul(Int64.logxor !value(Int64.of_int(Char.code(Bytes.get frame.storage i))))0x100000001b3L done;!value
let metrics (t:t)={capacity=Bytes.length t.storage;length=t.length;growths=t.growths}
