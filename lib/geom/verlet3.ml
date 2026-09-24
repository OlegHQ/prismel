open Prismel

type particle = {
  position : Vec3.t;
  previous : Vec3.t;
  force : Vec3.t;
  inverse_mass : float;
  locked : bool;
  behaviors : behavior list;
  constraints : constraint_ list;
}
and behavior = particle -> dt:float -> Vec3.t
and constraint_ = particle -> particle

type spring = {
  a : int;
  b : int;
  rest_length : float;
  strength : float;
  min_length : float option;
}

type t = {
  particles : particle array;
  springs : spring array;
  drag : float;
  iterations : int;
  behaviors : behavior list;
  constraints : constraint_ list;
}

let particle ?(mass = 1.) ?(locked = false) ?(velocity = Vec3.zero) position =
  if not (Float.is_finite mass) || mass <= 0. then
    invalid_arg "Verlet3.particle: mass must be finite and positive";
  { position; previous = Vec3.sub position velocity; force = Vec3.zero;
    inverse_mass = 1. /. mass; locked; behaviors = []; constraints = [] }

let position particle = particle.position
let previous_position particle = particle.previous
let velocity particle = Vec3.sub particle.position particle.previous
let mass particle = 1. /. particle.inverse_mass
let locked particle = particle.locked
let lock particle = { particle with locked = true }
let unlock particle = { particle with locked = false }

let with_position ?(preserve_velocity = false) position particle =
  let previous =
    if preserve_velocity then Vec3.sub position (velocity particle) else position
  in
  { particle with position; previous }

let with_velocity velocity particle =
  { particle with previous = Vec3.sub particle.position velocity }
let add_force force particle =
  { particle with force = Vec3.add particle.force force }
let clear_force particle = { particle with force = Vec3.zero }
let add_behavior behavior (particle : particle) =
  { particle with behaviors = behavior :: particle.behaviors }
let add_constraint constraint_ (particle : particle) =
  { particle with constraints = constraint_ :: particle.constraints }

let validate_spring strength rest_length =
  if not (Float.is_finite strength) || strength < 0. || strength > 1. then
    invalid_arg "Verlet3.spring: strength must be in zero to one";
  if not (Float.is_finite rest_length) || rest_length < 0. then
    invalid_arg "Verlet3.spring: rest length must be finite and non-negative"

let spring ?(strength = 1.) ?rest_length a b =
  if a < 0 || b < 0 || a = b then
    invalid_arg "Verlet3.spring: particle indices must be distinct and non-negative";
  let rest_length = Option.value rest_length ~default:0. in
  validate_spring strength rest_length;
  { a; b; rest_length; strength; min_length = None }

let pullback_spring ?(strength = 1.) ~rest_length ~min_length a b =
  validate_spring strength rest_length;
  if not (Float.is_finite min_length) || min_length < 0. then
    invalid_arg "Verlet3.pullback_spring: min_length must be non-negative";
  { (spring ~strength ~rest_length a b) with min_length = Some min_length }

let validate_indices count springs =
  match List.find_opt (fun spring -> spring.a >= count || spring.b >= count) springs with
  | None -> Ok ()
  | Some _ -> Error "Verlet3.create: spring particle index is out of range"

let create ?(drag = 0.01) ?(iterations = 4) ?(behaviors = [])
    ?(constraints = []) particles springs =
  if not (Float.is_finite drag) || drag < 0. || drag > 1. then
    invalid_arg "Verlet3.create: drag must be in zero to one";
  if iterations <= 0 then invalid_arg "Verlet3.create: iterations must be positive";
  Result.map
    (fun () ->
      { particles = Array.of_list particles; springs = Array.of_list springs;
        drag; iterations;
        behaviors; constraints })
    (validate_indices (List.length particles) springs)

let particles world = Array.to_list world.particles
let springs world = Array.to_list world.springs
let particle_count world = Array.length world.particles
let particle_at index world =
  if index < 0 || index >= particle_count world then None
  else Some world.particles.(index)

let with_particle index particle world =
  if index < 0 || index >= particle_count world then
    Error "Verlet3.with_particle: index is out of range"
  else
    let particles = Array.copy world.particles in
    particles.(index) <- particle;
    Ok { world with particles }

let add_particle particle world =
  { world with particles = Array.append world.particles [|particle|] }

let add_spring spring world =
  Result.map (fun () ->
      let count = Array.length world.springs in
      let springs = Array.make (count + 1) spring in
      Array.blit world.springs 0 springs 1 count;
      { world with springs })
    (validate_indices (particle_count world) [spring])

let add_behavior_to_world behavior world =
  { world with behaviors = behavior :: world.behaviors }
let add_constraint_to_world constraint_ world =
  { world with constraints = constraint_ :: world.constraints }

