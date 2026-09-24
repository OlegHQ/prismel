/* Architecture5 immutable snapshot. The safe layer copies the SDK name before
   the autorelease pool drains and never exposes the MTLArchitecture pointer. */
extern "C" CAMLprim value caml_prismel_metal_device_architecture_name(value raw_device){
  CAMLparam1(raw_device);CAMLlocal2(name,result);
  if(@available(macOS 14.0,*)){
    @try{id<MTLDevice>device=object_of_handle(raw_device,Handle_kind::Device);
      MTLArchitecture*architecture=device.architecture;
      if(!architecture||!architecture.name.length)
        CAMLreturn(result_error_text("Metal returned no architecture name"));
      name=caml_copy_string(architecture.name.UTF8String);result=result_ok(name);
      CAMLreturn(result);
    }@catch(NSException*exception){CAMLreturn(result_error(exception.reason));}
  }
  CAMLreturn(result_error_text("MTLArchitecture requires macOS 14"));
}
