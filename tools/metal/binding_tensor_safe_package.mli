type extents = int64 array
type graph_kind = Descriptor_dimensions | Descriptor_strides | Tensor_dimensions | Tensor_strides | Tensor_buffer
type constructor = Device_tensor | Device_size_and_align | Buffer_tensor
val constructors : (constructor * string) list
val copy : extents -> extents
val validate_extents : extents -> (extents, string) result
val validate_shape : dimensions:extents -> strides:extents -> ((extents * extents), string) result
val validate_slice : tensor_dimensions:extents -> origin:extents -> slice_dimensions:extents -> byte_strides:extents -> element_size:int -> bytes_length:int -> (int64, string) result
val retained_graph : graph_kind list
val validate_handoff : unit -> unit
