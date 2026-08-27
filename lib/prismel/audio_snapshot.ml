type kind = Sample | Music
type t = { id:int; generation:int64; kind:kind; encoded:bytes }
type entry = { key:Obj.t; mutable value:t }
let next_id=Atomic.make 1
let entries:entry list ref=ref[]
let find key=List.find_opt(fun entry->entry.key==key)!entries|>Option.map(fun e->e.value)
let register key ~kind encoded=
  let value={id=Atomic.fetch_and_add next_id 1;generation=1L;kind;encoded=Bytes.copy encoded}in
  entries:={key;value}::List.filter(fun entry->entry.key!=key)!entries
let update key encoded=match List.find_opt(fun entry->entry.key==key)!entries with
  |None->()
  |Some entry->entry.value<-{entry.value with generation=Int64.succ entry.value.generation;encoded=Bytes.copy encoded}
let remove key=entries:=List.filter(fun entry->entry.key!=key)!entries
let live_bytes()=List.fold_left(fun total entry->total+Bytes.length entry.value.encoded)0!entries
