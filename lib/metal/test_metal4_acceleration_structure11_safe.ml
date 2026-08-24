open Metal
let get=function Ok x->x|Error e->failwith(Format.asprintf "%a" pp_error e)
let ()=match Device.system_default()with Error _->print_endline"MTL4AccelerationStructure11 safe: skipped"|Ok dev->
 let open Acceleration_structure.Metal4_descriptor in
 match bounding_box dev with Error _->ignore(Device.destroy dev);print_endline"MTL4AccelerationStructure11 safe: skipped"|Ok first->
 let geometries=[first;get(curve dev);get(motion_bounding_box dev);get(motion_curve dev);get(motion_triangle dev);get(triangle dev)]in
 let descriptors=[get(indirect_instance dev);get(instance dev);get(primitive dev)]in
 List.iter(fun value->if geometry_device value!=dev||geometry_destroyed value then failwith"geometry ownership")geometries;
 List.iter(fun value->if device value!=dev||destroyed value then failwith"descriptor ownership")descriptors;
 List.iter(fun value->get(destroy_geometry value))geometries;List.iter(fun value->get(destroy value))descriptors;
 get(Device.destroy dev);print_endline"MTL4AccelerationStructure11 safe: concrete9 + abstract2 ownership/default availability passed"
