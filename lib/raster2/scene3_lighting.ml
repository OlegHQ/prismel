type vec3 = { x : float; y : float; z : float }
type color = { r : float; g : float; b : float; a : float }
type attenuation = { constant : float; linear : float; quadratic : float }
type light =
  | Directional of { direction : vec3; color : color; intensity : float }
  | Point of { position : vec3; color : color; intensity : float; attenuation : attenuation }
  | Spot of { position : vec3; direction : vec3; inner_cos : float; outer_cos : float;
      color : color; intensity : float; attenuation : attenuation }
type material = { ambient : color; diffuse : color; specular : color; emissive : color; shininess : float }
type fog = No_fog | Linear of { color : color; near : float; far : float }
type descriptor = { ambient : color; lights : light array; material : material; fog : fog;
  separate_specular : bool; two_sided : bool }
type prepared = descriptor
type error = Non_finite | Invalid_color | Invalid_direction | Invalid_attenuation |
  Invalid_spot | Invalid_shininess | Invalid_fog | Too_many_lights

let finite = Float.is_finite
let valid_color c = finite c.r && finite c.g && finite c.b && finite c.a &&
  c.r >= 0. && c.r <= 1. && c.g >= 0. && c.g <= 1. && c.b >= 0. && c.b <= 1. && c.a >= 0. && c.a <= 1.
let length2 v = (v.x *. v.x) +. (v.y *. v.y) +. (v.z *. v.z)
let valid_vec v = finite v.x && finite v.y && finite v.z
let valid_direction v = valid_vec v && length2 v > 0.
let valid_attenuation a = finite a.constant && finite a.linear && finite a.quadratic &&
  a.constant >= 0. && a.linear >= 0. && a.quadratic >= 0. &&
  (a.constant > 0. || a.linear > 0. || a.quadratic > 0.)

let prepare descriptor =
  let material = descriptor.material in
  if Array.length descriptor.lights > 64 then Error Too_many_lights
  else if not (valid_color descriptor.ambient && valid_color material.ambient &&
    valid_color material.diffuse && valid_color material.specular && valid_color material.emissive)
  then Error Invalid_color
  else if not (finite material.shininess) || material.shininess < 0. || material.shininess > 1024.
  then Error Invalid_shininess
  else begin
    let error = ref None in
    for i = 0 to Array.length descriptor.lights - 1 do
      match descriptor.lights.(i) with
      | Directional l ->
          if not (valid_direction l.direction) then error := Some Invalid_direction
          else if not (valid_color l.color && finite l.intensity && l.intensity >= 0.) then error := Some Invalid_color
      | Point l ->
          if not (valid_vec l.position) then error := Some Non_finite
          else if not (valid_attenuation l.attenuation) then error := Some Invalid_attenuation
          else if not (valid_color l.color && finite l.intensity && l.intensity >= 0.) then error := Some Invalid_color
      | Spot l ->
          if not (valid_vec l.position && valid_direction l.direction) then error := Some Invalid_direction
          else if not (valid_attenuation l.attenuation) then error := Some Invalid_attenuation
          else if not (finite l.inner_cos && finite l.outer_cos && l.inner_cos >= l.outer_cos && l.inner_cos <= 1. && l.outer_cos >= -1.) then error := Some Invalid_spot
          else if not (valid_color l.color && finite l.intensity && l.intensity >= 0.) then error := Some Invalid_color
    done;
    match !error with Some e -> Error e | None ->
      match descriptor.fog with
      | Linear f when not (valid_color f.color && finite f.near && finite f.far && f.near >= 0. && f.far > f.near) -> Error Invalid_fog
      | _ -> Ok descriptor
  end

let orient_normal ~reversed_winding normal =
  if reversed_winding then { x = -.normal.x; y = -.normal.y; z = -.normal.z } else normal
let clamp x = max 0. (min 1. x)
let normalize v = let inv = 1. /. sqrt (length2 v) in (v.x *. inv, v.y *. inv, v.z *. inv)
let dot ax ay az bx by bz = (ax *. bx) +. (ay *. by) +. (az *. bz)
let channel c shift = Float.of_int Int32.(to_int (logand (shift_right_logical c shift) 0xffl)) /. 255.
let pack r g b a =
  let c x = Int32.of_int (int_of_float ((clamp x *. 255.) +. 0.5)) in
  Int32.(logor (shift_left (c r) 24) (logor (shift_left (c g) 16) (logor (shift_left (c b) 8) (c a))))

