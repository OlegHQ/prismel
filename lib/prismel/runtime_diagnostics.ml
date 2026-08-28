type t={active:bool;resource_count:int;cache_entries:int;
  release_queue_pending:int option;release_queue_live_handles:int option;
  release_queue_total_created:int64 option;release_queue_total_released:int64 option}
type release_queue={pending:int;live_handles:int;total_created:int64;total_released:int64}
let native_release_queue()=Option.map(fun(pending,live_handles,total_created,total_released)->
  {pending;live_handles;total_created;total_released})(Prismel_next_execution.native_release_queue())
let empty={active=false;resource_count=0;cache_entries=0;release_queue_pending=None;
  release_queue_live_handles=None;release_queue_total_created=None;
  release_queue_total_released=None}
let current : Prismel_next_execution.t option ref=ref None
let last=ref empty
let convert (x:Prismel_next_execution.diagnostics)=
  {active=x.active;resource_count=x.resource_count;cache_entries=x.cache_entries;
   release_queue_pending=x.release_queue_pending;
   release_queue_live_handles=x.release_queue_live_handles;
   release_queue_total_created=x.release_queue_total_created;
   release_queue_total_released=x.release_queue_total_released}
module Private=struct
  let install value=current:=Some value;last:=convert(Prismel_next_execution.diagnostics value)
  let record value=last:=convert(Prismel_next_execution.diagnostics value);current:=None
end
let snapshot()=match!current with Some value->convert(Prismel_next_execution.diagnostics value)|None-> !last
