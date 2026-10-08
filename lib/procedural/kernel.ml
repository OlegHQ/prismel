type column = Floats of float array | Vec3s of float array
type runner = Context.t -> (column, Diagnostic.error) result
type t = {id : int; bytes : int; prepare : column list -> (runner, Diagnostic.error) result}
let create ~payload_bytes prepare =
  if payload_bytes < 0 then invalid_arg "Kernel.create: negative payload size";
  {id = Rdk.Data_id.fresh (); bytes = payload_bytes; prepare}
let data_id t = t.id
let payload_bytes t = t.bytes
let prepare t = t.prepare
