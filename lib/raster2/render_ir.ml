type rect={x:float;y:float;width:float;height:float}
type transform={xx:float;xy:float;yx:float;yy:float;tx:float;ty:float}
type geometry={vertices:float array;indices:int array;color:int32}
type image={resource_id:int;source:rect;destination:rect}
type glyph={glyph_id:int;x:float;y:float}
type glyphs={resource_id:int;color:int32;glyphs:glyph array}
type debug_text={x:float;y:float;text:string;color:int32}
type command=Clear of int32|Set_blend of Composite.blend|Push_clip of rect|Pop_clip|Push_transform of transform|Pop_transform|Geometry of geometry|Image of image|Glyphs of glyphs|Debug_text of debug_text
type batch_kind=State|Geometry_batch of int32|Image_batch of int|Glyph_batch of int|Debug_text_batch of int32
type batch={first:int;count:int;kind:batch_kind}
type t={commands:command array;batches:batch array}
type error=Non_finite|Invalid_extent|Invalid_cardinality|Invalid_index of int|Invalid_resource_id of int|Invalid_glyph_id of int|Invalid_debug_text|Unbalanced_clip|Unbalanced_transform|Complexity_limit
let finite=Float.is_finite
let valid_rect (r:rect)=finite r.x&&finite r.y&&finite r.width&&finite r.height&&r.width>=0.&&r.height>=0.
let copy_string value=Bytes.to_string(Bytes.of_string value)
let copy_command=function Clear c->Clear c|Set_blend b->Set_blend b|Push_clip r->Push_clip r|Pop_clip->Pop_clip|Push_transform t->Push_transform t|Pop_transform->Pop_transform|Geometry g->Geometry{g with vertices=Array.copy g.vertices;indices=Array.copy g.indices}|Image i->Image i|Glyphs g->Glyphs{g with glyphs=Array.copy g.glyphs}|Debug_text d->Debug_text{d with text=copy_string d.text}
let kind=function Clear _|Set_blend _|Push_clip _|Pop_clip|Push_transform _|Pop_transform->State|Geometry g->Geometry_batch g.color|Image i->Image_batch i.resource_id|Glyphs g->Glyph_batch g.resource_id|Debug_text d->Debug_text_batch d.color
let same_kind a b=match a,b with State,State->false|Geometry_batch x,Geometry_batch y->x=y|Image_batch x,Image_batch y->x=y|Glyph_batch x,Glyph_batch y->x=y|Debug_text_batch x,Debug_text_batch y->x=y|_->false
let create_internal ~copy input=
  if Array.length input>1_048_576 then Error Complexity_limit else
  let clip=ref 0 and transform=ref 0 and failure=ref None in
  let fail e=if !failure=None then failure:=Some e in
  Array.iter(fun command->match command with
  |Clear _|Set_blend _->()
  |Push_clip r->if valid_rect r then incr clip else fail(if List.for_all finite[r.x;r.y;r.width;r.height]then Invalid_extent else Non_finite)
  |Pop_clip->if !clip=0 then fail Unbalanced_clip else decr clip
  |Push_transform t->if List.for_all finite[t.xx;t.xy;t.yx;t.yy;t.tx;t.ty]then incr transform else fail Non_finite
  |Pop_transform->if !transform=0 then fail Unbalanced_transform else decr transform
  |Geometry g->if Array.length g.vertices mod 2<>0||Array.length g.indices mod 3<>0 then fail Invalid_cardinality else if not(Array.for_all finite g.vertices)then fail Non_finite else Array.iter(fun i->if i<0||i>=Array.length g.vertices/2 then fail(Invalid_index i))g.indices
  |Image i->if i.resource_id<=0 then fail(Invalid_resource_id i.resource_id)else if not(valid_rect i.source&&valid_rect i.destination)then fail(if List.for_all finite[i.source.x;i.source.y;i.source.width;i.source.height;i.destination.x;i.destination.y;i.destination.width;i.destination.height]then Invalid_extent else Non_finite)
  |Glyphs g->if g.resource_id<=0 then fail(Invalid_resource_id g.resource_id)else Array.iter(fun p->if p.glyph_id<0 then fail(Invalid_glyph_id p.glyph_id)else if not(finite p.x&&finite p.y)then fail Non_finite)g.glyphs
  |Debug_text d->if not(finite d.x&&finite d.y)then fail Non_finite else if String.length d.text>Debug_font.max_text_length then fail Invalid_debug_text)input;
  if !failure=None&& !clip<>0 then failure:=Some Unbalanced_clip;
  if !failure=None&& !transform<>0 then failure:=Some Unbalanced_transform;
  match !failure with Some e->Error e|None->
    let commands=if copy then Array.map copy_command input else input in
    let built=ref[]in Array.iteri(fun index command->let k=kind command in match !built with {first;count;kind=old}::rest when same_kind old k->built:={first;count=count+1;kind=old}::rest|_->built:={first=index;count=1;kind=k}::!built)commands;
    Ok{commands;batches=Array.of_list(List.rev !built)}
