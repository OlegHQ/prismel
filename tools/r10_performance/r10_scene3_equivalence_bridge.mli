type public_workload = {
  camera : Prismel_next_api.Camera.t;
  scene : Prismel_next_api.Scene3.t;
}

type proof = {
  triangles : int;
  transforms : int;
  representative_pixels_milli : (int * int * int * int) list;
  semantic_signature : string;
}

val public_workload : unit -> public_workload
val prove :
  width:int ->
  height:int ->
  R10_scene3_legacy_equivalent.t ->
  (proof, string) result
(** Compare the canonical staged artifact with a public [Scene3] construction.
    Success requires identical topology, transforms, camera projection,
    material/light/ambient/MSAA facts, and representative projected pixels. *)
