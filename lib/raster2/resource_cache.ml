type key=Image of{id:int64;generation:int64}|Glyph of{font:int64;codepoint:int;density:int}|Geometry of{id:int64;version:int64}
type reason=Replaced|Evicted|Invalidated|Cleared type error=Invalid_capacity|Invalid_key
type 'a node={key:key;mutable value:'a;mutable age:int64}
type 'a t={capacity:int;table:(key,'a node)Hashtbl.t;destroy:key->'a->reason->unit;mutable clock:int64;mutable errors:int}
let valid=function Image{id;generation}|Geometry{id;version=generation}->id>=0L&&generation>=0L|Glyph{font;codepoint;density}->font>=0L&&codepoint>=0&&codepoint<=0x10ffff&&density>0
let create~capacity~on_destroy=if capacity<=0 then Error Invalid_capacity else Ok{capacity;table=Hashtbl.create capacity;destroy=on_destroy;clock=1L;errors=0}
let tick t=let x=t.clock in t.clock<-Int64.succ x;x
let notify t n why=try t.destroy n.key n.value why with _->t.errors<-t.errors+1
let oldest t=Hashtbl.fold(fun _ n best->match best with None->Some n|Some b when n.age<b.age->Some n|_->best)t.table None
let insert t key value=if not(valid key)then Error Invalid_key else((match Hashtbl.find_opt t.table key with Some n->let old={n with value=n.value}in n.value<-value;n.age<-tick t;notify t old Replaced|None->let n={key;value;age=tick t}in Hashtbl.add t.table key n;if Hashtbl.length t.table>t.capacity then match oldest t with None->()|Some x->Hashtbl.remove t.table x.key;notify t x Evicted);Ok())
let get t key=match Hashtbl.find_opt t.table key with None->None|Some n->n.age<-tick t;Some n.value
let invalidate t predicate=let xs=Hashtbl.fold(fun _ n a->if predicate n.key then n::a else a)t.table[]|>List.sort(fun a b->Int64.compare a.age b.age)in List.iter(fun n->Hashtbl.remove t.table n.key;notify t n Invalidated)xs
let invalidate_image t ~id=invalidate t(function Image x->x.id=id|_->false)
let invalidate_density t ~density=invalidate t(function Glyph x->x.density=density|_->false)
let clear t=let xs=Hashtbl.fold(fun _ n a->n::a)t.table[]|>List.sort(fun a b->Int64.compare a.age b.age)in Hashtbl.clear t.table;List.iter(fun n->notify t n Cleared)xs
let length t=Hashtbl.length t.table
let keys_lru t=Hashtbl.fold(fun _ n a->n::a)t.table[]|>List.sort(fun a b->Int64.compare a.age b.age)|>List.map(fun n->n.key)
let callback_errors t=t.errors