let apply_constraints global_constraints particle =
  if particle.locked then particle
  else
    let particle = List.fold_left
        (fun particle constraint_ -> constraint_ particle)
        particle global_constraints in
    List.fold_left (fun particle constraint_ -> constraint_ particle)
      particle particle.constraints

let integrate drag dt global_behaviors particle =
  if particle.locked then clear_force particle
  else
    let add_behavior (fx, fy, fz) behavior =
      let added = behavior particle ~dt in
      fx +. added.Vec3.x, fy +. added.y, fz +. added.z
    in
    let fx, fy, fz =
      List.fold_left add_behavior
        (particle.force.x, particle.force.y, particle.force.z) global_behaviors
      |> fun force -> List.fold_left add_behavior force particle.behaviors
    in
    let velocity_scale = 1. -. drag in
    let acceleration_scale = particle.inverse_mass *. dt *. dt in
    let position = Vec3.create
        (particle.position.x
         +. ((particle.position.x -. particle.previous.x) *. velocity_scale)
         +. (fx *. acceleration_scale))
        (particle.position.y
         +. ((particle.position.y -. particle.previous.y) *. velocity_scale)
         +. (fy *. acceleration_scale))
        (particle.position.z
         +. ((particle.position.z -. particle.previous.z) *. velocity_scale)
         +. (fz *. acceleration_scale)) in
    { particle with
      position;
      previous = particle.position;
      force = Vec3.zero }

let solve_spring particles spring =
  let left = particles.(spring.a) and right = particles.(spring.b) in
  let dx = right.position.x -. left.position.x
  and dy = right.position.y -. left.position.y
  and dz = right.position.z -. left.position.z in
  let distance = sqrt ((dx *. dx) +. (dy *. dy) +. (dz *. dz)) in
  let active =
    match spring.min_length with
    | None -> true
    | Some minimum -> distance > minimum
  in
  if active && distance > 1e-12 then begin
    let left_weight = if left.locked then 0. else left.inverse_mass
    and right_weight = if right.locked then 0. else right.inverse_mass in
    let total = left_weight +. right_weight in
    if total > 0. then begin
      let correction =
        ((distance -. spring.rest_length) /. distance) *. spring.strength in
      if left_weight > 0. then begin
        let amount = correction *. left_weight /. total in
        particles.(spring.a) <- { left with position = Vec3.create
            (left.position.x +. (dx *. amount))
            (left.position.y +. (dy *. amount))
            (left.position.z +. (dz *. amount)) }
      end;
      if right_weight > 0. then begin
        let amount = correction *. right_weight /. total in
        particles.(spring.b) <- { right with position = Vec3.create
            (right.position.x -. (dx *. amount))
            (right.position.y -. (dy *. amount))
            (right.position.z -. (dz *. amount)) }
      end
    end
  end

let step ~dt world =
  if not (Float.is_finite dt) || dt <= 0. then
    invalid_arg "Verlet3.step: dt must be finite and positive";
  let has_particle_behaviors =
    Array.exists (fun (particle : particle) -> particle.behaviors <> [])
      world.particles in
  let particles =
    if world.behaviors = [] && not has_particle_behaviors then
      Parallel.map_array ~grain:2048 (integrate world.drag dt []) world.particles
    else Array.map (integrate world.drag dt world.behaviors) world.particles in
  let has_constraints =
    world.constraints <> []
    || Array.exists (fun (particle : particle) -> particle.constraints <> [])
         particles in
  for _ = 1 to world.iterations do
    Array.iter (solve_spring particles) world.springs;
    if has_constraints then
      Array.iteri
        (fun index (particle : particle) ->
          particles.(index) <- apply_constraints world.constraints particle)
        particles
  done;
  { world with particles }

let gravity force _particle ~dt:_ = force

let attract ~center ~radius ~strength particle ~dt:_ =
  if not (Float.is_finite radius) || radius <= 0. then
    invalid_arg "Verlet3.attract: radius must be positive";
  let delta = Vec3.sub center particle.position in
  let distance_sq = Vec3.length_sq delta in
  let radius_sq = radius *. radius in
  if distance_sq <= 1e-18 || distance_sq >= radius_sq then Vec3.zero
  else
    Vec3.scale (Vec3.normalize delta)
      (strength *. (1. -. (distance_sq /. radius_sq)))

let align ~velocity:target ~strength particle ~dt:_ =
  Vec3.scale (Vec3.sub target (velocity particle)) strength

let set_constrained_position position particle = { particle with position }
let inside_bounds bounds particle =
  set_constrained_position (Bounds3.closest_point bounds particle.position) particle

let on_sphere sphere particle =
  set_constrained_position (Sphere3.closest_point sphere particle.position) particle

let inside_sphere sphere particle =
  if Sphere3.contains sphere particle.position then particle
  else on_sphere sphere particle

let outside_sphere sphere particle =
  if Sphere3.contains sphere particle.position then on_sphere sphere particle
  else particle
