type t =
  | Wire of { node : int; output : string }
  | Expr of Flow.Expr.t
  | Live of Flow.Eval.value
