type config = { minutes : float; frames : int option; sample_every : int; sample_period_seconds : float; report : string option }
val run : config -> Yojson.Safe.t
