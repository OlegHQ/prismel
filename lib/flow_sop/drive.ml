type t =
  | Wire of { node : int; output : string }
  | Expr of Flow.Expr.t
