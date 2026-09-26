(** Inspectable SOP catalog nodes. Constructors retain the ordinary immutable
    Procedural graph API while attaching PPX-derived parameter metadata and a
    pure stable-id rebuild function to each node. *)

module Box : sig
  val create :
    ?label:string ->
    ?size:Prismel.Vec3.t ->
    ?connectivity:Pdk.Box_generator.box_connectivity ->
    ?consolidate_points:bool ->
    ?normals:Pdk.Box_generator.box_normals ->
    ?center:Prismel.Vec3.t -> ?rotation:Prismel.Vec3.t ->
    ?rotation_order:Pdk.Box_generator.box_rotation_order -> ?uniform_scale:float ->
    ?x_divisions:int -> ?y_divisions:int -> ?z_divisions:int ->
    ?uv_attribute:string -> ?face_groups:string ->
    unit -> Procedural.Node.t
end

module Platonic : sig
  val create :
    ?label:string ->
    ?kind:Pdk.Parametric_generators.platonic_kind ->
    ?normals:Pdk.Parametric_generators.platonic_normals ->
    ?orientation:Pdk.Parametric_generators.platonic_orientation ->
    ?center:Prismel.Vec3.t -> ?rotation:Prismel.Vec3.t ->
    ?rotation_order:Pdk.Parametric_generators.platonic_rotation_order ->
    ?face_groups:string ->
    radius:float -> unit -> Procedural.Node.t
end

module Switch : sig
  val create :
    ?label:string -> ?index:int -> Procedural.Node.t list -> Procedural.Node.t
  (** Inspectable standard SOP switch. The generated choice uses stable input
      order and node labels; only the selected input branch is cooked. *)
end

module Grid : sig
  val create :
    ?label:string ->
    ?counts:Pdk.Plane_generators.grid_counts ->
    ?connectivity:Pdk.Plane_generators.grid_connectivity ->
    ?orientation:Pdk.Plane_generators.grid_orientation ->
    ?center:Prismel.Vec3.t -> ?width:float -> ?height:float ->
    ?rotation:float -> ?uv_attribute:string ->
    columns:int -> rows:int -> size:float -> unit -> Procedural.Node.t
end

module Copy_to_points : sig
  val create :
    ?label:string ->
    ?source_group:string ->
    ?target_group:string ->
    ?piece_attribute:string ->
    ?pack:bool ->
    source:Procedural.Node.t ->
    targets:Procedural.Node.t ->
    unit ->
    Procedural.Node.t
end

module Mountain : sig
  val create :
    ?label:string ->
    ?group:string ->
    ?direction_attribute:string ->
    ?mask_attribute:string ->
    ?height_attribute:string ->
    ?recompute_normals:bool ->
    seed:int -> height:float -> frequency:Prismel.Vec3.t ->
    octaves:int -> lacunarity:float -> roughness:float ->
    Procedural.Node.t -> Procedural.Node.t
end

module Point_generate : sig
  val origin : ?label:string -> points:int -> unit -> Procedural.Node.t
end

module Attribute_noise_quaternion : sig
  val create :
    ?label:string ->
    ?group:string ->
    ?location:Pdk.Attribute_ops.noise_location ->
    ?range:Pdk.Attribute_ops.noise_range ->
    owner:Pdk.Attribute.owner ->
    name:string ->
    seed:int -> frequency:Prismel.Vec3.t -> octaves:int ->
    Procedural.Node.t -> Procedural.Node.t
end

module Point_jitter : sig
  val create :
    ?label:string ->
    ?group:string ->
    ?mask_attribute:string ->
    ?id_attribute:string ->
    seed:int -> scale:float ->
    ?axis_scales:Prismel.Vec3.t ->
    Procedural.Node.t -> Procedural.Node.t
end

module Boolean : sig
  val create :
    ?label:string ->
    ?operation:Pdk.Boolean.operation ->
    ?resolve_right_self_intersections:bool ->
    ?detriangulation:Pdk.Boolean.detriangulation ->
    right:Procedural.Node.t -> Procedural.Node.t -> Procedural.Node.t
  (** [create ~right left]: exact Boolean of [left] (input 0) with [right]
      (input 1); the operation defaults to union. *)
end

module Duplicate : sig
  val create :
    ?label:string -> ?copies:int -> ?cumulative:bool ->
    ?transform:Prismel.Mat4.t -> Procedural.Node.t -> Procedural.Node.t
  (** Append [copies] transformed copies (points included), each by
      [transform] to the power of its index when [cumulative]. *)
end

module Poly_bevel : sig
  type shape = Chamfer | Round
  val create :
    ?label:string -> ?shape:shape -> ?divisions:int -> distance:float ->
    Procedural.Node.t -> Procedural.Node.t
end

module Transform : sig
  val create :
    ?label:string -> ?translate:Prismel.Vec3.t -> ?rotate:Prismel.Vec3.t ->
    ?scale:Prismel.Vec3.t -> ?uniform_scale:float ->
    Procedural.Node.t -> Procedural.Node.t
  (** Translate, rotate (radians), scale, then uniform scale. *)
end

module Attribute_randomize : sig
  val create :
    ?label:string -> ?owner:Pdk.Attribute.owner -> ?seed:int -> name:string ->
    minimum:float -> maximum:float -> Procedural.Node.t -> Procedural.Node.t
  (** A uniform random scalar attribute in [[minimum, maximum]] per element
      (point by default). *)
end

module Merge : sig
  val create : ?label:string -> Procedural.Node.t list -> Procedural.Node.t
  (** Concatenate geometry in input order. The node menu offers one required
      and two optional inputs. *)
end

module Group_random : sig
  val create :
    ?label:string -> ?seed:int -> probability:float ->
    owner:Pdk.Group_ops.owner -> name:string ->
    Procedural.Node.t -> Procedural.Node.t
end

module Blast : sig
  val create :
    ?label:string -> ?selected:bool -> ?compact_points:bool ->
    owner:Pdk.Group.owner -> group:string ->
    Procedural.Node.t -> Procedural.Node.t
end

module Boolean_fracture : sig
  val create :
    ?label:string ->
    ?resolve_cutter_self_intersections:bool ->
    ?detriangulation:Pdk.Boolean.detriangulation ->
    ?require_closed:bool ->
    ?piece_attribute:string ->
    cutters:Procedural.Node.t ->
    Procedural.Node.t ->
    Procedural.Node.t
end

module Normal : sig
  val create :
    ?label:string -> ?owner:Pdk.Attribute.owner ->
    ?weighting:Pdk.Normal_ops.weighting -> ?cusp_angle:float ->
    ?keep_original_zero:bool -> ?reverse:bool -> ?attribute:string ->
    Procedural.Node.t -> Procedural.Node.t
end

module Exploded_view : sig
  val create :
    ?label:string -> ?amount:float -> ?scale:Prismel.Vec3.t ->
    ?piece_attribute:string -> ?noise_amount:float ->
    ?noise_frequency:float -> ?noise_seed:int ->
    Procedural.Node.t -> Procedural.Node.t
end

(** Deterministic PPX-generated manifest for the interactive SOP network
    editor. A module marked [[@@sop.register]] contributes its local [factory]
    in source order; there is no second hand-maintained registry. Factories
    declare exact input arity and build ordinary immutable nodes, while the
    editor document remains the topology authority. *)
module Editor : sig
  val factories : Procedural.Edit_graph.factory list
end
