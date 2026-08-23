type ('buffer, 'function_handle, 'visible_table) t

val create : device:int64 -> capacity:int ->
  ('buffer, 'function_handle, 'visible_table) t
val set_buffer :
  buffer_device:('buffer -> int64) ->
  ('buffer, 'function_handle, 'visible_table) t -> index:int ->
  ('buffer * int64) option -> (unit, string) result
val set_function :
  ('buffer, 'function_handle, 'visible_table) t -> index:int ->
  'function_handle option -> (unit, string) result
val set_visible_table :
  table_device:('visible_table -> int64) ->
  ('buffer, 'function_handle, 'visible_table) t -> index:int ->
  'visible_table option -> (unit, string) result
val destroy : ('buffer, 'function_handle, 'visible_table) t -> unit
val retained_count : ('buffer, 'function_handle, 'visible_table) t -> int
val destroyed : ('buffer, 'function_handle, 'visible_table) t -> bool
