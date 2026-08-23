module Mock=struct
 type handle=int
 let released=ref[] and fail=ref false
 let result()=if !fail then Error"native failure"else Ok 99
 let mesh_descriptor ~function_:_ ~mesh_function:_ ~fragment_function:_ ~archives:_ ~linked:_=result()
 let tile_descriptor ~tile_function:_ ~archives:_ ~libraries:_ ~linked:_=result()
 let set_buffer _ ~index:_ _=Ok() let set_attachment _ ~index:_ _=Ok()
 let release h=released:=h::!released
end
module S=Binding_mesh_tile_ownership_raw.Make(Mock)
let ()=Mock.fail:=true;(match S.tile ~tile_function:1 ~archives:[2] ~libraries:[3] ~linked:[4]with Error _->()|Ok _->failwith"failure accepted");if List.sort compare!(Mock.released)<>[1;2;3;4]then failwith"partial retain unwind"