let shade descriptor ~position ~normal ~view ~front_facing ~texture ~fog_distance =
  if not (valid_direction normal && valid_direction view && valid_vec position && finite fog_distance) then 0l else
  let nx, ny, nz = normalize normal in
  let nx, ny, nz = if descriptor.two_sided && not front_facing then (-.nx, -.ny, -.nz) else (nx, ny, nz) in
  let vx, vy, vz = normalize view in
  let material = descriptor.material in
  let primary_r = ref (material.emissive.r +. material.ambient.r *. descriptor.ambient.r)
  and primary_g = ref (material.emissive.g +. material.ambient.g *. descriptor.ambient.g)
  and primary_b = ref (material.emissive.b +. material.ambient.b *. descriptor.ambient.b)
  and spec_r = ref 0. and spec_g = ref 0. and spec_b = ref 0. in
  for i = 0 to Array.length descriptor.lights - 1 do
    let lx, ly, lz, strength, color = match descriptor.lights.(i) with
      | Directional l -> let x,y,z = normalize l.direction in (-.x,-.y,-.z,l.intensity,l.color)
      | Point l ->
          let dx = l.position.x -. position.x and dy = l.position.y -. position.y and dz = l.position.z -. position.z in
          let distance = sqrt ((dx*.dx)+.(dy*.dy)+.(dz*.dz)) in
          let inv = if distance = 0. then 0. else 1. /. distance in
          let a = l.attenuation in (dx*.inv,dy*.inv,dz*.inv,l.intensity /. (a.constant +. a.linear*.distance +. a.quadratic*.distance*.distance),l.color)
      | Spot l ->
          let dx = l.position.x -. position.x and dy = l.position.y -. position.y and dz = l.position.z -. position.z in
          let distance = sqrt ((dx*.dx)+.(dy*.dy)+.(dz*.dz)) in
          let inv = if distance = 0. then 0. else 1. /. distance in
          let lx,ly,lz = (dx*.inv,dy*.inv,dz*.inv) and sx,sy,sz = normalize l.direction in
          let cosine = -.dot lx ly lz sx sy sz in
          let cone = if cosine <= l.outer_cos then 0. else if cosine >= l.inner_cos then 1. else (cosine -. l.outer_cos) /. (l.inner_cos -. l.outer_cos) in
          let a=l.attenuation in (lx,ly,lz,cone*.l.intensity /. (a.constant +. a.linear*.distance +. a.quadratic*.distance*.distance),l.color)
    in
    let diffuse = max 0. (dot nx ny nz lx ly lz) *. strength in
    primary_r := !primary_r +. material.diffuse.r *. color.r *. diffuse;
    primary_g := !primary_g +. material.diffuse.g *. color.g *. diffuse;
    primary_b := !primary_b +. material.diffuse.b *. color.b *. diffuse;
    if diffuse > 0. then begin
      let hx,hy,hz = normalize {x=lx+.vx;y=ly+.vy;z=lz+.vz} in
      let specular = (max 0. (dot nx ny nz hx hy hz) ** material.shininess) *. strength in
      spec_r := !spec_r +. material.specular.r *. color.r *. specular;
      spec_g := !spec_g +. material.specular.g *. color.g *. specular;
      spec_b := !spec_b +. material.specular.b *. color.b *. specular
    end
  done;
  let tr,tg,tb,ta = match texture with None -> (1.,1.,1.,1.) | Some c -> (channel c 24,channel c 16,channel c 8,channel c 0) in
  let r,g,b = if descriptor.separate_specular then
    (!primary_r*.tr +. !spec_r, !primary_g*.tg +. !spec_g, !primary_b*.tb +. !spec_b)
    else ((!primary_r+. !spec_r)*.tr,(!primary_g+. !spec_g)*.tg,(!primary_b+. !spec_b)*.tb) in
  let r,g,b = match descriptor.fog with No_fog -> (r,g,b) | Linear f ->
    let amount = clamp ((fog_distance -. f.near) /. (f.far -. f.near)) in
    (r*.(1.-.amount)+.f.color.r*.amount,g*.(1.-.amount)+.f.color.g*.amount,b*.(1.-.amount)+.f.color.b*.amount) in
  pack r g b (material.diffuse.a *. ta)
