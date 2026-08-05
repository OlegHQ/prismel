(** Packed rest-state and point-motion operations for explicit immutable
    geometry snapshots. *)

type rest_mode = Store_rest | Extract_rest | Swap_rest
type rest_normals = No_rest_normals | Rest_normals_if_present | Rest_normals_always

val rest_position :
  ?cancel:Cancel.t ->
  ?grain:int ->
  ?reference:Geometry.t ->
  ?rest_attribute:string ->
  ?normals:rest_normals ->
  ?normal_attribute:string ->
  ?rest_normal_attribute:string ->
  rest_mode ->
  Geometry.t ->
  (Geometry.t, Error.t) result
(** Store, extract, or swap canonical point [P] with a point-owned rest
    attribute. A reference snapshot, when supplied, provides the stored
    positions and normals and must have the same point cardinality. If the
    rest position does not exist, extract and swap follow Houdini and perform
    a store. Packed position/attribute planes are structurally shared; only
    computed normals allocate numeric output. *)

type velocity_approximation = Backward_difference | Central_difference | Forward_difference
type velocity_initialization =
  | Compute_from_deformation
  | Keep_incoming
  | Set_value of Prismel.Vec3.t
  | From_attribute of { name : string; scale : float }
type velocity_unmatched = Velocity_unmatched_error | Velocity_unmatched_zero

val point_velocity :
  ?cancel:Cancel.t ->
  ?grain:int ->
  ?points:Group.t ->
  ?previous:Geometry.t ->
  ?next:Geometry.t ->
  ?approximation:velocity_approximation ->
  ?dt:float ->
  ?initialization:velocity_initialization ->
  ?match_attribute:string ->
  ?unmatched:velocity_unmatched ->
  ?velocity_attribute:string ->
  ?add_velocity:Prismel.Vec3.t ->
  ?compute_acceleration:bool ->
  ?acceleration_attribute:string ->
  Geometry.t ->
  (Geometry.t, Error.t) result
(** Initialize and modify a point velocity field. Deformation modes consume
    explicit neighboring snapshots: backward needs [previous], forward needs
    [next], and central needs both. [dt] is the positive interval from the
    current snapshot to either adjacent sample, so central velocity divides by
    [2 * dt] and acceleration by [dt * dt].

    Point-number matching requires equal cardinality. [match_attribute]
    instead matches integer or text point attributes and supports changing
    cardinality; duplicate reference keys fail as ambiguous, while missing
    keys follow [unmatched]. The optional group restricts writes and preserves
    existing velocity/acceleration outside it. Stable point ranges fill exact
    packed planes in parallel and are byte-identical across domain counts.
    Time is O(points + sample points), with O(points) output and match storage. *)
