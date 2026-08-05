type attenuation = {
  constant : float;
  linear : float;
  quadratic : float;
}

type kind =
  | Ambient
  | Directional of { direction : Vec3.t }
  | Point of { position : Vec3.t; attenuation : attenuation }
  | Spot of {
      position : Vec3.t;
      direction : Vec3.t;
      cutoff : float;
      concentration : float;
      attenuation : attenuation;
    }
  | Area of {
      position : Vec3.t;
      direction : Vec3.t;
      width : float;
      height : float;
      samples : int;
      attenuation : attenuation;
    }

type t = {
  kind : kind;
  diffuse : Color.t;
  ambient : Color.t;
  specular : Color.t;
  intensity : float;
}

let no_attenuation = { constant = 1.; linear = 0.; quadratic = 0. }

let attenuation ?(constant = 1.) ?(linear = 0.) ?(quadratic = 0.) () =
  if constant < 0. || linear < 0. || quadratic < 0.
     || not (Float.is_finite constant)
     || not (Float.is_finite linear)
     || not (Float.is_finite quadratic)
  then invalid_arg "Light.attenuation: coefficients must be finite and non-negative";
  if constant = 0. && linear = 0. && quadratic = 0. then
    invalid_arg "Light.attenuation: at least one coefficient must be non-zero";
  { constant; linear; quadratic }

let validate_intensity intensity =
  if not (Float.is_finite intensity) || intensity < 0. then
    invalid_arg "Light: intensity must be finite and non-negative"

let make ?(diffuse = Color.white) ?(ambient = Color.black)
    ?(specular = Color.white) ?(intensity = 1.) kind =
  validate_intensity intensity;
  { kind; diffuse; ambient; specular; intensity }

let ambient ?(intensity = 1.) color =
  make ~diffuse:Color.black ~ambient:color ~specular:Color.black
    ~intensity Ambient

let direction value =
  if Vec3.length_sq value = 0. then
    invalid_arg "Light: direction must be non-zero";
  Vec3.normalize value

let directional ?diffuse ?ambient ?specular ?intensity ~direction:value () =
  make ?diffuse ?ambient ?specular ?intensity
    (Directional { direction = direction value })

let point ?diffuse ?ambient ?specular ?intensity
    ?(attenuation = no_attenuation) ~at () =
  make ?diffuse ?ambient ?specular ?intensity
    (Point { position = at; attenuation })

let spot ?diffuse ?ambient ?specular ?intensity
    ?(attenuation = no_attenuation) ~at ~direction:value ~cutoff
    ~concentration () =
  if not (Float.is_finite cutoff)
     || cutoff <= 0. || cutoff > Float.pi /. 2.
  then invalid_arg "Light.spot: cutoff must be in (0, pi/2]";
  if not (Float.is_finite concentration) || concentration < 0. then
    invalid_arg "Light.spot: concentration must be finite and non-negative";
  make ?diffuse ?ambient ?specular ?intensity
    (Spot {
       position = at;
       direction = direction value;
       cutoff;
       concentration;
       attenuation;
     })

let area ?diffuse ?ambient ?specular ?intensity
    ?(attenuation = no_attenuation) ?(samples = 9)
    ~at ~direction:value ~width ~height () =
  if not (Float.is_finite width && Float.is_finite height)
     || width <= 0. || height <= 0.
  then invalid_arg "Light.area: dimensions must be finite and positive";
  if not (List.mem samples [1; 4; 9; 16]) then
    invalid_arg "Light.area: samples must be 1, 4, 9, or 16";
  make ?diffuse ?ambient ?specular ?intensity
    (Area {
       position = at;
       direction = direction value;
       width;
       height;
       samples;
       attenuation;
     })
