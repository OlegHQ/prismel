static MTLRegion prismel_region_of_value(value v) {
  return MTLRegionMake3D(Int64_val(Field(v, 0)), Int64_val(Field(v, 1)),
                         Int64_val(Field(v, 2)), Int64_val(Field(v, 3)),
                         Int64_val(Field(v, 4)), Int64_val(Field(v, 5)));
}

static value prismel_value_of_region(MTLRegion r) {
  CAMLparam0();
  CAMLlocal1(v);
  v = caml_alloc_tuple(6);
  Store_field(v, 0, caml_copy_int64(r.origin.x));
  Store_field(v, 1, caml_copy_int64(r.origin.y));
  Store_field(v, 2, caml_copy_int64(r.origin.z));
  Store_field(v, 3, caml_copy_int64(r.size.width));
  Store_field(v, 4, caml_copy_int64(r.size.height));
  Store_field(v, 5, caml_copy_int64(r.size.depth));
  CAMLreturn(v);
}

extern "C" CAMLprim value caml_prismel_metal_device_convert_sparse_regions(
    value rh, value rpixels, value rsize, value rmode, value rreverse) {
  CAMLparam5(rh, rpixels, rsize, rmode, rreverse);
  CAMLlocal3(output, item, result);
  @try {
    id<MTLDevice> device = object_of_handle(rh, Handle_kind::Device);
    const mlsize_t count = Wosize_val(rpixels);
    std::vector<MTLRegion> input(count), converted(count);
    for (mlsize_t i = 0; i < count; ++i)
      input[i] = prismel_region_of_value(Field(rpixels, i));
    MTLSize tile = MTLSizeMake(Int64_val(Field(rsize, 0)),
                               Int64_val(Field(rsize, 1)),
                               Int64_val(Field(rsize, 2)));
    if (Bool_val(rreverse))
      [device convertSparseTileRegions:input.data() toPixelRegions:converted.data()
                         withTileSize:tile numRegions:count];
    else
      [device convertSparsePixelRegions:input.data() toTileRegions:converted.data()
                          withTileSize:tile
                         alignmentMode:(MTLSparseTextureRegionAlignmentMode)Int_val(rmode)
                            numRegions:count];
    output = caml_alloc(count, 0);
    for (mlsize_t i = 0; i < count; ++i) {
      item = prismel_value_of_region(converted[i]);
      Store_field(output, i, item);
    }
    result = result_ok(output);
    CAMLreturn(result);
  } @catch (NSException *exception) {
    CAMLreturn(result_error(exception.reason));
  }
}

extern "C" CAMLprim value caml_prismel_metal_device_default_sample_positions(
    value rh, value rcount) {
  CAMLparam2(rh, rcount);
  CAMLlocal4(output, item, x, y);
  int64_t requested = Int64_val(rcount);
  if (requested < 0 || requested > 1024)
    CAMLreturn(result_error_text("sample-position count is out of range"));
  @try {
    id<MTLDevice> device = object_of_handle(rh, Handle_kind::Device);
    std::vector<MTLSamplePosition> positions((size_t)requested);
    [device getDefaultSamplePositions:positions.data() count:(NSUInteger)requested];
    output = caml_alloc((mlsize_t)requested, 0);
    for (int64_t i = 0; i < requested; ++i) {
      item = caml_alloc_tuple(2);
      x = caml_copy_double(positions[(size_t)i].x);
      y = caml_copy_double(positions[(size_t)i].y);
      Store_field(item, 0, x); Store_field(item, 1, y);
      Store_field(output, (mlsize_t)i, item);
    }
    CAMLreturn(result_ok(output));
  } @catch (NSException *exception) {
    CAMLreturn(result_error(exception.reason));
  }
}

extern "C" CAMLprim value caml_prismel_metal_device_sample_timestamps(value rh) {
  CAMLparam1(rh); CAMLlocal2(pair, result);
  @try {
    id<MTLDevice> device = object_of_handle(rh, Handle_kind::Device);
    MTLTimestamp cpu = 0, gpu = 0;
    [device sampleTimestamps:&cpu gpuTimestamp:&gpu];
    pair = caml_alloc_tuple(2);
    Store_field(pair, 0, caml_copy_int64((int64_t)cpu));
    Store_field(pair, 1, caml_copy_int64((int64_t)gpu));
    result = result_ok(pair); CAMLreturn(result);
  } @catch (NSException *exception) { CAMLreturn(result_error(exception.reason)); }
}

extern "C" CAMLprim value caml_prismel_metal_device_timestamp_frequency(value rh) {
  CAMLparam1(rh);
  if (@available(macOS 26.0, *)) {
    @try { id<MTLDevice> d=object_of_handle(rh,Handle_kind::Device);
      CAMLreturn(result_ok(caml_copy_int64((int64_t)[d queryTimestampFrequency])));
    } @catch(NSException*x){CAMLreturn(result_error(x.reason));}
  }
  CAMLreturn(result_error_text("queryTimestampFrequency requires macOS 26"));
}

extern "C" CAMLprim value caml_prismel_metal_device_counter_heap_entry_size(value rh) {
  CAMLparam1(rh);
  if (@available(macOS 26.0, *)) {
    @try { id<MTLDevice> d=object_of_handle(rh,Handle_kind::Device);
      CAMLreturn(result_ok(caml_copy_int64((int64_t)[d sizeOfCounterHeapEntry:MTL4CounterHeapTypeTimestamp])));
    } @catch(NSException*x){CAMLreturn(result_error(x.reason));}
  }
  CAMLreturn(result_error_text("sizeOfCounterHeapEntry requires macOS 26"));
}
