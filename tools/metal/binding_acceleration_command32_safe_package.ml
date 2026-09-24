type resource = { token:int; device:int; length:int; mutable live:bool }
type sample_buffer = { resource:resource; sample_count:int }
type attachment = { sample:sample_buffer; first:int; last:int }
type pass = { device:int; slots:attachment option array }
type encoder = { device:int; mutable ended:bool; mutable retained:int list }
let callable_ids = Binding_acceleration_command32_native_closure.ids
let metadata_ids = ["class:MTLAccelerationStructurePassDescriptor";"class:MTLAccelerationStructurePassSampleBufferAttachmentDescriptor";"class:MTLAccelerationStructurePassSampleBufferAttachmentDescriptorArray";"protocol:MTLAccelerationStructureCommandEncoder"]
let create_pass ~device = {device;slots=Array.make 4 None}
let validate_resource ~device resource = if not resource.live then Error "destroyed acceleration command resource" else if resource.device<>device then Error "acceleration command device mismatch" else Ok()
let set_attachment pass ~index value = if index<0||index>=Array.length pass.slots then Error "sample attachment index out of range" else match value with None->pass.slots.(index)<-None;Ok()|Some attachment->(match validate_resource~device:pass.device attachment.sample.resource with Error _ as error->error|Ok()when attachment.first<0||attachment.last<attachment.first||attachment.last>=attachment.sample.sample_count->Error "sample attachment range is invalid"|Ok()->pass.slots.(index)<-Some attachment;Ok())
let encode encoder resources = if encoder.ended then Error "acceleration encoder already ended" else let rec validate=function []->Ok()|resource::rest->match validate_resource~device:encoder.device resource with Error _ as error->error|Ok()->validate rest in match validate resources with Error _ as error->error|Ok()->encoder.retained<-List.sort_uniq Int.compare(List.map(fun resource->resource.token)resources@encoder.retained);Ok()
let validate () = if List.length callable_ids<>32||List.length(List.sort_uniq String.compare callable_ids)<>32||List.length metadata_ids<>4 then invalid_arg "AccelerationCommand32 safe package drift"
