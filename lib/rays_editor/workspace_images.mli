type t
val create : Workspace_resources.t -> t
val image : t -> state:Flow.Eval.state -> live:Frame_input.t -> Flow.Eval.plan -> Flow.Eval.value ->
  (Rays.Image.t,Flow.Diagnostic.t) result
val payload : t -> Flow_sop.Lower.image_resolver
val texture : t -> state:Flow.Eval.state -> live:Frame_input.t -> Flow.Eval.plan -> Flow.Eval.value ->
  (Rays.Texture.t,Flow.Diagnostic.t) result
