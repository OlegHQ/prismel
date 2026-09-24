type region = int64 * int64 * int64 * int64 * int64 * int64
type origin = int64 * int64 * int64
type size3 = int64 * int64 * int64

module type Raw = sig
  type handle
  val buffer_add_debug_marker : handle -> string -> int64 -> int64 -> (unit,string) result
  val buffer_remote_view : handle -> handle -> (handle option,string) result
  val buffer_new_tensor : handle -> handle -> int64 -> (handle,string) result
  val buffer_remote_storage : handle -> (handle option,string) result
  val layout_array_get : handle -> int64 -> (handle option,string) result
  val layout_array_set : handle -> int64 -> handle option -> (unit,string) result
  val command_buffer_state_encoder : handle -> handle -> (handle,string) result
  val device_new_view_pool : handle -> handle -> (handle,string) result
  val heap_device : handle -> (handle option,string) result
  val heap_acceleration_descriptor : handle -> handle -> (handle,string) result
  val heap_acceleration_descriptor_offset : handle -> handle -> int64 -> (handle,string) result
  val heap_acceleration_size : handle -> int64 -> (handle,string) result
  val heap_acceleration_size_offset : handle -> int64 -> int64 -> (handle,string) result
  val resource_device : handle -> (handle option,string) result
  val resource_heap : handle -> (handle option,string) result
  val set_owner : handle -> bytes -> (unit,string) result
  val encoder_move_texture : handle -> handle -> int64 -> int64 -> origin -> size3 -> handle -> int64 -> int64 -> origin -> (unit,string) result
  val encoder_update_fence : handle -> handle -> (unit,string) result
  val encoder_indirect_mapping : handle -> handle -> int64 -> handle -> int64 -> (unit,string) result
  val encoder_mappings : handle -> handle -> int64 -> region array -> int64 array -> int64 array -> int64 -> (unit,string) result
  val encoder_wait_fence : handle -> handle -> (unit,string) result
  val pass_sample_attachments : handle -> (handle option,string) result
  val sample_attachment_buffer : handle -> (handle option,string) result
  val sample_attachment_set_buffer : handle -> handle option -> (unit,string) result
  val sample_array_get : handle -> int64 -> (handle option,string) result
  val sample_array_set : handle -> int64 -> handle option -> (unit,string) result
  val pool_base_id : handle -> (int64,string) result
  val pool_copy : handle -> handle -> int64 -> int64 -> int64 -> (int64,string) result
  val pool_device : handle -> (handle option,string) result
  val pool_label : handle -> (string option,string) result
  val pool_count : handle -> (int64,string) result
  val texture_get_bytes : handle -> bytes -> int64 -> region -> int64 -> (unit,string) result
  val texture_remote_view : handle -> handle -> (handle option,string) result
  val texture_view : handle -> int64 -> (handle option,string) result
  val texture_remote_storage : handle -> (handle option,string) result
  val texture_replace : handle -> region -> int64 -> bytes -> int64 -> (unit,string) result
  val texture_root : handle -> (handle option,string) result
  val texture_pool_set : handle -> handle -> int64 -> (int64,string) result
  val texture_pool_set_descriptor : handle -> handle -> handle -> int64 -> (int64,string) result
  val texture_pool_set_buffer : handle -> handle -> handle -> int64 -> int64 -> int64 -> (int64,string) result
  val pass_create : unit -> (handle,string) result
  val texture_descriptor_2d : int64 -> int64 -> int64 -> bool -> (handle,string) result
  val texture_descriptor_buffer : int64 -> int64 -> int64 -> int64 -> (handle,string) result
  val texture_descriptor_cube : int64 -> int64 -> bool -> (handle,string) result
end
