/* MTL4AccelerationStructure11 is an exact class-metadata tail. These nine
   constructors are support machinery for concrete descriptor ownership; the
   abstract Descriptor and GeometryDescriptor classes are never instantiated. */
extern "C" CAMLprim value caml_prismel_metal4_acceleration_structure11_create(
    value kind_raw) {
  CAMLparam1(kind_raw); CAMLlocal2(handle, result); id descriptor = nil;
  Handle_kind kind;
  if (@available(macOS 26.0, *)) {
    @try { switch (Long_val(kind_raw)) {
        case 0: descriptor = [MTL4AccelerationStructureBoundingBoxGeometryDescriptor new];
          kind = Handle_kind::Acceleration4_bbox_descriptor; break;
        case 1: descriptor = [MTL4AccelerationStructureCurveGeometryDescriptor new];
          kind = Handle_kind::Acceleration4_curve_descriptor; break;
        case 2: descriptor = [MTL4AccelerationStructureMotionBoundingBoxGeometryDescriptor new];
          kind = Handle_kind::Acceleration4_motion_bbox_descriptor; break;
        case 3: descriptor = [MTL4AccelerationStructureMotionCurveGeometryDescriptor new];
          kind = Handle_kind::Acceleration4_motion_curve_descriptor; break;
        case 4: descriptor = [MTL4AccelerationStructureMotionTriangleGeometryDescriptor new];
          kind = Handle_kind::Acceleration4_motion_triangle_descriptor; break;
        case 5: descriptor = [MTL4AccelerationStructureTriangleGeometryDescriptor new];
          kind = Handle_kind::Acceleration4_triangle_descriptor; break;
        case 6: descriptor = [MTL4IndirectInstanceAccelerationStructureDescriptor new];
          kind = Handle_kind::Acceleration4_indirect_instance_descriptor; break;
        case 7: descriptor = [MTL4InstanceAccelerationStructureDescriptor new];
          kind = Handle_kind::Acceleration4_instance_descriptor; break;
        case 8: descriptor = [MTL4PrimitiveAccelerationStructureDescriptor new];
          kind = Handle_kind::Acceleration4_primitive_descriptor; break;
        default: CAMLreturn(result_error_text("unknown Metal4 acceleration descriptor kind"));
      }
      if (descriptor == nil)
        CAMLreturn(result_error_text("Metal returned no Metal4 acceleration descriptor"));
      handle = allocate_handle(descriptor, kind); result = result_ok(handle);
      CAMLreturn(result);
    } @catch (NSException *exception) { CAMLreturn(result_error(exception.reason)); }
  }
  CAMLreturn(result_error_text("Metal4 acceleration structures require macOS 26"));
}
