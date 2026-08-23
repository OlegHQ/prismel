module type Raw = sig
  type handle
  val buffer_layout_create : unit -> (handle,string) result
  val buffer_layout_stride : handle -> (int64,string) result
  val buffer_layout_set_stride : handle -> int64 -> (unit,string) result
  val buffer_layout_step_rate : handle -> (int64,string) result
  val buffer_layout_set_step_rate : handle -> int64 -> (unit,string) result
  val buffer_layout_step_function : handle -> (int64,string) result
  val buffer_layout_set_step_function : handle -> int64 -> (unit,string) result
  val sample_attachment_create : unit -> (handle,string) result
  val sample_attachment_start : handle -> (int64,string) result
  val sample_attachment_set_start : handle -> int64 -> (unit,string) result
  val sample_attachment_end : handle -> (int64,string) result
  val sample_attachment_set_end : handle -> int64 -> (unit,string) result
  val view_pool_descriptor_create : unit -> (handle,string) result
  val view_pool_descriptor_count : handle -> (int64,string) result
  val view_pool_descriptor_set_count : handle -> int64 -> (unit,string) result
  val view_pool_descriptor_label : handle -> (string option,string) result
  val view_pool_descriptor_set_label : handle -> string option -> (unit,string) result
end
