type t =
  | Wire of { node : int; output : string }
  | Expr of Flow.Expr.t
  | Live of Flow.Eval.value
(** [Live v]: a workspace argument that depends on [t] ({!Flow.Eval.is_live}),
    evaluated by {!Value_lane.resolve} for each time (a scalar, a vec3, a
    colour text, or a list of vec3 for a text-encoded list parameter). It has
    no wire and no type check; {!Lower} installs it. Compare with [==]. *)
