/* Exact CAML hookup for the prepared mesh/tile and counter materializers.
   The unsafe IO load helper is deliberately not exported. */

static id prismel_optional_typed_handle(value option, Handle_kind kind) {
  return Is_block(option) ? object_of_handle(Field(option, 0), kind) : nil;
}

static NSArray<id<MTLBinaryArchive>> *prismel_mesh_archives(value raw) {
  std::vector<id<MTLBinaryArchive>> values = binary_archives_of_array(raw);
  return [NSArray arrayWithObjects:values.data() count:values.size()];
}

static NSArray<id<MTLDynamicLibrary>> *prismel_mesh_libraries(value raw) {
  std::vector<id<MTLDynamicLibrary>> values = dynamic_libraries_of_array(raw);
  return [NSArray arrayWithObjects:values.data() count:values.size()];
}

static bool prismel_mesh_objects_from_value(value raw, bool tile,
                                            PrismelMeshTileObjects *objects,
                                            NSString **failure) {
  @try {
    if (tile) {
      objects->tileFunction = object_of_handle(Field(raw, 0), Handle_kind::Function);
      objects->binaryArchives = prismel_mesh_archives(Field(raw, 1));
      objects->preloadedLibraries = prismel_mesh_libraries(Field(raw, 2));
      objects->tileLinkedFunctions = static_cast<MTLLinkedFunctions *>(
          prismel_optional_typed_handle(Field(raw, 3), Handle_kind::Linked_functions));
    } else {
      objects->objectFunction = prismel_optional_typed_handle(Field(raw, 0), Handle_kind::Function);
      objects->meshFunction = object_of_handle(Field(raw, 1), Handle_kind::Function);
      objects->fragmentFunction = prismel_optional_typed_handle(Field(raw, 2), Handle_kind::Function);
      objects->binaryArchives = prismel_mesh_archives(Field(raw, 3));
      objects->objectLinkedFunctions = static_cast<MTLLinkedFunctions *>(
          prismel_optional_typed_handle(Field(raw, 4), Handle_kind::Linked_functions));
      objects->meshLinkedFunctions = static_cast<MTLLinkedFunctions *>(
          prismel_optional_typed_handle(Field(raw, 5), Handle_kind::Linked_functions));
      objects->fragmentLinkedFunctions = static_cast<MTLLinkedFunctions *>(
          prismel_optional_typed_handle(Field(raw, 6), Handle_kind::Linked_functions));
    }
    return true;
  } @catch (NSException *exception) {
    *failure = exception.reason;
    return false;
  }
}

extern "C" CAMLprim value caml_prismel_mesh_pipeline_descriptor(value raw) {
  CAMLparam1(raw); CAMLlocal2(handle, result); @autoreleasepool {
    PrismelMeshTileObjects objects = {}; NSString *failure = nil;
    if (!prismel_mesh_objects_from_value(raw, false, &objects, &failure))
      CAMLreturn(result_error(failure));
    MTLMeshRenderPipelineDescriptor *descriptor =
        prismel_materialize_mesh_descriptor(objects, &failure);
    if (descriptor == nil) CAMLreturn(result_error(failure));
    handle = allocate_handle(descriptor, Handle_kind::Mesh_pipeline_descriptor);
    result = result_ok(handle); CAMLreturn(result);
  }
}

extern "C" CAMLprim value caml_prismel_tile_pipeline_descriptor(value raw) {
  CAMLparam1(raw); CAMLlocal2(handle, result); @autoreleasepool {
    PrismelMeshTileObjects objects = {}; NSString *failure = nil;
    if (!prismel_mesh_objects_from_value(raw, true, &objects, &failure))
      CAMLreturn(result_error(failure));
    MTLTileRenderPipelineDescriptor *descriptor =
        prismel_materialize_tile_descriptor(objects, &failure);
    if (descriptor == nil) CAMLreturn(result_error(failure));
    handle = allocate_handle(descriptor, Handle_kind::Tile_pipeline_descriptor);
    result = result_ok(handle); CAMLreturn(result);
  }
}

extern "C" CAMLprim value caml_prismel_counter_descriptor(
    value raw_set, value raw_count, value raw_label) {
  CAMLparam3(raw_set, raw_count, raw_label); CAMLlocal2(handle, result);
  @autoreleasepool { @try {
    intnat count = Long_val(raw_count);
    if (count <= 0) CAMLreturn(result_error_text("sample count must be positive"));
    id<MTLCounterSet> set = object_of_handle(raw_set, Handle_kind::Counter_set);
    NSString *label = Is_block(raw_label) ? string_from_ocaml(Field(raw_label, 0)) : nil;
    if (Is_block(raw_label) && label == nil)
      CAMLreturn(result_error_text("counter descriptor label is not valid UTF-8"));
    NSString *failure = nil;
    MTLCounterSampleBufferDescriptor *descriptor = prismel_counter_descriptor(
        set, static_cast<NSUInteger>(count), label, &failure);
    if (descriptor == nil) CAMLreturn(result_error(failure));
    handle = allocate_handle(descriptor, Handle_kind::Counter_descriptor);
    result = result_ok(handle); CAMLreturn(result);
  } @catch (NSException *exception) { CAMLreturn(result_error(exception.reason)); } }
}

extern "C" CAMLprim value caml_prismel_io_load_buffer(
    value raw_commands, value raw_destination, value raw_destination_offset,
    value raw_size, value raw_source, value raw_source_offset) {
  CAMLparam5(raw_commands, raw_destination, raw_destination_offset, raw_size,
             raw_source);
  CAMLxparam1(raw_source_offset);
  @autoreleasepool { @try {
    int64_t destination_offset = Int64_val(raw_destination_offset);
    int64_t size = Int64_val(raw_size);
    int64_t source_offset = Int64_val(raw_source_offset);
    if (destination_offset < 0 || size < 0 || source_offset < 0) {
      CAMLreturn(result_error_text("IO load offsets and size must be non-negative"));
    }
    id<MTLIOCommandBuffer> commands = object_of_handle(
        raw_commands, Handle_kind::Io_command_buffer);
    id<MTLBuffer> destination = object_of_handle(
        raw_destination, Handle_kind::Buffer);
    id<MTLIOFileHandle> source = object_of_handle(
        raw_source, Handle_kind::Io_file_handle);
    NSString *failure = nil;
    if (!prismel_io_load_buffer(
            commands, destination, static_cast<NSUInteger>(destination_offset),
            static_cast<NSUInteger>(size), source,
            static_cast<NSUInteger>(source_offset), &failure)) {
      CAMLreturn(result_error(failure));
    }
    CAMLreturn(result_unit());
  } @catch (NSException *exception) { CAMLreturn(result_error(exception.reason)); } }
}

extern "C" CAMLprim value caml_prismel_io_load_buffer_bytecode(
    value *argv, int argn) {
  (void)argn;
  return caml_prismel_io_load_buffer(argv[0], argv[1], argv[2], argv[3],
                                    argv[4], argv[5]);
}
