type group = Listener | Queue | Export | Label | Device | Notification

type item =
  { id : string
  ; group : group
  }

val items : item list
val ids : string list
val validate : unit -> unit

