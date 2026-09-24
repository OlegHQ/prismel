module type RAW=sig type handle
 val node:name:string->arguments:handle list->dependencies:handle list->(handle,string)result
 val graph:name:string->nodes:handle list->output:handle->attributes:handle list->(handle,string)result
 val compile:library:handle->descriptor:handle->callback:(handle option->string option->unit)->(unit,string)result
 val retain:handle->unit val release:handle->unit end
module Make(R:RAW)=struct
 let unwind xs=List.iter R.release xs
 let build f xs=List.iter R.retain xs;match f()with Ok _ as x->x|Error _ as e->unwind xs;e
 let node~name~arguments~dependencies=build(fun()->R.node~name~arguments~dependencies)(arguments@dependencies)
 let graph~name~nodes~output~attributes=build(fun()->R.graph~name~nodes~output~attributes)(output::nodes@attributes)
 let compile~library~descriptor callback=R.retain library;R.retain descriptor;let fired=ref false in let finish fn err=if not !fired then(fired:=true;R.release descriptor;R.release library;callback fn err)in match R.compile~library~descriptor~callback:finish with Ok()->Ok()|Error _ as e->finish None(Some"submission failed");e
end
