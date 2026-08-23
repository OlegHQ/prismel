val archive_ids : string list
val pre_archive_callable_count : int
val authoritative_ownership_count : int
val validate :
  authoritative_ids:string list -> pre_archive_callable_ids:string list -> unit
