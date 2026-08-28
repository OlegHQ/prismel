type error =
  | Load_failed of { target : Runtime_next_provider.target; message : string }
  | Registration_failed of Runtime_next_provider.error

val ensure :
  load:(Runtime_next_provider.target -> (unit, string) result) ->
  Runtime_next_provider.target ->
  (Runtime_next_provider.packed, error) result
