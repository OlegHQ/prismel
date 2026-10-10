(** Prepared SOP surfaces. Material batches share one converted mesh, and
    explosion moves complete pieces before any material split. *)
type t
val of_output : Sop.Session.output -> (t, string) result
val scene3 : Sop.Node.t -> t -> Rays.Scene3.t
