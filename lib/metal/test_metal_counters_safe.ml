open Metal
let get=function Ok x->x|Error e->failwith(Format.asprintf"%a"pp_error e)
let ()=match Device.system_default()with Error _->print_endline"counters22: skipped"|Ok device->
 let sets=get(Counters.sets device)in
 if List.exists(fun(s:Counters.set)->s.name=""||s.counters=[])sets then failwith"empty counter metadata";
 match sets with []->print_endline"counters22: no sets"|set::_->
 let descriptor=get(Counters.Descriptor.create device~set_name:set.name~label:"prismel-counters22"~sample_count:2L~storage:Buffer.Shared())in
 let samples=get(Counters.Descriptor.create_buffer descriptor)in
 if Counters.Descriptor.sample_count descriptor<>2L||Counters.Descriptor.label descriptor<>Some"prismel-counters22"then failwith"counter descriptor drift";
 if get(Counters.supports device Counters.Blit_boundary)then(let queue=get(Command_queue.create device)in let command=get(Command_buffer.create queue())in let encoder=get(Blit_encoder.create command)in get(Resource100.Sample_buffer.sample encoder samples~index:0L);get(Resource100.Sample_buffer.sample encoder samples~index:1L);get(Blit_encoder.end_encoding encoder);get(Command_buffer.commit command);get(Command_buffer.wait_until_completed command);if Bytes.length(get(Counters.resolve samples~first:0L~count:2L))=0 then failwith"empty counter resolve";get(Command_buffer.destroy command);get(Command_queue.destroy queue))else(match Counters.resolve samples~first:2L~count:1L with Error e when e.kind=Invalid_argument->()|_->failwith"counter capability/range rejection drift");
 get(Resource100.Sample_buffer.destroy samples);get(Counters.Descriptor.destroy descriptor);get(Device.destroy device);print_endline"counters22 safe: execute-or-capability-reject ok"
