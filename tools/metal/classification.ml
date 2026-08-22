type t =
  | Bound
  | Availability_gated
  | Scope_excluded
  | Unreviewed

let name = function
  | Bound -> "bound"
  | Availability_gated -> "availability-gated"
  | Scope_excluded -> "scope-excluded"
  | Unreviewed -> "unreviewed"

let classify ~unavailable ~identifier:_ =
  if unavailable then
    Scope_excluded, "Clang marks this declaration unavailable for macOS."
  else Unreviewed, "Binding classification pending during Phase 2."
