type config = { minutes : float; frames : int option; sample_every : int; report : string option }
val run : config -> Yojson.Safe.t
