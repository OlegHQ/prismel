(** Deterministic, target-independent geometry analysis. *)

type bounds = {
  min : Prismel.Vec3.t;
  max : Prismel.Vec3.t;
  center : Prismel.Vec3.t;
  size : Prismel.Vec3.t;
}

type measure = Perimeter | Area | Signed_volume
type accumulation = Per_element | Throughout
type connectivity_owner = Connectivity_points | Connectivity_primitives
type connectivity_attribute = Connectivity_integer | Connectivity_text of string

val bounds : ?cancel:Cancel.t -> Geometry.t -> bounds option
(** Axis-aligned point bounds. Empty geometry has no bounds. O(points) time
    and O(1) auxiliary memory. *)

val primitive_measure :
  ?cancel:Cancel.t -> ?grain:int -> ?primitives:Group.t ->
  measure -> Geometry.t -> (float array, string) result
(** Measure selected primitives into a full primitive-order plane, with zeroes
    outside the selection. [Perimeter] measures closed polygon/curve boundary
    length or open-polyline length. [Area] and [Signed_volume] require simple
    polygons and use deterministic ear clipping. Signed volume is the stable
    sum of oriented tetrahedral contributions around the geometry bounds
    center and is meaningful as a total for consistently wound closed shells.

    Perimeter is O(vertices). Polygon measures are O(sum(c squared)) for corner
    counts [c], with O(primitives + parallel chunks * max(c)) storage. Output
    slots are disjoint and total reductions remain in primitive order. *)

val primitive_area :
  ?cancel:Cancel.t -> ?grain:int -> ?primitives:Group.t ->
  Geometry.t -> (float array, string) result

val surface_area :
  ?cancel:Cancel.t -> ?grain:int -> ?primitives:Group.t ->
  Geometry.t -> (float, string) result
val primitive_perimeter :
  ?cancel:Cancel.t -> ?grain:int -> ?primitives:Group.t ->
  Geometry.t -> (float array, string) result
val perimeter :
  ?cancel:Cancel.t -> ?grain:int -> ?primitives:Group.t ->
  Geometry.t -> (float, string) result
val primitive_signed_volume :
  ?cancel:Cancel.t -> ?grain:int -> ?primitives:Group.t ->
  Geometry.t -> (float array, string) result
val signed_volume :
  ?cancel:Cancel.t -> ?grain:int -> ?primitives:Group.t ->
  Geometry.t -> (float, string) result

val connectivity : Geometry.t -> int array * int
(** Primitive connected-component IDs based on shared points, numbered by the
    first primitive encountered in each component. Returns IDs and component
    count. O(vertices alpha(primitives)) time and O(points + primitives)
    auxiliary/output memory. *)

val classify_connectivity :
  ?cancel:Cancel.t ->
  ?grain:int ->
  ?primitives:Group.t ->
  ?points:Group.t ->
  ?seams:Edge_group.t ->
  ?uv_attribute:string ->
  connectivity_owner ->
  Geometry.t ->
  (int array * int, Error.t) result
(** Classify point or primitive connected components. Primitive and point
    include groups behave as deleted topology and excluded output elements are
    [-1]. Point mode joins topology edges and may omit native [seams]. Primitive
    mode normally joins shared-point incidence; a native seam group instead
    joins only across non-seam shared edges, while [uv_attribute] joins only
    across shared edges whose endpoint vertex float2 or float3 UVs agree
    exactly. Seam and UV modes are mutually exclusive.

    Default classification is O(points + vertices + primitives). Seam/UV mode
    is O(vertices + sum(edge incidence squared)) for non-manifold edges and
    linear on manifold topology. Auxiliary memory is O(points + primitives)
    plus the shared topology index. IDs are compact and assigned by the first
    included output element in each component. *)

val with_primitive_area : ?name:string -> Geometry.t -> (Geometry.t, string) result
val with_measure :
  ?cancel:Cancel.t ->
  ?grain:int ->
  ?primitives:Group.t ->
  ?accumulation:accumulation ->
  ?name:string ->
  ?total_name:string ->
  measure -> Geometry.t -> (Geometry.t, Error.t) result
(** Write a primitive float attribute in stable order. A restricted operation
    preserves an existing same-name float payload outside its group, otherwise
    unselected values default to zero. [Throughout] writes the selected total
    to every selected primitive. [total_name] additionally writes that total
    once as a detail float attribute. *)

val with_connectivity :
  ?cancel:Cancel.t ->
  ?grain:int ->
  ?primitives:Group.t ->
  ?points:Group.t ->
  ?seams:Edge_group.t ->
  ?uv_attribute:string ->
  ?owner:connectivity_owner ->
  ?name:string ->
  ?attribute:connectivity_attribute ->
  Geometry.t ->
  (Geometry.t, Error.t) result
(** Add integer or prefixed-text component IDs. Text values share one string
    per component; excluded elements receive the empty string. *)
