module type RAW=sig type handle
 val load:commands:handle->destination:handle->destination_offset:int->size:int->source:handle->source_offset:int->(unit,string)result
 val add_completed:handle->(unit->unit)->(unit,string)result
 val retain:handle->unit val release:handle->unit end
module Make(R:RAW)=struct
 let load~commands~destination~destination_offset~size~source~source_offset=if destination_offset<0||source_offset<0||size<0 then Error"negative IO range"else let held=[commands;destination;source]in List.iter R.retain held;match R.load~commands~destination~destination_offset~size~source~source_offset with Ok()->Ok held|Error _ as e->List.iter R.release held;e
 let completed command callback=R.retain command;let fired=ref false in let finish()=if not !fired then(fired:=true;R.release command;callback())in match R.add_completed command finish with Ok()->Ok finish|Error _ as e->finish();e
end
