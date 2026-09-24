(** Parallel-transport frames along three-dimensional polylines. *)

open Prismel

type frame = private {
  point : Vec3.t;
  tangent : Vec3.t;
  normal : Vec3.t;
  binormal : Vec3.t;
}

(** Compute minimum-rotation frames. Closed paths distribute residual frame
    twist around the loop. *)
val frames : ?closed:bool -> Vec3.t list -> (frame list, string) result

val sweep_point : frame -> Vec2.t -> Vec3.t
val sweep_profile : frame -> Polygon2.t -> Vec3.t list
