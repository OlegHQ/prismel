type error=Invalid_capacity|Invalid_reservation|Capacity_exceeded
type t={hard:int;mutable bytes:bytes;mutable used:int;mutable high:int;mutable growths:int;mutable generation:int}
type slice={arena:t;offset:int;length:int;generation:int}
type metrics={capacity:int;used:int;high_water:int;growths:int}
let create ~initial_capacity ~hard_capacity=if initial_capacity<0||hard_capacity<0||initial_capacity>hard_capacity then Error Invalid_capacity else Ok{hard=hard_capacity;bytes=Bytes.create initial_capacity;used=0;high=0;growths=0;generation=1}
let power x=x>0&&x land(x-1)=0
let reserve (t:t) ~alignment ~length=if length<0||not(power alignment)then Error Invalid_reservation else let mask=alignment-1 in if t.used>max_int-mask then Error Capacity_exceeded else let offset=(t.used+mask)land(lnot mask)in if offset>t.hard||length>t.hard-offset then Error Capacity_exceeded else let needed=offset+length in if needed>Bytes.length t.bytes then(let rec grow n=if n>=needed then n else if n>=t.hard then t.hard else grow(min t.hard(max 1(n*2)))in let capacity=grow(Bytes.length t.bytes)in let replacement=Bytes.create capacity in Bytes.blit t.bytes 0 replacement 0 t.used;t.bytes<-replacement;t.growths<-t.growths+1);t.used<-needed;t.high<-max t.high needed;Ok{arena=t;offset;length;generation=t.generation}
let reset (t:t)=t.used<-0;t.generation<-t.generation+1
let metrics (t:t)={capacity=Bytes.length t.bytes;used=t.used;high_water=t.high;growths=t.growths}
let slice_offset s=s.offset and slice_length s=s.length
let live s=s.generation=s.arena.generation
let fill s c=if live s then Bytes.fill s.arena.bytes s.offset s.length c
let set s i c=if not(live s)||i<0||i>=s.length then Error Invalid_reservation else(Bytes.set s.arena.bytes(s.offset+i)c;Ok())
let get s i=if not(live s)||i<0||i>=s.length then Error Invalid_reservation else Ok(Bytes.get s.arena.bytes(s.offset+i))
let snapshot s=if not(live s)then Bytes.empty else Bytes.sub s.arena.bytes s.offset s.length
