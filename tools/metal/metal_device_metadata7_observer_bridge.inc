struct PrismelDeviceObserverState{
  std::mutex mutex;bool active=true;value*root=nullptr;id observer=nil;
};
struct PrismelDeviceObserverToken{std::shared_ptr<PrismelDeviceObserverState>state;};

static void prismel_device_observer_fire(
    const std::shared_ptr<PrismelDeviceObserverState>&state,id<MTLDevice>device,
    MTLDeviceNotificationName name){
  int registered=caml_c_thread_register();caml_acquire_runtime_system();
  std::lock_guard<std::mutex>lock(state->mutex);
  if(state->active&&state->root){
    CAMLparam0();CAMLlocal3(raw,event,pair);
    raw=allocate_handle(device,Handle_kind::Device);
    event=copy_optional_string(name);pair=caml_alloc_tuple(2);
    Store_field(pair,0,raw);Store_field(pair,1,event);
    caml_callback_exn(*state->root,pair);CAMLdrop;
  }
  caml_release_runtime_system();if(registered)caml_c_thread_unregister();
}

extern "C" CAMLprim value caml_prismel_metal_device_observer_create(value callback){
  CAMLparam1(callback);CAMLlocal4(items,raw,token,result);
  auto state=std::make_shared<PrismelDeviceObserverState>();
  state->root=(value*)malloc(sizeof(value));if(!state->root)CAMLreturn(result_error_text("unable to root device observer"));
  *state->root=callback;caml_register_generational_global_root(state->root);
  @try{id observer=nil;auto captured=state;
    NSArray<id<MTLDevice>>*devices=MTLCopyAllDevicesWithObserver(&observer,
      ^(id<MTLDevice>d,MTLDeviceNotificationName n){prismel_device_observer_fire(captured,d,n);});
    if(!observer){caml_remove_generational_global_root(state->root);free(state->root);state->root=nullptr;CAMLreturn(result_error_text("Metal returned no device observer"));}
    state->observer=observer;items=caml_alloc(devices.count,0);
    for(NSUInteger i=0;i<devices.count;i++){raw=allocate_handle(devices[i],Handle_kind::Device);Store_field(items,i,raw);}
    auto*t=new PrismelDeviceObserverToken{state};token=caml_copy_nativeint((intnat)t);
    result=caml_alloc_tuple(2);Store_field(result,0,items);Store_field(result,1,token);CAMLreturn(result_ok(result));
  }@catch(NSException*x){std::lock_guard<std::mutex>lock(state->mutex);state->active=false;if(state->root){caml_remove_generational_global_root(state->root);free(state->root);state->root=nullptr;}CAMLreturn(result_error(x.reason));}
}

extern "C" CAMLprim value caml_prismel_metal_device_observer_cancel(value raw_token){
  CAMLparam1(raw_token);auto*t=(PrismelDeviceObserverToken*)Nativeint_val(raw_token);
  if(!t)CAMLreturn(result_error_text("device observer token is null"));auto state=t->state;
  @try{if(state->observer)MTLRemoveDeviceObserver(state->observer);state->observer=nil;
    {std::lock_guard<std::mutex>lock(state->mutex);if(!state->active){delete t;CAMLreturn(result_error_text("device observer is already cancelled"));}state->active=false;if(state->root){caml_remove_generational_global_root(state->root);free(state->root);state->root=nullptr;}}
    delete t;CAMLreturn(result_unit());
  }@catch(NSException*x){CAMLreturn(result_error(x.reason));}
}
