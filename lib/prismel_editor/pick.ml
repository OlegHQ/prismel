(* Viewport provenance (plan W6).  Every collecting merge of a workspace tags
   its primitives with [Flow_sop.Lower.tag]; this module reads the tag back
   from the displayed geometry, casts a CPU ray to find the primitive under the
   pointer, and tints the primitives of the probed iteration.

   ponytail: a CPU ray over [Pdk.Surface_index] (a BVH of the displayed
   geometry, built at the first click and kept with the piece), not an ID
   buffer.  The upgrade path when meshes pass about 1M triangles is an OGPU
   ID-buffer feature (skill add-ogpu-feature). *)
open Prismel

module Set = Set.Make (Int)

let tags geometry =
  Option.bind (Pdk.Geometry.find_attribute ~owner:Pdk.Attribute.Primitive
    Flow_sop.Lower.source_attribute geometry) (fun attribute ->
      match Pdk.Attribute.Private.storage attribute with
      | Pdk.Attribute.Int values -> Some values | _ -> None)

let same_set a b = a == b || Set.equal a b

(* [None] when the geometry cannot be picked (degenerate polygons). *)
let surface geometry = Result.to_option (Pdk.Surface_index.create geometry)

(* The nearest hit as (distance, tag); tags of a geometry without provenance
   are absent, so it never picks. *)
let cast surface geometry ~origin ~direction =
  match surface, tags geometry with
  | Some surface, Some tags ->
      (match Pdk.Surface_index.raycast surface ~origin ~direction with
       | Ok (Some hit) -> Some (hit.distance, tags.(hit.primitive))
       | Ok None | Error _ -> None)
  | _ -> None

(* The primitives whose tag is in [lit] take the selection tint over their own
   colour, the rest are dimmed: a vertex colour per corner, so a prepare that
   reads [Cd] (as [to_mesh] does) draws it without knowing about picking. *)
let dim = 0.3 and mix = 0.6

let tint (output : Procedural.Session.output) lit =
  let geometry = output.geometry in
  match tags geometry with
  | Some tags when not (Set.is_empty lit) ->
      let topology = Pdk.Geometry.topology geometry in
      let corners = Pdk.Topology.vertex_count topology in
      let base = match Pdk.Geometry.find_attribute ~owner:Pdk.Attribute.Vertex "Cd" geometry,
                       Pdk.Geometry.find_attribute ~owner:Pdk.Attribute.Point "Cd" geometry with
        | Some a, _ -> (match Pdk.Attribute.Private.storage a with
            | Pdk.Attribute.Float4 c -> Some (`Vertex (Pdk.Packed.Float4.Private.view c)) | _ -> None)
        | None, Some a -> (match Pdk.Attribute.Private.storage a with
            | Pdk.Attribute.Float4 c -> Some (`Point (Pdk.Packed.Float4.Private.view c)) | _ -> None)
        | None, None -> None in
      let r = Array.make corners 1. and g = Array.make corners 1.
      and b = Array.make corners 1. and w = Array.make corners 1. in
      let ar, ag, ab, _ = Color.to_floats Pxui.Theme.default.accent in
      for primitive = 0 to Array.length tags - 1 do
        let first, last = Pdk.Topology.primitive_vertex_range topology primitive in
        let lit = Set.mem tags.(primitive) lit in
        for corner = first to last - 1 do
          let cr, cg, cb, cw = match base with
            | None -> 1., 1., 1., 1.
            | Some (`Vertex c) -> c.x.(corner), c.y.(corner), c.z.(corner), c.w.(corner)
            | Some (`Point c) ->
                let p = Pdk.Topology.point_of_vertex topology corner in
                c.x.(p), c.y.(p), c.z.(p), c.w.(p) in
          let shade own accent =
            if lit then own *. (1. -. mix) +. accent *. mix else own *. dim in
          r.(corner) <- shade cr ar; g.(corner) <- shade cg ag;
          b.(corner) <- shade cb ab; w.(corner) <- cw
        done
      done;
      (match Pdk.Packed.Float4.of_owned ~x:r ~y:g ~z:b ~w with
       | Error _ -> output
       | Ok colors ->
           match Result.bind (Pdk.Attribute.create_key_owned
               (Pdk.Attribute.color ~owner:Pdk.Attribute.Vertex) colors)
               (fun attribute -> Pdk.Geometry.with_attribute attribute geometry) with
           | Ok geometry -> { output with geometry }
           | Error _ -> output)
  | _ -> output
