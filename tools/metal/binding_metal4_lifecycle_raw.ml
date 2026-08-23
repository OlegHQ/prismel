type state=Initial|Recording|Ended|Committed|Complete
module type RAW=sig type handle val begin_:handle->allocator:handle->(unit,string)result val end_:handle->(unit,string)result val commit:handle->callback:(unit->unit)->(unit,string)result val retain:handle->unit val release:handle->unit end
module Make(R:RAW)=struct
 type t={raw:R.handle;allocator:R.handle;mutable state:state;mutable held:R.handle list}
 let create raw allocator={raw;allocator;state=Initial;held=[]}
 let begin_ t=if t.state<>Initial then Error"Metal4 command buffer already begun"else(R.retain t.allocator;match R.begin_ t.raw~allocator:t.allocator with Ok()->t.state<-Recording;Ok()|Error _ as e->R.release t.allocator;e)
 let retain t x=if t.state<>Recording then Error"Metal4 command buffer not recording"else(R.retain x;t.held<-x::t.held;Ok())
 let end_ t=if t.state<>Recording then Error"Metal4 encoder/buffer not recording"else match R.end_ t.raw with Error _ as e->e|Ok()->t.state<-Ended;Ok()
 let commit t callback=if t.state<>Ended then Error"Metal4 command buffer must end before commit"else let fired=ref false in let finish()=if not !fired then(fired:=true;List.iter R.release t.held;t.held<-[];R.release t.allocator;t.state<-Complete;callback())in match R.commit t.raw~callback:finish with Ok()->t.state<-Committed;Ok finish|Error _ as e->finish();e
end
