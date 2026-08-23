module type RAW=sig type handle
 val copy:encoder:handle->source:handle->source_offset:int->destination:handle->destination_offset:int->size:int->(unit,string)result
 val compile:compiler:handle->descriptor:handle->callback:(handle option->string option->unit)->(handle,string)result
 val retain:handle->unit val release:handle->unit end
module Make(R:RAW)=struct
 let range~length~offset~size~alignment=alignment>0&&offset>=0&&size>=0&&offset mod alignment=0&&size mod alignment=0&&offset<=length-size
 let copy~encoder~encoder_device~source~source_device~source_length~source_offset~destination~destination_device~destination_length~destination_offset~size~alignment=
  if source_device<>encoder_device||destination_device<>encoder_device then Error"Metal4 resource belongs to another device"
  else if not(range~length:source_length~offset:source_offset~size~alignment&&range~length:destination_length~offset:destination_offset~size~alignment)then Error"Metal4 buffer range/alignment"else let held=[encoder;source;destination]in List.iter R.retain held;match R.copy~encoder~source~source_offset~destination~destination_offset~size with Ok()->Ok held|Error _ as e->List.iter R.release held;e
 let compile~compiler~descriptor callback=let held=[compiler;descriptor]in List.iter R.retain held;let fired=ref false in let finish state error=if not !fired then(fired:=true;List.iter R.release held;callback state error)in match R.compile~compiler~descriptor~callback:finish with Ok task->R.retain task;Ok(task,finish)|Error _ as e->finish None(Some"compiler submission failed");e
end
