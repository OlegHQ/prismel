extern "C" CAMLprim value caml_prismel_metal_layer10_snapshot(value raw_layer) {
  CAMLparam1(raw_layer);
  CAMLlocal5(result, tuple, preferred, properties, pair);
  CAMLlocal2(key, text);
  @autoreleasepool { @try {
    CAMetalLayer *layer = object_of_handle(raw_layer, Handle_kind::Metal_layer);
    preferred = Val_none;
    if (@available(macOS 10.15, *)) {
      id<MTLDevice> device = layer.preferredDevice;
      if (device != nil) {
        value registry = caml_copy_int64((int64_t)device.registryID);
        preferred = caml_alloc(1, 0);
        Store_field(preferred, 0, registry);
      }
    }
    properties = Val_emptylist;
    if (@available(macOS 13.0, *)) {
      NSDictionary *dictionary = layer.developerHUDProperties;
      NSArray *keys = [[dictionary allKeys] sortedArrayUsingSelector:@selector(compare:)];
      for (NSInteger index = (NSInteger)keys.count - 1; index >= 0; --index) {
        id native_key = keys[(NSUInteger)index];
        id native_value = dictionary[native_key];
        if (![native_key isKindOfClass:[NSString class]] ||
            ![native_value isKindOfClass:[NSString class]])
          CAMLreturn(result_error_text("developer HUD properties must contain string keys and values"));
        key = caml_copy_string([(NSString *)native_key UTF8String]);
        text = caml_copy_string([(NSString *)native_value UTF8String]);
        pair = caml_alloc_tuple(2);
        Store_field(pair, 0, key);
        Store_field(pair, 1, text);
        value cell = caml_alloc(2, 0);
        Store_field(cell, 0, pair);
        Store_field(cell, 1, properties);
        properties = cell;
      }
    }
    bool has_residency = false;
    if (@available(macOS 26.0, *)) has_residency = layer.residencySet != nil;
    tuple = caml_alloc_tuple(3);
    Store_field(tuple, 0, preferred);
    Store_field(tuple, 1, properties);
    Store_field(tuple, 2, Val_bool(has_residency));
    result = result_ok(tuple);
    CAMLreturn(result);
  } @catch (NSException *exception) { CAMLreturn(result_error(exception.reason)); } }
}

extern "C" CAMLprim value caml_prismel_metal_layer10_set_hud(value raw_layer,
                                                               value raw_properties) {
  CAMLparam2(raw_layer, raw_properties);
  if (@available(macOS 13.0, *)) {
    @autoreleasepool { @try {
      CAMetalLayer *layer = object_of_handle(raw_layer, Handle_kind::Metal_layer);
      NSMutableDictionary<NSString *, NSString *> *dictionary = [NSMutableDictionary dictionary];
      for (value cursor = raw_properties; cursor != Val_emptylist; cursor = Field(cursor, 1)) {
        value pair = Field(cursor, 0);
        NSString *key = string_from_ocaml(Field(pair, 0));
        NSString *text = string_from_ocaml(Field(pair, 1));
        if (key.length == 0) CAMLreturn(result_error_text("developer HUD property key is empty"));
        if (dictionary[key] != nil) CAMLreturn(result_error_text("duplicate developer HUD property"));
        dictionary[key] = text;
      }
      layer.developerHUDProperties = dictionary;
      CAMLreturn(result_unit());
    } @catch (NSException *exception) { CAMLreturn(result_error(exception.reason)); } }
  }
  CAMLreturn(result_error_text("developer HUD properties require macOS 13"));
}
