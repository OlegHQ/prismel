module Mock=struct type handle=int let released=ref[]and fail=ref true
 let result()=if !fail then Error"native failure"else Ok 99
 let render_descriptor~device:_~vertex:_~fragment:_~dependencies:_=result()
 let compute_descriptor~device:_~compute:_~dependencies:_=result()
 let release x=released:=x::!released end
module S=Binding_pipeline_ownership_raw.Make(Mock)
let ()=(match S.render~device:1~vertex:2~fragment:(Some 3)~dependencies:[4;5]with Error _->()|Ok _->failwith"failure accepted");if List.sort compare!(Mock.released)<>[1;2;3;4;5]then failwith"render unwind";Mock.released:=[];(match S.compute~device:1~compute:2~dependencies:[3]with Error _->()|Ok _->failwith"failure accepted");if List.sort compare!(Mock.released)<>[1;2;3]then failwith"compute unwind"
