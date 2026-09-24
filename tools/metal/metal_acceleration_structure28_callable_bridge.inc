/* AccelerationStructure28 constructor-only ownership shard. Integration adds
   ten exact descriptor handle kinds; property graphs remain handwritten and
   validate all buffers before mutating these retained descriptors. */
extern "C" CAMLprim value caml_prismel_metal_acceleration_descriptor_create(value tag_raw){
  CAMLparam1(tag_raw);CAMLlocal2(handle,result);id descriptor=nil;Handle_kind kind;
  @try{switch(Long_val(tag_raw)){
    case 0:descriptor=[MTLAccelerationStructureBoundingBoxGeometryDescriptor descriptor];kind=Handle_kind::Acceleration_bbox_descriptor;break;
    case 1:descriptor=[MTLAccelerationStructureCurveGeometryDescriptor descriptor];kind=Handle_kind::Acceleration_curve_descriptor;break;
    case 2:descriptor=[MTLAccelerationStructureMotionBoundingBoxGeometryDescriptor descriptor];kind=Handle_kind::Acceleration_motion_bbox_descriptor;break;
    case 3:descriptor=[MTLAccelerationStructureMotionCurveGeometryDescriptor descriptor];kind=Handle_kind::Acceleration_motion_curve_descriptor;break;
    case 4:descriptor=[MTLAccelerationStructureMotionTriangleGeometryDescriptor descriptor];kind=Handle_kind::Acceleration_motion_triangle_descriptor;break;
    case 5:descriptor=[MTLAccelerationStructureTriangleGeometryDescriptor descriptor];kind=Handle_kind::Acceleration_triangle_owned_descriptor;break;
    case 6:descriptor=[MTLIndirectInstanceAccelerationStructureDescriptor descriptor];kind=Handle_kind::Acceleration_indirect_instance_descriptor;break;
    case 7:descriptor=[MTLInstanceAccelerationStructureDescriptor descriptor];kind=Handle_kind::Acceleration_instance_descriptor;break;
    case 8:descriptor=[MTLMotionKeyframeData data];kind=Handle_kind::Acceleration_motion_keyframe;break;
    case 9:descriptor=[MTLPrimitiveAccelerationStructureDescriptor descriptor];kind=Handle_kind::Acceleration_primitive_descriptor;break;
    default:CAMLreturn(result_error_text("unknown acceleration descriptor constructor"));}
    if(!descriptor)CAMLreturn(result_error_text("Metal returned no acceleration descriptor"));handle=allocate_handle(descriptor,kind);result=result_ok(handle);CAMLreturn(result);
  }@catch(NSException*x){CAMLreturn(result_error(x.reason));}}