let create input=create_internal~copy:true input
let commands t=Array.map copy_command t.commands
let batches t=Array.copy t.batches
module Private=struct
  let commands_readonly t=t.commands
  let create_owned input=create_internal~copy:false input
end
module Encoder=struct
 type t={mutable bytes:bytes;mutable length:int}
 let create()={bytes=Bytes.create 256;length=0}
 let ensure t n=if n>Bytes.length t.bytes-t.length then(let size=ref(Bytes.length t.bytes)in while !size<t.length+n do size:=2* !size done;let b=Bytes.create !size in Bytes.blit t.bytes 0 b 0 t.length;t.bytes<-b)
 let byte t x=ensure t 1;Bytes.set t.bytes t.length(Char.chr(x land 255));t.length<-t.length+1
 let i32 t x=for n=0 to 3 do byte t Int32.(to_int(logand(shift_right_logical x(8*n))0xffl))done
 let i64 t x=for n=0 to 7 do byte t Int64.(to_int(logand(shift_right_logical x(8*n))0xffL))done
 let int t x=i64 t(Int64.of_int x)
 let float t x=i64 t(Int64.bits_of_float x)
 let string t value=int t(String.length value);String.iter(fun character->byte t(Char.code character))value
 let result t=Bytes.sub t.bytes 0 t.length
end
let serialize value=let e=Encoder.create()in Encoder.i32 e 0x52324931l;Encoder.int e(Array.length value.commands);let rect (r:rect)=List.iter(Encoder.float e)[r.x;r.y;r.width;r.height]and transform (t:transform)=List.iter(Encoder.float e)[t.xx;t.xy;t.yx;t.yy;t.tx;t.ty]in Array.iter(function Clear c->Encoder.byte e 0;Encoder.i32 e c|Set_blend b->Encoder.byte e 8;Encoder.byte e(match b with Composite.Source_over->0|Copy->1|Replace->2|Alpha->3|Add->4|Multiply->5|Screen->6|Subtract->7)|Push_clip r->Encoder.byte e 1;rect r|Pop_clip->Encoder.byte e 2|Push_transform t->Encoder.byte e 3;transform t|Pop_transform->Encoder.byte e 4|Geometry g->Encoder.byte e 5;Encoder.i32 e g.color;Encoder.int e(Array.length g.vertices);Array.iter(Encoder.float e)g.vertices;Encoder.int e(Array.length g.indices);Array.iter(Encoder.int e)g.indices|Image i->Encoder.byte e 6;Encoder.int e i.resource_id;rect i.source;rect i.destination|Glyphs g->Encoder.byte e 7;Encoder.int e g.resource_id;Encoder.i32 e g.color;Encoder.int e(Array.length g.glyphs);Array.iter(fun p->Encoder.int e p.glyph_id;Encoder.float e p.x;Encoder.float e p.y)g.glyphs|Debug_text d->Encoder.byte e 9;Encoder.float e d.x;Encoder.float e d.y;Encoder.i32 e d.color;Encoder.string e d.text)value.commands;Encoder.result e
let hash value=let h=ref 0xcbf29ce484222325L in Bytes.iter(fun c->h:=Int64.mul(Int64.logxor !h(Int64.of_int(Char.code c)))0x100000001b3L)(serialize value);!h
