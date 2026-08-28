val load : Runtime_next_provider.target -> (unit, string) result

val ensure :
  Runtime_next_provider.target ->
  (Runtime_next_provider.packed, Runtime_next_provider_loader.error) result
