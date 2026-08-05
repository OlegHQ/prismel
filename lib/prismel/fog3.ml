type mode =
  | Linear of { start : float; end_ : float }
  | Exponential of { density : float }
  | Exponential_squared of { density : float }

type t = {
  color : Color.t;
  mode : mode;
}

let linear ~color ~start ~end_ =
  if not (Float.is_finite start && Float.is_finite end_)
     || start < 0. || end_ <= start
  then
    invalid_arg
      "Fog3.linear: require finite distances with 0 <= start < end";
  { color; mode = Linear { start; end_ } }

let validate_density name density =
  if not (Float.is_finite density) || density <= 0. then
    invalid_arg (name ^ ": density must be finite and positive")

let exponential ~color ~density =
  validate_density "Fog3.exponential" density;
  { color; mode = Exponential { density } }

let exponential_squared ~color ~density =
  validate_density "Fog3.exponential_squared" density;
  { color; mode = Exponential_squared { density } }

let clamp value = Float.max 0. (Float.min 1. value)

module Private = struct
  let visibility fog ~distance =
    let distance = Float.max 0. distance in
    match fog.mode with
    | Linear { start; end_ } ->
        clamp ((end_ -. distance) /. (end_ -. start))
    | Exponential { density } ->
        clamp (exp (-.(density *. distance)))
    | Exponential_squared { density } ->
        let scaled = density *. distance in
        clamp (exp (-.(scaled *. scaled)))
end
