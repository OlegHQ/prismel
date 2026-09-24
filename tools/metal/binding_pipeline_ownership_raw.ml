module type RAW=sig
 type handle
 val render_descriptor:device:handle->vertex:handle->fragment:handle option->dependencies:handle list->(handle,string)result
 val compute_descriptor:device:handle->compute:handle->dependencies:handle list->(handle,string)result
 val release:handle->unit
end
module Make(R:RAW)=struct
 let build create retained=match create()with Ok x->Ok x|Error _ as e->List.iter R.release retained;e
 let render ~device ~vertex ~fragment ~dependencies=
  build(fun()->R.render_descriptor~device~vertex~fragment~dependencies)
   (device::vertex::dependencies@Option.to_list fragment)
 let compute ~device ~compute ~dependencies=
  build(fun()->R.compute_descriptor~device~compute~dependencies)(device::compute::dependencies)
end
module type EXTERNALS=sig
 type handle
 external render_pipeline_descriptor:'a->(handle,string)result="caml_prismel_render_pipeline_descriptor"
 external compute_pipeline_descriptor:'a->(handle,string)result="caml_prismel_compute_pipeline_descriptor"
end
