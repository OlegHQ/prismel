open Metal

type t =
  { device : Device.t
  ; library : Library.t
  ; write_function : Function.t
  ; exchange_function : Function.t
  ; read_function : Function.t
  ; write_pipeline : Compute_pipeline.t
  ; exchange_pipeline : Compute_pipeline.t
  ; read_pipeline : Compute_pipeline.t
  ; queue : Command_queue.t
  }
