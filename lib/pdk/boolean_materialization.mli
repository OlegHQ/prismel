(** Private post-rounding Boolean materialization policy. *)

(* O(Ec + Ic + Es + Is) time and O(Fc) auxiliary storage for complex edges
    [Ec], complex incidence [Ic], extracted surface edges [Es], surface
    incidence [Is], and complex facets [Fc]. Exact seam-facet adjacency
    restricts candidates; the threshold applies only to rounded length. *)
val tiny_seam_edges :
  ?cancel:Cancel.t -> grain:int -> threshold:float ->
  Boolean_extract.ancestry -> Boolean_seam.t ->
  (Edge_group.t, Error.t) result

val surface_seam_edges :
  ?cancel:Cancel.t -> grain:int -> Boolean_extract.ancestry -> Boolean_seam.t ->
  (Edge_group.t, Error.t) result

val safe_independent_edges :
  ?cancel:Cancel.t -> grain:int -> ?keep_greatest:bool ->
  Edge_group.t -> Geometry.t ->
  (Edge_group.t, Error.t) result
(** Select a stable shortest-first independent subset satisfying two-manifold
    triangle incidence, the link condition, and a conservative exact
    orientation certificate for least-ID endpoint contraction. *)

(* O(F log F + K) time and O(F + K) auxiliary storage for [F] triangles and
    broad-phase candidate work [K]. Exact binary64 predicates distinguish
    ordinary shared topology from non-adjacent contact. *)
val verify_surface :
  ?cancel:Cancel.t -> grain:int -> require_closed:bool ->
  ?allow_opposite_duplicates:bool -> Geometry.t ->
  (unit, Error.t) result

type cleanup
val cleanup_geometry : cleanup -> Geometry.t
val cleanup_candidate_count : cleanup -> int
val cleanup_collapsed_count : cleanup -> int
val cleanup_batch_count : cleanup -> int
val cleanup_remaining_candidate_count : cleanup -> int
val cleanup_rounding_repaired_count : cleanup -> int
(* Number of rounded zero-area facets removed or ULP-scale contact edges
   contracted by the mandatory certified representability repair. *)
val cleanup_point_source : cleanup -> int -> int
val cleanup_vertex_source : cleanup -> int -> int
val cleanup_primitive_source : cleanup -> int -> int
val cleanup_seam_edges : cleanup -> Edge_group.t

val collapse_tiny_seam_batch :
  ?cancel:Cancel.t -> grain:int -> threshold:float -> require_closed:bool ->
  ?allow_opposite_duplicates:bool ->
  Boolean_extract.ancestry -> Boolean_seam.t -> Geometry.t ->
  (cleanup, Error.t) result
(** Collapse one deterministic independent batch to the least endpoint, then
    rerun seam and exact rounded-surface verification before publishing it. *)

val collapse_tiny_seams :
  ?cancel:Cancel.t -> grain:int -> threshold:float -> require_closed:bool ->
  ?allow_opposite_duplicates:bool -> ?max_batches:int -> ?strict:bool ->
  Boolean_extract.ancestry -> Boolean_seam.t -> Geometry.t ->
  (cleanup, Error.t) result
(** Continue deterministic independent contraction batches until no tiny
    seam-adjacent candidate remains, the explicit batch bound is reached, or
    no candidate has a certified contraction. Strict mode returns the stable
    [unresolved_cleanup] diagnostic instead of publishing a partial cleanup.
    Before optional threshold cleanup, a separately bounded mandatory pass
    removes only closed/pair-canceling zero-area subcomplexes and contracts
    only ULP-scale edges. Conservative link/orientation batches run first;
    a bounded speculative fallback is retained only when complete rounded
    degeneracy, incidence, and self-contact verification accepts the result. *)

val split_seam_points :
  ?cancel:Cancel.t -> grain:int -> cleanup -> (cleanup, Error.t) result
(** Duplicate each seam point once per primitive component obtained after
    removing exact seam edges. Corner/primitive order is unchanged; point
    payload and native edge groups follow exact packed ancestry. *)

type detriangulation = All_polygons | Unchanged_polygons
val detriangulate :
  ?cancel:Cancel.t -> grain:int -> assume_flat:bool -> mode:detriangulation ->
  Boolean_extract.ancestry -> cleanup -> (cleanup, Error.t) result
(** Merge adjacent triangles only when their exact extraction ancestry names
    the same source polygon and the edge is not a Boolean seam. *)
