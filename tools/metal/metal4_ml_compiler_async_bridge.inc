extern "C" CAMLprim value caml_prismel_metal4_ml_compile_async(value rc,value rd){
  CAMLparam2(rc,rd);CAMLlocal1(raw);
  if(@available(macOS 26.0,*)){@try{
    id<MTL4Compiler>c=object_of_handle(rc,Handle_kind::Compiler);
    MTL4MachineLearningPipelineDescriptor*d=object_of_handle(rd,Handle_kind::Machine_learning_descriptor4);
    PrismelMetalCompilerTaskState*s=[[PrismelMetalCompilerTaskState alloc]
      initWithKind:PrismelMetalCompilerResultMachineLearningPipeline label:d.label reflectionRequested:YES];
    s.retainedInputs=d;__weak PrismelMetalCompilerTaskState*w=s;
    id<MTL4CompilerTask>task=[c newMachineLearningPipelineStateWithDescriptor:d completionHandler:^(id<MTL4MachineLearningPipelineState>p,NSError*e){[w finishWithObject:p error:e];}];
    if(!task)CAMLreturn(result_error_text("Metal returned no ML compiler task"));
    s.task=task;raw=allocate_handle(s,Handle_kind::Compiler_task);CAMLreturn(result_ok(raw));
  }@catch(NSException*x){CAMLreturn(result_error(x.reason));}}
  CAMLreturn(result_error_text("Metal 4 ML requires macOS 26"));
}

extern "C" CAMLprim value caml_prismel_metal4_ml_task_take(value rt){
  CAMLparam1(rt);CAMLlocal5(raw,info,pair,completion,option);
  if(@available(macOS 26.0,*)){@try{
    PrismelMetalCompilerTaskState*s=object_of_handle(rt,Handle_kind::Compiler_task);
    if(s.resultKind!=PrismelMetalCompilerResultMachineLearningPipeline)
      CAMLreturn(result_error_text("compiler task does not contain an ML pipeline"));
    id object=nil;NSError*error=nil;PrismelMetalCompilerResultState state=[s takeObject:&object error:&error];
    if(state==PrismelMetalCompilerResultPending)CAMLreturn(result_ok(Val_none));
    if(state==PrismelMetalCompilerResultConsumed)CAMLreturn(result_error_text("compiler task completion was already consumed"));
    if(state==PrismelMetalCompilerResultFailure)completion=result_error(error_description(error,@"ML compilation failed"));
    else{id<MTL4MachineLearningPipelineState>p=object;
      if(p.device.registryID!=s.task.compiler.device.registryID)completion=result_error_text("ML pipeline belongs to another device");
      else{raw=allocate_handle(p,Handle_kind::Machine_learning_pipeline4);info=caml_alloc_tuple(4);
        Store_field(info,0,copy_optional_string(p.label));Store_field(info,1,caml_copy_int64(p.device.registryID));
        Store_field(info,2,caml_copy_int64(p.intermediatesHeapSize));Store_field(info,3,p.reflection?copy_bindings(p.reflection.bindings):Atom(0));
        pair=caml_alloc_tuple(2);Store_field(pair,0,raw);Store_field(pair,1,info);completion=result_ok(pair);}}
    option=caml_alloc(1,0);Store_field(option,0,completion);CAMLreturn(result_ok(option));
  }@catch(NSException*x){CAMLreturn(result_error(x.reason));}}
  CAMLreturn(result_error_text("Metal 4 ML requires macOS 26"));
}
