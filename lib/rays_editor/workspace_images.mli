type t
val bind : t -> Flow_sop.Lower.t -> unit
val peek : t -> Flow.Eval.plan -> int -> Rays.Image.t option
val create : ?domains:int -> gpu:Workspace_gpu.t -> Workspace_resources.t -> t
val close : t -> unit
val render_stats : t -> int * int * int * int
val image : t -> state:Flow.Eval.state -> live:Frame_input.t -> Flow.Eval.plan -> Flow.Eval.value ->
  (Rays.Image.t,Flow.Diagnostic.t) result
val payload : t -> Flow_sop.Lower.image_resolver
val texture : t -> state:Flow.Eval.state -> live:Frame_input.t -> Flow.Eval.plan -> Flow.Eval.value ->
  (Rays.Texture.t,Flow.Diagnostic.t) result
