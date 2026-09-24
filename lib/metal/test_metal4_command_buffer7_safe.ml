open Metal
let get=function Ok x->x|Error e->failwith(Format.asprintf "%a" pp_error e)
let ()=match Device.system_default()with Error _->print_endline"MTL4CommandBuffer7 safe: skipped"|Ok device->
 match Command4.Allocator.create device with Error _->ignore(Device.destroy device);print_endline"MTL4CommandBuffer7 safe: skipped"|Ok allocator->
 let log=get(Command4.Log_state.create device)in
 let options=get(Command4.Command_buffer_options.create device)in
 get(Command4.Command_buffer_options.set_log_state options(Some log));
 (match Command4.Command_buffer_options.log_state options with Some returned when returned==log->()|_->failwith"log-state identity");
 (match Command4.Log_state.destroy log with Error e when e.kind=Parent_has_dependents->()|_->failwith"log-state retention");
 let commands=get(Command4.Command_buffer.create allocator~options())in
 (match Command4.Command_buffer_options.destroy options with Error e when e.kind=Parent_has_dependents->()|_->failwith"options retention");
 get(Command4.Command_buffer.end_recording commands);
 get(Command4.Command_buffer.destroy commands);get(Command4.Command_buffer_options.destroy options);get(Command4.Log_state.destroy log);get(Command4.Allocator.reset allocator);get(Command4.Allocator.destroy allocator);get(Device.destroy device);
 print_endline"MTL4CommandBuffer7 safe: exact7 options/log/begin/encoder state ownership passed"
