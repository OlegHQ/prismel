type ('buffer, 'element, 'acceleration) value =
  | Buffer of 'buffer option
  | Buffer_range of { buffer : 'buffer; offset : int64; length : int64 }
  | String of string option
  | Elements of 'element list
  | Accelerations of 'acceleration list
  | Resource_id of int64

val validate :
  expected_device:int64 ->
  buffer_device:('buffer -> int64) -> buffer_length:('buffer -> int64) ->
  element_device:('element -> int64) ->
  acceleration_device:('acceleration -> int64) ->
  ('buffer, 'element, 'acceleration) value -> (unit, string) result

val copy_retained_array :
  retain:('a -> ('owned, string) result) -> release:('owned -> unit) ->
  'a list -> ('owned array, string) result

val render_native_materializers :
  Binding_acceleration_ownership_plan.selection -> string
