(* Shape nodes, declared once: the record is the editor schema, the factory
   and the typed [Sop] constructor. *)

open Rays_math
open Sop_support

(* ocamldep must see the PPX's [Procedural.X] resolve inside this library. *)
module Procedural = Sop_support.Procedural

module Line = struct
  let kind_parameter = Parameter.choice ~equal:( = ) [
      "Polygon curve", Rdk.Line_geometry.Line_curve;
      "Points", Rdk.Line_geometry.Line_points;
    ]

  type parameters = {
    kind : Rdk.Line_geometry.kind [@sop.default Rdk.Line_geometry.Line_curve]
      [@sop.label "Primitive type"] [@sop.kind kind_parameter];
    points : int [@sop.default 2] [@sop.label "Points"]
      [@sop.min 2] [@sop.max 128] [@sop.hard_min 1];
    origin_x : float [@sop.default 0.] [@sop.label "Origin X"]
      [@sop.folder "Origin"] [@sop.min (-10.)] [@sop.max 10.]; [@sop.vec3 "origin"]
    origin_y : float [@sop.default 0.] [@sop.label "Origin Y"]
      [@sop.folder "Origin"] [@sop.min (-10.)] [@sop.max 10.]; [@sop.vec3 "origin"]
    origin_z : float [@sop.default 0.] [@sop.label "Origin Z"]
      [@sop.folder "Origin"] [@sop.min (-10.)] [@sop.max 10.]; [@sop.vec3 "origin"]
    direction_x : float [@sop.default 0.] [@sop.label "Direction X"]
      [@sop.folder "Direction"] [@sop.min (-1.)] [@sop.max 1.]; [@sop.vec3 "direction"]
    direction_y : float [@sop.default 1.] [@sop.label "Direction Y"]
      [@sop.folder "Direction"] [@sop.min (-1.)] [@sop.max 1.]; [@sop.vec3 "direction"]
    direction_z : float [@sop.default 0.] [@sop.label "Direction Z"]
      [@sop.folder "Direction"] [@sop.min (-1.)] [@sop.max 1.]; [@sop.vec3 "direction"]
    length : float [@sop.default 1.] [@sop.label "Length"]
      [@sop.min 0.] [@sop.max 10.] [@sop.hard_min 0.];
  } [@@sop.node_key "line"] [@@sop.node_label "Line"]
    [@@sop.node_category "Create/Curve"] [@@sop.node_inputs 0]
    [@@sop.fn "line"] [@@sop.args "?kind ?points ~origin ~direction ~length ()"]
    [@@deriving sop_params, sop_node]

  let build = parameters_build (fun ~label parameters ->
    let label = Some label in
    let kind = parameters.kind in
    let points = parameters.points in
    let origin = Vec3.create parameters.origin_x parameters.origin_y
          parameters.origin_z in
    let direction = Vec3.create parameters.direction_x parameters.direction_y
          parameters.direction_z in
    let length = parameters.length in
    let origin = vec3_copy origin and direction = vec3_copy direction in
    Node.Private.make ?label ~operation:"line" ~version:1
      ~parameters:""
      ~cook_mode:Node.Generator ~dependencies:Context.Dependencies.static
      ~inputs:[||] (fun ~node_id:_ context _inputs ->
        match Rdk.Line_geometry.line ~cancel:(Context.cancel_token context)
            ~grain:(Context.grain context) ~kind ~points ~origin ~direction
            ~length () with
        | Ok geometry -> cooked geometry
        | Error error -> structured_rdk_error error)
  )

  let factory = parameters_factory build
  let fn = parameters_fn build
end


module Mirror = struct
  type parameters = {
    keep_original : bool [@sop.default true] [@sop.label "Keep original"];
    origin_x : float [@sop.default 0.] [@sop.label "Origin X"]
      [@sop.folder "Plane/Origin"] [@sop.min (-10.)] [@sop.max 10.]; [@sop.vec3 "origin"]
    origin_y : float [@sop.default 0.] [@sop.label "Origin Y"]
      [@sop.folder "Plane/Origin"] [@sop.min (-10.)] [@sop.max 10.]; [@sop.vec3 "origin"]
    origin_z : float [@sop.default 0.] [@sop.label "Origin Z"]
      [@sop.folder "Plane/Origin"] [@sop.min (-10.)] [@sop.max 10.]; [@sop.vec3 "origin"]
    normal_x : float [@sop.default 1.] [@sop.label "Normal X"]
      [@sop.folder "Plane/Normal"] [@sop.min (-1.)] [@sop.max 1.]; [@sop.vec3 "normal"]
    normal_y : float [@sop.default 0.] [@sop.label "Normal Y"]
      [@sop.folder "Plane/Normal"] [@sop.min (-1.)] [@sop.max 1.]; [@sop.vec3 "normal"]
    normal_z : float [@sop.default 0.] [@sop.label "Normal Z"]
      [@sop.folder "Plane/Normal"] [@sop.min (-1.)] [@sop.max 1.]; [@sop.vec3 "normal"]
  } [@@sop.node_key "mirror"] [@@sop.node_label "Mirror"]
    [@@sop.node_category "Modify"] [@@sop.node_inputs 1]
    [@@sop.fn "mirror"] [@@sop.args "?keep_original ~origin ~normal in0"]
    [@@deriving sop_params, sop_node]

  let build = parameters_build (fun ~label parameters input ->
    let label = Some label in
    let keep_original = parameters.keep_original in
    let origin = Vec3.create parameters.origin_x parameters.origin_y
          parameters.origin_z in
    let normal = Vec3.create parameters.normal_x parameters.normal_y
          parameters.normal_z in
    let origin = vec3_copy origin and normal = vec3_copy normal in
    Node.Private.make ?label ~operation:"mirror" ~version:1
      ~parameters:""
      ~cook_mode:(Node.Duplicate_input 0)
      ~dependencies:Context.Dependencies.static ~inputs:[|input|]
      (fun ~node_id:_ context inputs ->
        match Rdk.Mirror_geometry.run ~cancel:(Context.cancel_token context)
            ~grain:(Context.grain context) ~keep_original ~origin ~normal inputs.(0) with
        | Ok geometry -> cooked geometry
        | Error error -> structured_rdk_error error)
  )

  let factory = parameters_factory build
  let fn = parameters_fn build
end


module Match_axis = struct
  type parameters = {
    from_x : float [@sop.default 0.] [@sop.label "From X"]
      [@sop.folder "From"] [@sop.min (-1.)] [@sop.max 1.]; [@sop.vec3 "from"]
    from_y : float [@sop.default 1.] [@sop.label "From Y"]
      [@sop.folder "From"] [@sop.min (-1.)] [@sop.max 1.]; [@sop.vec3 "from"]
    from_z : float [@sop.default 0.] [@sop.label "From Z"]
      [@sop.folder "From"] [@sop.min (-1.)] [@sop.max 1.]; [@sop.vec3 "from"]
    into_x : float [@sop.default 0.] [@sop.label "Into X"]
      [@sop.folder "Into"] [@sop.min (-1.)] [@sop.max 1.]; [@sop.vec3 "into"]
    into_y : float [@sop.default 1.] [@sop.label "Into Y"]
      [@sop.folder "Into"] [@sop.min (-1.)] [@sop.max 1.]; [@sop.vec3 "into"]
    into_z : float [@sop.default 0.] [@sop.label "Into Z"]
      [@sop.folder "Into"] [@sop.min (-1.)] [@sop.max 1.]; [@sop.vec3 "into"]
  } [@@sop.node_key "match_axis"] [@@sop.node_label "Match Axis"]
    [@@sop.node_category "Modify/Align"] [@@sop.node_inputs 1]
    [@@sop.fn "match_axis"] [@@sop.args "~from ~into in0"]
    [@@deriving sop_params, sop_node]

  let build = parameters_build (fun ~label parameters input ->
    let label = Some label in
    let from = Vec3.create parameters.from_x parameters.from_y
          parameters.from_z in
    let into = Vec3.create parameters.into_x parameters.into_y
          parameters.into_z in
    let from = vec3_copy from and into = vec3_copy into in
    Node.Private.make ?label ~operation:"match_axis" ~version:1
      ~parameters:""
      ~cook_mode:(Node.Duplicate_input 0) ~dependencies:Context.Dependencies.static
      ~inputs:[|input|] (fun ~node_id:_ context inputs ->
        match Rdk.Match_size.match_axis ~grain:(Context.grain context) ~from ~into inputs.(0) with
        | Ok geometry -> cooked geometry
        | Error error -> structured_rdk_error error)
  )
  let factory = parameters_factory build
  let fn = parameters_fn build
end


module Noise_displace = struct
  type parameters = {
    context_seed : bool [@sop.default false] [@sop.label "Use context seed"];
    seed : int [@sop.default 0] [@sop.label "Seed"] [@sop.min 0]
      [@sop.max 9999] [@sop.absent "context_seed"];
    amplitude : float [@sop.default 0.1] [@sop.label "Amplitude"]
      [@sop.min (-10.)] [@sop.max 10.];
    frequency : float [@sop.default 1.] [@sop.label "Frequency"]
      [@sop.min 0.] [@sop.max 20.] [@sop.hard_min 0.];
  } [@@sop.node_key "noise_displace"] [@@sop.node_label "Noise Displace"]
    [@@sop.node_category "Deform/Noise"] [@@sop.node_inputs 1]
    [@@sop.fn "noise_displace"] [@@sop.args "?seed ~amplitude ~frequency in0"]
    [@@deriving sop_params, sop_node]
  let build = parameters_build (fun ~label parameters input ->
    let label = Some label in
    let seed = if parameters.context_seed then None else Some parameters.seed in
    let amplitude = parameters.amplitude in
    let frequency = parameters.frequency in
    let dependencies = match seed with
      | Some _ -> Context.Dependencies.static
      | None -> Context.Dependencies.one Context.Dependencies.Seed
    in
    let stable_identity = Option.map (fun label ->
      stable_string_hash ("noise_displace:" ^ label)) label in
    Node.Private.make ?label ~operation:"noise_displace" ~version:1 ~parameters:""
      ~cook_mode:(Node.Duplicate_input 0) ~dependencies ~inputs:[|input|]
      (fun ~node_id context inputs ->
        let identity = Option.value ~default:(Int64.of_int node_id) stable_identity in
        let seed = Option.value ~default:(mixed_seed context identity) seed in
        match Rdk.Deform.noise_displace ~grain:(Context.grain context)
            ~cancel:(Context.cancel_token context)
            ~amplitude ~frequency ~seed inputs.(0) with
        | Ok geometry -> cooked geometry
        | Error error -> structured_rdk_error error)
  )
  let factory = parameters_factory build
  let fn = parameters_fn build
end

