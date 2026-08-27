type buffer_range={buffer:unit Handle.t;buffer_size:int64;offset:int64;length:int64}
type geometry=Triangles of{vertices:buffer_range;vertex_stride:int;vertex_count:int}|Bounding_boxes of{boxes:buffer_range;stride:int;count:int}|Curves of{control_points:buffer_range;radii:buffer_range;control_point_count:int}|Motion of{keyframes:int;geometry:geometry}
type descriptor=Blas of{geometries:geometry array;allow_refit:bool}|Tlas of{instances:buffer_range;instance_stride:int;instance_count:int;allow_refit:bool}
type state=Empty|Built|Compacted
type t={handle:unit Handle.t;descriptor:descriptor;allow_refit:bool;mutable state:state}
type description=Build of int64|Refit of int64|Copy of{source:int64;destination:int64}|Compact of int64
let invalid op text=Error(Error.make op Error.Invalid_argument text)
let validate_range device range=let op="Ogpu.Acceleration.validate_range"in match Handle.validate_for ~operation:op device range.buffer with Error _ as e->e|Ok()when range.buffer_size<0L||range.offset<0L||range.length<=0L||Int64.rem range.offset 4L<>0L->invalid op"buffer range is invalid or unaligned"|Ok()when range.offset>Int64.sub range.buffer_size range.length->invalid op"buffer range is out of bounds"|Ok()->Ok()
let rec validate_geometry device=function
  |Triangles{vertices;vertex_stride;vertex_count}->if vertex_stride<12||vertex_stride mod 4<>0||vertex_count<3||vertex_count mod 3<>0 then invalid"Ogpu.Acceleration.Triangles""triangle cardinality/stride is invalid"else validate_range device vertices
  |Bounding_boxes{boxes;stride;count}->if stride<24||stride mod 4<>0||count<=0 then invalid"Ogpu.Acceleration.Bounding_boxes""box cardinality/stride is invalid"else validate_range device boxes
  |Curves{control_points;radii;control_point_count}->if control_point_count<2 then invalid"Ogpu.Acceleration.Curves""curve cardinality is invalid"else Result.bind(validate_range device control_points)(fun()->validate_range device radii)
  |Motion{keyframes;geometry}->if keyframes<2 then invalid"Ogpu.Acceleration.Motion""motion requires at least two keyframes"else validate_geometry device geometry
let descriptor_refit=function Blas{allow_refit;_}|Tlas{allow_refit;_}->allow_refit
let validate_descriptor device=function Blas{geometries;_}when Array.length geometries=0->invalid"Ogpu.Acceleration.create""BLAS geometry array is empty"|Blas{geometries;_}->Array.fold_left(fun result geometry->Result.bind result(fun()->validate_geometry device geometry))(Ok())geometries|Tlas{instances;instance_stride;instance_count;_}->if instance_stride<64||instance_stride mod 16<>0||instance_count<=0 then invalid"Ogpu.Acceleration.create""instance cardinality/stride is invalid"else validate_range device instances
let create device ~ray_tracing descriptor=if not ray_tracing then Error(Error.make"Ogpu.Acceleration.create"Error.Unsupported"ray tracing is unsupported")else Result.bind(validate_descriptor device descriptor)(fun()->Ok{handle=Handle.create ~device;descriptor;allow_refit=descriptor_refit descriptor;state=Empty})
let check op device value=Handle.validate_for ~operation:op device value.handle
let build device value=let op="Ogpu.Acceleration.build"in Result.bind(check op device value)(fun()->match value.state with Empty->value.state<-Built;Ok(Build(Handle.id value.handle))|Built|Compacted->Error(Error.make op Error.Invalid_state"structure has already been built"))
let refit device value=let op="Ogpu.Acceleration.refit"in Result.bind(check op device value)(fun()->if not value.allow_refit then Error(Error.make op Error.Unsupported"descriptor does not permit refit")else match value.state with Built->Ok(Refit(Handle.id value.handle))|Empty|Compacted->Error(Error.make op Error.Invalid_state"refit requires an uncompacted built structure"))
let copy device value=let op="Ogpu.Acceleration.copy"in Result.bind(check op device value)(fun()->match value.state with Empty->Error(Error.make op Error.Invalid_state"copy requires a built structure")|Built|Compacted as state->let target={handle=Handle.create ~device;descriptor=value.descriptor;allow_refit=value.allow_refit;state}in Ok(target,Copy{source=Handle.id value.handle;destination=Handle.id target.handle}))
let compact device value=let op="Ogpu.Acceleration.compact"in Result.bind(check op device value)(fun()->match value.state with Built->value.state<-Compacted;Ok(Compact(Handle.id value.handle))|Empty|Compacted->Error(Error.make op Error.Invalid_state"compact requires an uncompacted built structure"))
let destroy value=Handle.destroy value.handle
let id value=Handle.id value.handle
