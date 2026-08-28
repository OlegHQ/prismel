type error =
  | Load_failed of { target : Runtime_next_provider.target; message : string }
  | Registration_failed of Runtime_next_provider.error

let ensure ~load target =
  match Runtime_next_provider.find target with
  | Ok provider -> Ok provider
  | Error (Runtime_next_provider.Missing_target _) ->
      (match load target with
       | Error message -> Error (Load_failed { target; message })
       | Ok () -> Result.map_error (fun error -> Registration_failed error)
           (Runtime_next_provider.find target))
  | Error error -> Error (Registration_failed error)
