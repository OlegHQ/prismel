open Metal
let get=function Ok x->x|Error e->failwith(Format.asprintf"%a"pp_error e)
let run () =match Device.system_default()with Error _->print_endline"compute-pipeline11: skipped"|Ok device->
  let source="#include <metal_stdlib>\nusing namespace metal; kernel void cp11(device uint *out [[buffer(0)]], uint i [[thread_position_in_grid]]) { out[i] = i + 7; }"in
  let library=get(Library.compile_source~device source)in let function_=get(Function.find~library "cp11")in
  let pipeline=get(Compute_pipeline.create~reflection:true function_)in
  (match Compute_pipeline.bindings pipeline with Some(_::_)->()|_->failwith"missing immutable reflection snapshot")
