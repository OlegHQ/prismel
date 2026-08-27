type vec3 = { x : float; y : float; z : float }
type color = { r : float; g : float; b : float; a : float }
type attenuation = { constant : float; linear : float; quadratic : float }
type light =
  | Directional of { direction : vec3; color : color; intensity : float }
  | Point of { position : vec3; color : color; intensity : float; attenuation : attenuation }
  | Spot of { position : vec3; direction : vec3; inner_cos : float; outer_cos : float;
      concentration : float; color : color; intensity : float; attenuation : attenuation }
type material = { ambient : color; diffuse : color; specular : color; emissive : color; shininess : float }
type fog = No_fog | Linear of { color : color; near : float; far : float }
type descriptor = { ambient : color; lights : light array; material : material; fog : fog;
  separate_specular : bool; two_sided : bool }
type prepared
type error = Non_finite | Invalid_color | Invalid_direction | Invalid_attenuation |
  Invalid_spot | Invalid_shininess | Invalid_fog | Invalid_shadow | Too_many_lights

val prepare : descriptor -> (prepared, error) result
val prepare_with_shadows : descriptor -> Shadow_map.prepared option array -> (prepared, error) result
(* Reverses authored normals when winding extraction reverses a source facet. *)
val orient_normal : reversed_winding:bool -> vec3 -> vec3
(* Returns straight-alpha 0xRRGGBBAA. The hot evaluator allocates no containers. *)
val shade : prepared -> position:vec3 -> normal:vec3 -> view:vec3 ->
  front_facing:bool -> texture:int32 option -> fog_distance:float -> int32
