open Tsdl

type rgba = {
  red : float;
  green : float;
  blue : float;
  alpha : float;
}

type vertex = {
  x : float;
  y : float;
  depth : float;
  inv_w : float;
  world : Vec3.t;
  normal : Vec3.t;
  tex_coord : Vec2.t;
  color : rgba;
  direct : rgba array;
  specular : rgba array;
  varyings : float array;
}

type clip_vertex = {
  clip_x : float;
  clip_y : float;
  clip_z : float;
  clip_w : float;
  world : Vec3.t;
  normal : Vec3.t;
  tex_coord : Vec2.t;
  color : rgba;
  direct : rgba array;
  specular : rgba array;
  varyings : float array;
}

let[@inline always] clamp value = Float.max 0. (Float.min 1. value)

let rgba color =
  {
    red = float_of_int color.Color.r /. 255.;
    green = float_of_int color.g /. 255.;
    blue = float_of_int color.b /. 255.;
    alpha = float_of_int color.a /. 255.;
  }

let multiply left right =
  {
    red = left.red *. right.red;
    green = left.green *. right.green;
    blue = left.blue *. right.blue;
    alpha = left.alpha *. right.alpha;
  }

let color_of_rgba color =
  Color.of_floats
    (clamp color.red) (clamp color.green) (clamp color.blue)
    (clamp color.alpha)

let attenuation coefficient distance =
  let divisor =
    coefficient.Light.constant
    +. (coefficient.linear *. distance)
    +. (coefficient.quadratic *. distance *. distance)
  in
  if divisor <= 1e-12 then 1. else 1. /. divisor

type lighting = {
  indirect : rgba;
  direct : rgba array;
  specular : rgba array;
}

type prepared_light = {
  source : Light.t;
  ambient : rgba;
  diffuse : rgba;
  specular : rgba;
}

type lighting_context = {
  camera_position : Vec3.t;
  ambient : rgba;
  lights : prepared_light array;
  material_ambient : rgba;
  material_diffuse : rgba;
  material_specular : rgba;
  material_emissive : rgba;
  shininess : float;
}

let prepare_lighting ~camera ~ambient ~lights ~material = {
  camera_position = Camera.position camera;
  ambient = rgba ambient;
  lights = Array.map (fun source -> {
    source;
    ambient = rgba source.Light.ambient;
    diffuse = rgba source.diffuse;
    specular = rgba source.specular;
  }) lights;
  material_ambient = rgba material.Material.ambient;
  material_diffuse = rgba material.diffuse;
  material_specular = rgba material.specular;
  material_emissive = rgba material.emissive;
  shininess = material.shininess;
}

let shade ?(collapse = false) context ~vertex_color ~world ~normal =
  let normal = Vec3.normalize normal in
  let vx = context.camera_position.x -. world.Vec3.x
  and vy = context.camera_position.y -. world.y
  and vz = context.camera_position.z -. world.z in
  let view_length = sqrt ((vx *. vx) +. (vy *. vy) +. (vz *. vz)) in
  let vx, vy, vz = if view_length <= 1e-18 then 0., 0., 0.
    else vx /. view_length, vy /. view_length, vz /. view_length in
  let material_diffuse = multiply context.material_diffuse vertex_color in
  let indirect_red = ref
      ((context.material_ambient.red *. context.ambient.red)
       +. context.material_emissive.red)
  and indirect_green = ref
      ((context.material_ambient.green *. context.ambient.green)
       +. context.material_emissive.green)
  and indirect_blue = ref
      ((context.material_ambient.blue *. context.ambient.blue)
       +. context.material_emissive.blue) in
  let transparent = rgba Color.transparent in
  let direct =
    if collapse then [||]
    else Array.make (Array.length context.lights) transparent
  and separate_specular =
    if collapse then [||]
    else Array.make (Array.length context.lights) transparent
  in
  let collapsed_red = ref 0. and collapsed_green = ref 0.
  and collapsed_blue = ref 0. in
  for light_index = 0 to Array.length context.lights - 1 do
      let prepared = context.lights.(light_index) in
      let light = prepared.source in
      let intensity = light.Light.intensity in
      indirect_red := !indirect_red
        +. (context.material_ambient.red *. prepared.ambient.red *. intensity);
      indirect_green := !indirect_green
        +. (context.material_ambient.green *. prepared.ambient.green *. intensity);
      indirect_blue := !indirect_blue
        +. (context.material_ambient.blue *. prepared.ambient.blue *. intensity);
      let diffuse_factor = ref 0. and specular_factor = ref 0. in
      let[@inline always] accumulate tx ty tz falloff =
        let diffuse_amount = Float.max 0.
            ((normal.x *. tx) +. (normal.y *. ty) +. (normal.z *. tz)) in
        diffuse_factor := !diffuse_factor +. (diffuse_amount *. falloff);
        if diffuse_amount > 0. then begin
          let hx = tx +. vx and hy = ty +. vy and hz = tz +. vz in
          let length = sqrt ((hx *. hx) +. (hy *. hy) +. (hz *. hz)) in
          if length > 1e-18 then begin
            let amount = Float.max 0.
                ((normal.x *. hx +. normal.y *. hy +. normal.z *. hz)
                 /. length) ** context.shininess in
            specular_factor := !specular_factor +. (amount *. falloff)
          end
        end in
      (match light.kind with
      | Light.Ambient -> ()
      | Directional { direction } ->
          accumulate (-.direction.x) (-.direction.y) (-.direction.z) 1.
      | Point { position; attenuation = coefficient } ->
          let dx = position.x -. world.x and dy = position.y -. world.y
          and dz = position.z -. world.z in
          let distance = sqrt ((dx *. dx) +. (dy *. dy) +. (dz *. dz)) in
          if distance > 1e-18 then
            accumulate (dx /. distance) (dy /. distance) (dz /. distance)
              (attenuation coefficient distance)
      | Spot { position; direction; cutoff; concentration;
               attenuation = coefficient } ->
          let dx = position.x -. world.x and dy = position.y -. world.y
          and dz = position.z -. world.z in
          let distance = sqrt ((dx *. dx) +. (dy *. dy) +. (dz *. dz)) in
          if distance > 1e-18 then begin
            let tx = dx /. distance and ty = dy /. distance
            and tz = dz /. distance in
            let cosine = -.tx *. direction.x -. ty *. direction.y
                -. tz *. direction.z in
            if cosine >= cos cutoff then
              accumulate tx ty tz
                (attenuation coefficient distance *. (cosine ** concentration))
          end
      | Area { position; direction; width; height; samples;
               attenuation = coefficient } ->
          let reference =
            if abs_float direction.y < 0.99 then Vec3.unit_y else Vec3.unit_x in
          let right = Vec3.cross direction reference |> Vec3.normalize in
          let up = Vec3.cross right direction |> Vec3.normalize in
          let factor = int_of_float (sqrt (float_of_int samples)) in
          let sample_weight = 1. /. float_of_int samples in
          for sample = 0 to samples - 1 do
            let column = sample mod factor and row = sample / factor in
            let horizontal =
              ((float_of_int column +. 0.5) /. float_of_int factor -. 0.5)
              *. width
            and vertical =
              ((float_of_int row +. 0.5) /. float_of_int factor -. 0.5)
              *. height in
            let dx = position.x +. right.x *. horizontal +. up.x *. vertical
                -. world.x
            and dy = position.y +. right.y *. horizontal +. up.y *. vertical
                -. world.y
            and dz = position.z +. right.z *. horizontal +. up.z *. vertical
                -. world.z in
            let distance = sqrt ((dx *. dx) +. (dy *. dy) +. (dz *. dz)) in
            if distance > 1e-18 then begin
              let tx = dx /. distance and ty = dy /. distance
              and tz = dz /. distance in
              let facing = Float.max 0.
                  (-.tx *. direction.x -. ty *. direction.y
                   -. tz *. direction.z) in
              let falloff = attenuation coefficient distance
                  *. facing *. sample_weight in
              if falloff > 0. then accumulate tx ty tz falloff
            end
          done);
      let diffuse_factor = !diffuse_factor *. intensity
      and specular_factor = !specular_factor *. intensity in
      let direct_red =
        material_diffuse.red *. prepared.diffuse.red *. diffuse_factor
      and direct_green =
        material_diffuse.green *. prepared.diffuse.green *. diffuse_factor
      and direct_blue =
        material_diffuse.blue *. prepared.diffuse.blue *. diffuse_factor
      and specular_red =
        context.material_specular.red *. prepared.specular.red *. specular_factor
      and specular_green =
        context.material_specular.green *. prepared.specular.green
        *. specular_factor
      and specular_blue =
        context.material_specular.blue *. prepared.specular.blue
        *. specular_factor
      in
      if collapse then begin
        collapsed_red := !collapsed_red +. direct_red +. specular_red;
        collapsed_green := !collapsed_green +. direct_green +. specular_green;
        collapsed_blue := !collapsed_blue +. direct_blue +. specular_blue
      end else begin
        direct.(light_index) <- {
          red = direct_red; green = direct_green; blue = direct_blue; alpha = 0.;
        };
        separate_specular.(light_index) <- {
          red = specular_red;
          green = specular_green;
          blue = specular_blue;
          alpha = 0.;
        }
      end
  done;
  {
    indirect = {
      red = !indirect_red +. !collapsed_red;
      green = !indirect_green +. !collapsed_green;
      blue = !indirect_blue +. !collapsed_blue;
      alpha = material_diffuse.alpha;
    };
    direct;
    specular = separate_specular;
  }

let[@inline always] byte_of_unit_float value =
  int_of_float ((clamp value *. 255.) +. 0.5)

let[@inline always] write_color pixels index red green blue alpha =
  let offset = index * 4 in
  Bigarray.Array1.unsafe_set pixels offset (byte_of_unit_float red);
  Bigarray.Array1.unsafe_set pixels (offset + 1) (byte_of_unit_float green);
  Bigarray.Array1.unsafe_set pixels (offset + 2) (byte_of_unit_float blue);
  Bigarray.Array1.unsafe_set pixels (offset + 3) (byte_of_unit_float alpha)

let interpolate_color a b c wa wb wc =
  {
    red = (a.red *. wa) +. (b.red *. wb) +. (c.red *. wc);
    green = (a.green *. wa) +. (b.green *. wb) +. (c.green *. wc);
    blue = (a.blue *. wa) +. (b.blue *. wb) +. (c.blue *. wc);
    alpha = (a.alpha *. wa) +. (b.alpha *. wb) +. (c.alpha *. wc);
  }

let interpolate_color_arrays a b c wa wb wc =
  Array.init (Array.length a) (fun index ->
    interpolate_color a.(index) b.(index) c.(index) wa wb wc)

let interpolate_vec2 (a : Vec2.t) (b : Vec2.t) (c : Vec2.t) wa wb wc =
  Vec2.create
    ((a.Vec2.x *. wa) +. (b.x *. wb) +. (c.x *. wc))
    ((a.y *. wa) +. (b.y *. wb) +. (c.y *. wc))

let interpolate_vec3 (a : Vec3.t) (b : Vec3.t) (c : Vec3.t) wa wb wc =
  Vec3.create
    ((a.Vec3.x *. wa) +. (b.x *. wb) +. (c.x *. wc))
    ((a.y *. wa) +. (b.y *. wb) +. (c.y *. wc))
    ((a.z *. wa) +. (b.z *. wb) +. (c.z *. wc))

let interpolate_varyings a b c wa wb wc =
  Array.init (Array.length a) (fun index ->
    (a.(index) *. wa) +. (b.(index) *. wb) +. (c.(index) *. wc))

let[@inline always] edge ax ay bx by px py =
  ((px -. ax) *. (by -. ay)) -. ((py -. ay) *. (bx -. ax))

type framebuffer = {
  width : int;
  height : int;
  depths : float array;
  stencils : int array;
  opaque_red : float array;
  opaque_green : float array;
  opaque_blue : float array;
  opaque_alpha : float array;
  opaque_set : bytes;
  pixels :
    (int, Bigarray.int8_unsigned_elt, Bigarray.c_layout) Bigarray.Array1.t;
  mutable downsampled_pixels :
    (int, Bigarray.int8_unsigned_elt, Bigarray.c_layout) Bigarray.Array1.t option;
  transparent :
    (float * Scene3.comparison * Scene3.blend * rgba) list array;
}

let framebuffer_cache : framebuffer option ref = ref None

let create_framebuffer ~width ~height ~depth_clear ~stencil_clear =
  let length = width * height in
  {
    width;
    height;
    depths = Array.make length depth_clear;
    stencils = Array.make length stencil_clear;
    opaque_red = Array.make length 0.;
    opaque_green = Array.make length 0.;
    opaque_blue = Array.make length 0.;
    opaque_alpha = Array.make length 0.;
    opaque_set = Bytes.make length '\000';
    pixels = Bigarray.Array1.create Bigarray.int8_unsigned Bigarray.c_layout
        (length * 4);
    downsampled_pixels = None;
    transparent = Array.make length [];
  }

let acquire_framebuffer ~width ~height ~depth_clear ~stencil_clear =
  let framebuffer = match !framebuffer_cache with
    | Some framebuffer
      when framebuffer.width = width && framebuffer.height = height ->
        let length = width * height in
        Array.fill framebuffer.depths 0 length depth_clear;
        Array.fill framebuffer.stencils 0 length stencil_clear;
        Array.fill framebuffer.opaque_red 0 length 0.;
        Array.fill framebuffer.opaque_green 0 length 0.;
        Array.fill framebuffer.opaque_blue 0 length 0.;
        Array.fill framebuffer.opaque_alpha 0 length 0.;
        Bytes.fill framebuffer.opaque_set 0 length '\000';
        Array.fill framebuffer.transparent 0 length [];
        framebuffer
    | _ ->
        let framebuffer =
          create_framebuffer ~width ~height ~depth_clear ~stencil_clear in
        framebuffer_cache := Some framebuffer;
        framebuffer in
  framebuffer

let[@inline always] compare_float comparison incoming stored =
  match comparison with
  | Scene3.Never -> false
  | Less -> incoming < stored
  | Equal -> incoming = stored
  | Less_equal -> incoming <= stored
  | Greater -> incoming > stored
  | Not_equal -> incoming <> stored
  | Greater_equal -> incoming >= stored
  | Always -> true

let[@inline always] compare_int comparison incoming stored =
  match comparison with
  | Scene3.Never -> false
  | Less -> incoming < stored
  | Equal -> incoming = stored
  | Less_equal -> incoming <= stored
  | Greater -> incoming > stored
  | Not_equal -> incoming <> stored
  | Greater_equal -> incoming >= stored
  | Always -> true

let stencil_result operation ~reference current =
  match operation with
  | Scene3.Keep -> current
  | Zero -> 0
  | Replace -> reference
  | Increment -> min 0xff (current + 1)
  | Decrement -> max 0 (current - 1)
  | Increment_wrap -> (current + 1) land 0xff
  | Decrement_wrap -> (current - 1) land 0xff
  | Invert -> (lnot current) land 0xff

let[@inline always] apply_stencil framebuffer index state operation =
  let current = framebuffer.stencils.(index) in
  let result =
    stencil_result operation ~reference:state.Scene3.reference current
  in
  let write_mask = state.write_mask in
  framebuffer.stencils.(index) <-
    (current land ((lnot write_mask) land 0xff))
    lor (result land write_mask)

let[@inline always] test_pixel_index framebuffer
    ~(depth_state : Scene3.depth_state)
    ~(stencil_state : Scene3.stencil_state)
    x y depth =
  if x >= 0 && y >= 0
     && x < framebuffer.width && y < framebuffer.height
     && Float.is_finite depth && depth >= 0. && depth <= 1.
  then
    let index = (y * framebuffer.width) + x in
    let stencil_passes =
      compare_int stencil_state.Scene3.comparison
        (stencil_state.reference land stencil_state.read_mask)
        (framebuffer.stencils.(index) land stencil_state.read_mask)
    in
    if not stencil_passes then
      begin
        apply_stencil framebuffer index stencil_state
          stencil_state.on_stencil_fail;
        -1
      end
    else
      let depth_passes =
        compare_float depth_state.Scene3.comparison
          depth framebuffer.depths.(index)
      in
      if not depth_passes then
        begin
          apply_stencil framebuffer index stencil_state
            stencil_state.on_depth_fail;
          -1
        end
      else index
  else -1

let[@inline always] commit_pixel_components framebuffer index
    ~(depth_state : Scene3.depth_state)
    ~(stencil_state : Scene3.stencil_state)
    ~(blend : Scene3.blend) depth red green blue source_alpha =
  apply_stencil framebuffer index stencil_state stencil_state.on_pass;
  let alpha = clamp source_alpha in
  if blend = Scene3.Replace || (blend = Alpha && alpha >= 0.999) then begin
    if depth_state.write then framebuffer.depths.(index) <- depth;
    framebuffer.opaque_red.(index) <- red;
    framebuffer.opaque_green.(index) <- green;
    framebuffer.opaque_blue.(index) <- blue;
    framebuffer.opaque_alpha.(index) <-
      (if blend = Alpha then 1. else alpha);
    Bytes.set framebuffer.opaque_set index '\001'
  end else if alpha > 0. then
    framebuffer.transparent.(index) <-
      (depth, depth_state.comparison, blend,
       { red; green; blue; alpha })
      :: framebuffer.transparent.(index)

let commit_pixel framebuffer index
    ~(depth_state : Scene3.depth_state)
    ~(stencil_state : Scene3.stencil_state)
    ~(blend : Scene3.blend) depth color =
  commit_pixel_components framebuffer index ~depth_state ~stencil_state
    ~blend depth color.red color.green color.blue color.alpha

let write_pixel framebuffer ~depth_state ~stencil_state ~blend
    x y depth color =
  let index = test_pixel_index framebuffer ~depth_state ~stencil_state
      x y depth in
  if index >= 0 then
    commit_pixel framebuffer index ~depth_state ~stencil_state ~blend depth color

let over source destination =
  let source_alpha = clamp source.alpha
  and destination_alpha = clamp destination.alpha in
  let alpha =
    source_alpha +. (destination_alpha *. (1. -. source_alpha))
  in
  if alpha <= 1e-12 then rgba Color.transparent
  else
    let channel source destination =
      ((source *. source_alpha)
       +. (destination *. destination_alpha *. (1. -. source_alpha)))
      /. alpha
    in
    {
      red = channel source.red destination.red;
      green = channel source.green destination.green;
      blue = channel source.blue destination.blue;
      alpha;
    }

let blend source destination = function
  | Scene3.Replace -> source
  | Alpha -> over source destination
  | Add | Multiply | Screen | Subtract as mode ->
      let amount = clamp source.alpha in
      let channel source destination =
        match mode with
        | Add -> destination +. (source *. amount)
        | Multiply ->
            destination *. ((source *. amount) +. (1. -. amount))
        | Screen ->
            1. -. ((1. -. destination) *. (1. -. (source *. amount)))
        | Subtract -> destination -. (source *. amount)
        | Replace | Alpha -> assert false
      in
      {
        red = channel source.red destination.red;
        green = channel source.green destination.green;
        blue = channel source.blue destination.blue;
        alpha =
          amount +. (clamp destination.alpha *. (1. -. amount));
      }

let resolve framebuffer =
  let transparent = rgba Color.transparent in
  Array.mapi
    (fun index fragments ->
      let opaque_depth = framebuffer.depths.(index) in
      let destination =
        if Bytes.get framebuffer.opaque_set index = '\000'
        then transparent
        else {
          red = framebuffer.opaque_red.(index);
          green = framebuffer.opaque_green.(index);
          blue = framebuffer.opaque_blue.(index);
          alpha = framebuffer.opaque_alpha.(index);
        } in
      let color = match fragments with
        | [] -> destination
        | _ ->
            List.filter
              (fun (depth, comparison, _, _) ->
                compare_float comparison depth opaque_depth)
              fragments
            |> List.sort
                 (fun (left, _, _, _) (right, _, _, _) ->
                   Float.compare right left)
            |> List.fold_left
                 (fun destination (_, _, mode, source) ->
                   blend source destination mode)
                 destination
      in
      color)
    framebuffer.transparent

let pack_framebuffer framebuffer =
  let length = framebuffer.width * framebuffer.height in
  let pixels = framebuffer.pixels in
  Bigarray.Array1.fill pixels 0;
  for index = 0 to length - 1 do
    let fragments = framebuffer.transparent.(index) in
    match fragments with
    | [] ->
        if Bytes.get framebuffer.opaque_set index <> '\000' then
          write_color pixels index
            framebuffer.opaque_red.(index)
            framebuffer.opaque_green.(index)
            framebuffer.opaque_blue.(index)
            framebuffer.opaque_alpha.(index)
    | _ ->
        let opaque_depth = framebuffer.depths.(index) in
        let destination =
          if Bytes.get framebuffer.opaque_set index = '\000' then
            rgba Color.transparent
          else {
            red = framebuffer.opaque_red.(index);
            green = framebuffer.opaque_green.(index);
            blue = framebuffer.opaque_blue.(index);
            alpha = framebuffer.opaque_alpha.(index);
          }
        in
        let color =
          List.filter
            (fun (depth, comparison, _, _) ->
              compare_float comparison depth opaque_depth)
            fragments
          |> List.sort
               (fun (left, _, _, _) (right, _, _, _) ->
                 Float.compare right left)
          |> List.fold_left
               (fun destination (_, _, mode, source) ->
                 blend source destination mode)
               destination
        in
        write_color pixels index color.red color.green color.blue color.alpha
  done;
  pixels

let acquire_downsampled_pixels framebuffer length =
  match framebuffer.downsampled_pixels with
  | Some pixels when Bigarray.Array1.dim pixels = length -> pixels
  | _ ->
      let pixels =
        Bigarray.Array1.create Bigarray.int8_unsigned Bigarray.c_layout length
      in
      framebuffer.downsampled_pixels <- Some pixels;
      pixels

let downsample_framebuffer_pixels framebuffer ~factor ~width ~height =
  let pixels = acquire_downsampled_pixels framebuffer (width * height * 4) in
  let sample_count = float_of_int (factor * factor) in
  let transparent = rgba Color.transparent in
  for y = 0 to height - 1 do
    for x = 0 to width - 1 do
      let alpha = ref 0. and red = ref 0.
      and green = ref 0. and blue = ref 0. in
      for sample_y = 0 to factor - 1 do
        for sample_x = 0 to factor - 1 do
          let source_x = (x * factor) + sample_x
          and source_y = (y * factor) + sample_y in
          let index = (source_y * framebuffer.width) + source_x in
          match framebuffer.transparent.(index) with
          | [] ->
              if Bytes.get framebuffer.opaque_set index <> '\000' then begin
                let sample_alpha = clamp framebuffer.opaque_alpha.(index) in
                alpha := !alpha +. sample_alpha;
                red := !red +. (framebuffer.opaque_red.(index) *. sample_alpha);
                green :=
                  !green +. (framebuffer.opaque_green.(index) *. sample_alpha);
                blue :=
                  !blue +. (framebuffer.opaque_blue.(index) *. sample_alpha)
              end
          | fragments ->
              let opaque_depth = framebuffer.depths.(index) in
              let destination =
                if Bytes.get framebuffer.opaque_set index = '\000'
                then transparent
                else {
                  red = framebuffer.opaque_red.(index);
                  green = framebuffer.opaque_green.(index);
                  blue = framebuffer.opaque_blue.(index);
                  alpha = framebuffer.opaque_alpha.(index);
                }
              in
              let color =
                List.filter
                  (fun (depth, comparison, _, _) ->
                    compare_float comparison depth opaque_depth)
                  fragments
                |> List.sort
                     (fun (left, _, _, _) (right, _, _, _) ->
                       Float.compare right left)
                |> List.fold_left
                     (fun destination (_, _, mode, source) ->
                       blend source destination mode)
                     destination
              in
              let sample_alpha = clamp color.alpha in
              alpha := !alpha +. sample_alpha;
              red := !red +. (color.red *. sample_alpha);
              green := !green +. (color.green *. sample_alpha);
              blue := !blue +. (color.blue *. sample_alpha)
        done
      done;
      let output_alpha = !alpha /. sample_count in
      if !alpha <= 1e-12 then
        write_color pixels ((y * width) + x) 0. 0. 0. 0.
      else
        write_color pixels ((y * width) + x)
          (!red /. !alpha) (!green /. !alpha) (!blue /. !alpha) output_alpha
    done
  done;
  pixels

let downsample_colors framebuffer colors ~factor ~width ~height =
  if factor = 1 then colors
  else
    let output = Array.make (width * height) (rgba Color.transparent) in
    let sample_count = float_of_int (factor * factor) in
    for y = 0 to height - 1 do
      for x = 0 to width - 1 do
        let alpha = ref 0. and red = ref 0.
        and green = ref 0. and blue = ref 0. in
        for sample_y = 0 to factor - 1 do
          for sample_x = 0 to factor - 1 do
            let source_x = (x * factor) + sample_x
            and source_y = (y * factor) + sample_y in
            let color =
              colors.((source_y * framebuffer.width) + source_x)
            in
            let sample_alpha = clamp color.alpha in
            alpha := !alpha +. sample_alpha;
            red := !red +. (color.red *. sample_alpha);
            green := !green +. (color.green *. sample_alpha);
            blue := !blue +. (color.blue *. sample_alpha)
          done
        done;
        let output_alpha = !alpha /. sample_count in
        let color =
          if !alpha <= 1e-12 then rgba Color.transparent
          else {
            red = !red /. !alpha;
            green = !green /. !alpha;
            blue = !blue /. !alpha;
            alpha = output_alpha;
          }
        in
        output.((y * width) + x) <- color
      done
    done;
    output

let pack_colors colors =
  let pixels =
    Bigarray.Array1.create Bigarray.int8_unsigned Bigarray.c_layout
      (Array.length colors * 4)
  in
  Array.iteri
    (fun index color ->
      write_color pixels index color.red color.green color.blue color.alpha)
    colors;
  pixels

let downsample_attachments framebuffer ~factor ~width ~height =
  if factor = 1 then
    Array.copy framebuffer.depths, Array.copy framebuffer.stencils
  else
    let depths = Array.make (width * height) 1.
    and stencils = Array.make (width * height) 0 in
    for y = 0 to height - 1 do
      for x = 0 to width - 1 do
        let depth = ref infinity and stencil = ref 0 in
        for sample_y = 0 to factor - 1 do
          for sample_x = 0 to factor - 1 do
            let source_x = (x * factor) + sample_x
            and source_y = (y * factor) + sample_y in
            let index = (source_y * framebuffer.width) + source_x in
            depth := Float.min !depth framebuffer.depths.(index);
            stencil := !stencil lor framebuffer.stencils.(index)
          done
        done;
        let index = (y * width) + x in
        depths.(index) <- !depth;
        stencils.(index) <- !stencil
      done
    done;
    depths, stencils

let sample_texture ?(lod = 0.) texture tex_coord color =
  match texture with
  | None -> color
  | Some texture ->
      let sampled =
        let packed = Texture.Private.sample_lod_packed
          ~filter:texture.Scene3.filter
          ~wrap_u:texture.wrap_u ~wrap_v:texture.wrap_v
          texture.value ~lod ~u:tex_coord.Vec2.x ~v:tex_coord.y
        in
        {
          red = float_of_int ((packed lsr 24) land 0xff) /. 255.;
          green = float_of_int ((packed lsr 16) land 0xff) /. 255.;
          blue = float_of_int ((packed lsr 8) land 0xff) /. 255.;
          alpha = float_of_int (packed land 0xff) /. 255.;
        }
      in
      multiply color sampled

let shadow_visibility shadows light world normal =
  let rec visit visibility = function
    | [] -> visibility
    | shadow :: rest ->
        let visibility =
          if Shadow3.Private.affects shadow light then
            Float.min visibility
              (Shadow3.Private.visibility shadow ~world ~normal)
          else visibility
        in
        visit visibility rest
  in
  visit 1. shadows

let fixed_color ?(lod = 0.) texture ~separate_specular ~lights ~shadows
    ~world ~normal tex_coord indirect direct specular =
  if Array.length direct = 0 && Array.length specular = 0 then
    sample_texture ~lod texture tex_coord indirect
  else begin
  if Array.length direct <> Array.length lights
     || Array.length specular <> Array.length lights then
    invalid_arg "Renderer3d: lighting payload does not match active lights";
  let direct_red = ref 0. and direct_green = ref 0. and direct_blue = ref 0.
  and specular_red = ref 0. and specular_green = ref 0.
  and specular_blue = ref 0. in
  Array.iteri
    (fun index light ->
      let visibility = shadow_visibility shadows light world normal in
      direct_red := !direct_red +. (direct.(index).red *. visibility);
      direct_green := !direct_green +. (direct.(index).green *. visibility);
      direct_blue := !direct_blue +. (direct.(index).blue *. visibility);
      specular_red := !specular_red +. (specular.(index).red *. visibility);
      specular_green := !specular_green +. (specular.(index).green *. visibility);
      specular_blue := !specular_blue +. (specular.(index).blue *. visibility))
    lights;
  let primary = {
    red = indirect.red +. !direct_red;
    green = indirect.green +. !direct_green;
    blue = indirect.blue +. !direct_blue;
    alpha = indirect.alpha;
  } in
  if separate_specular then
    let sampled = sample_texture ~lod texture tex_coord primary in
    {
      red = sampled.red +. !specular_red;
      green = sampled.green +. !specular_green;
      blue = sampled.blue +. !specular_blue;
      alpha = sampled.alpha;
    }
  else
    sample_texture ~lod texture tex_coord {
      red = primary.red +. !specular_red;
      green = primary.green +. !specular_green;
      blue = primary.blue +. !specular_blue;
      alpha = primary.alpha;
    }
  end

let apply_fog fog camera world color =
  match fog with
  | None -> color
  | Some fog ->
      let visibility =
        Fog3.Private.visibility fog
          ~distance:(Vec3.distance (Camera.position camera) world)
      in
      let fog_color = rgba fog.Fog3.color in
      let mix source target =
        (source *. visibility) +. (target *. (1. -. visibility))
      in
      {
        red = mix color.red fog_color.red;
        green = mix color.green fog_color.green;
        blue = mix color.blue fog_color.blue;
        alpha = color.alpha;
      }

let run_fragment shader ~camera ~fog ~front_facing ~x ~y ~depth
    ~world ~normal ~tex_coord ~varyings color =
  let color = apply_fog fog camera world color in
  match shader with
  | None -> Some (depth, color)
  | Some shader ->
      let input : Shader3.fragment_input = {
        screen_position = Vec2.create x y;
        depth;
        front_facing;
        world_position = world;
        world_normal = Vec3.normalize normal;
        color = color_of_rgba color;
        tex_coord;
        varyings = Array.to_list varyings;
        uniforms = Shader3.uniforms shader;
      } in
      Shader3.Private.fragment shader input
      |> Option.map (fun output ->
        Option.value ~default:depth output.Shader3.depth,
        rgba output.color)

let raster_triangle texture shader ~blend ~separate_specular
    ~camera ~fog ~lights ~shadows
    ~(depth_state : Scene3.depth_state)
    ~(stencil_state : Scene3.stencil_state)
    framebuffer ~front_facing a b c =
  let width = framebuffer.width and height = framebuffer.height in
  let area = edge a.x a.y b.x b.y c.x c.y in
  let inverse_area = 1. /. area in
  let wa_dx = (c.y -. b.y) *. inverse_area
  and wa_dy = (b.x -. c.x) *. inverse_area
  and wb_dx = (a.y -. c.y) *. inverse_area
  and wb_dy = (c.x -. a.x) *. inverse_area
  and wc_dx = (b.y -. a.y) *. inverse_area
  and wc_dy = (a.x -. b.x) *. inverse_area in
  let denominator_dx =
    (wa_dx *. a.inv_w) +. (wb_dx *. b.inv_w) +. (wc_dx *. c.inv_w)
  and denominator_dy =
    (wa_dy *. a.inv_w) +. (wb_dy *. b.inv_w) +. (wc_dy *. c.inv_w)
  and tex_u_numerator_dx =
    (wa_dx *. a.inv_w *. a.tex_coord.x)
    +. (wb_dx *. b.inv_w *. b.tex_coord.x)
    +. (wc_dx *. c.inv_w *. c.tex_coord.x)
  and tex_u_numerator_dy =
    (wa_dy *. a.inv_w *. a.tex_coord.x)
    +. (wb_dy *. b.inv_w *. b.tex_coord.x)
    +. (wc_dy *. c.inv_w *. c.tex_coord.x)
  and tex_v_numerator_dx =
    (wa_dx *. a.inv_w *. a.tex_coord.y)
    +. (wb_dx *. b.inv_w *. b.tex_coord.y)
    +. (wc_dx *. c.inv_w *. c.tex_coord.y)
  and tex_v_numerator_dy =
    (wa_dy *. a.inv_w *. a.tex_coord.y)
    +. (wb_dy *. b.inv_w *. b.tex_coord.y)
    +. (wc_dy *. c.inv_w *. c.tex_coord.y)
  in
  let fixed_fast_path =
    match texture, shader, fog, shadows with
    | None, None, None, [] ->
        `Solid (a.color, b.color, c.color,
          a.color = b.color && a.color = c.color)
    | Some texture, None, None, []
      when Array.length a.direct = 0 && Array.length a.specular = 0 ->
        `Textured (texture, a.color, b.color, c.color)
    | _ -> `General in
  let simple_depth_stencil =
    depth_state.Scene3.comparison = Less
    && stencil_state.Scene3.comparison = Always
    && stencil_state.on_stencil_fail = Keep
    && stencil_state.on_depth_fail = Keep
    && stencil_state.on_pass = Keep
  in
  let texture_coordinate =
    match texture with
    | None -> None
    | Some _ ->
        Some (fun px py ->
          let wa = edge b.x b.y c.x c.y px py /. area
          and wb = edge c.x c.y a.x a.y px py /. area
          and wc = edge a.x a.y b.x b.y px py /. area in
          let denominator =
            (wa *. a.inv_w) +. (wb *. b.inv_w) +. (wc *. c.inv_w)
          in
          let pwa, pwb, pwc =
            if abs_float denominator <= 1e-12 then wa, wb, wc
            else
              ( wa *. a.inv_w /. denominator,
                wb *. b.inv_w /. denominator,
                wc *. c.inv_w /. denominator )
          in
          interpolate_vec2 a.tex_coord b.tex_coord c.tex_coord pwa pwb pwc)
  in
  if abs_float area > 1e-9 then begin
    let min_x =
      max 0
        (int_of_float
           (Float.floor (Float.min a.x (Float.min b.x c.x))))
    and max_x =
      min (width - 1)
        (int_of_float
           (Float.ceil (Float.max a.x (Float.max b.x c.x))))
    and min_y =
      max 0
        (int_of_float
           (Float.floor (Float.min a.y (Float.min b.y c.y))))
    and max_y =
      min (height - 1)
        (int_of_float
           (Float.ceil (Float.max a.y (Float.max b.y c.y))))
    in
    let origin_x = float_of_int min_x +. 0.5
    and origin_y = float_of_int min_y +. 0.5 in
    let wa_origin =
      (((origin_x -. b.x) *. (c.y -. b.y))
       -. ((origin_y -. b.y) *. (c.x -. b.x))) *. inverse_area
    and wb_origin =
      (((origin_x -. c.x) *. (a.y -. c.y))
       -. ((origin_y -. c.y) *. (a.x -. c.x))) *. inverse_area
    and wc_origin =
      (((origin_x -. a.x) *. (b.y -. a.y))
       -. ((origin_y -. a.y) *. (b.x -. a.x))) *. inverse_area
    in
    for y = min_y to max_y do
      let row = float_of_int (y - min_y) in
      let wa_row = wa_origin +. (row *. wa_dy)
      and wb_row = wb_origin +. (row *. wb_dy)
      and wc_row = wc_origin +. (row *. wc_dy) in
      for x = min_x to max_x do
        let px = float_of_int x +. 0.5 and py = float_of_int y +. 0.5 in
        let column = float_of_int (x - min_x) in
        let wa = wa_row +. (column *. wa_dx)
        and wb = wb_row +. (column *. wb_dx)
        and wc = wc_row +. (column *. wc_dx) in
        if wa >= (-1e-9) && wb >= (-1e-9) && wc >= (-1e-9) then
          let depth = (a.depth *. wa) +. (b.depth *. wb) +. (c.depth *. wc) in
          let denominator =
            (wa *. a.inv_w) +. (wb *. b.inv_w) +. (wc *. c.inv_w)
          in
          let affine = abs_float denominator <= 1e-12 in
          let pwa = if affine then wa else wa *. a.inv_w /. denominator
          and pwb = if affine then wb else wb *. b.inv_w /. denominator
          and pwc = if affine then wc else wc *. c.inv_w /. denominator in
          match fixed_fast_path with
          | `Solid (color_a, color_b, color_c, constant_color) ->
              let alpha =
                if constant_color then color_a.alpha
                else
                  (color_a.alpha *. pwa) +. (color_b.alpha *. pwb)
                  +. (color_c.alpha *. pwc)
              in
              if simple_depth_stencil
                 && (blend = Scene3.Replace
                     || (blend = Scene3.Alpha && alpha >= 0.999))
                 && Float.is_finite depth && depth >= 0. && depth <= 1.
              then begin
                let index = (y * width) + x in
                if depth < framebuffer.depths.(index) then begin
                  if depth_state.Scene3.write then
                    framebuffer.depths.(index) <- depth;
                  framebuffer.opaque_red.(index) <-
                    (if constant_color then color_a.red
                     else
                       (color_a.red *. pwa) +. (color_b.red *. pwb)
                       +. (color_c.red *. pwc));
                  framebuffer.opaque_green.(index) <-
                    (if constant_color then color_a.green
                     else
                       (color_a.green *. pwa) +. (color_b.green *. pwb)
                       +. (color_c.green *. pwc));
                  framebuffer.opaque_blue.(index) <-
                    (if constant_color then color_a.blue
                     else
                       (color_a.blue *. pwa) +. (color_b.blue *. pwb)
                       +. (color_c.blue *. pwc));
                  framebuffer.opaque_alpha.(index) <-
                    (if blend = Scene3.Alpha then 1. else clamp alpha);
                  Bytes.set framebuffer.opaque_set index '\001'
                end
              end else begin
                let index = test_pixel_index framebuffer
                    ~depth_state ~stencil_state x y depth in
                if index >= 0 then
                  commit_pixel_components framebuffer index
                    ~depth_state ~stencil_state ~blend depth
                    (if constant_color then color_a.red
                     else
                       (color_a.red *. pwa) +. (color_b.red *. pwb)
                       +. (color_c.red *. pwc))
                    (if constant_color then color_a.green
                     else
                       (color_a.green *. pwa) +. (color_b.green *. pwb)
                       +. (color_c.green *. pwc))
                    (if constant_color then color_a.blue
                     else
                       (color_a.blue *. pwa) +. (color_b.blue *. pwb)
                       +. (color_c.blue *. pwc))
                    alpha
              end
          | `Textured (texture, color_a, color_b, color_c) ->
              let tex_u =
                (a.tex_coord.x *. pwa) +. (b.tex_coord.x *. pwb)
                +. (c.tex_coord.x *. pwc)
              and tex_v =
                (a.tex_coord.y *. pwa) +. (b.tex_coord.y *. pwb)
                +. (c.tex_coord.y *. pwc)
              in
              let tex_u_numerator =
                (wa *. a.inv_w *. a.tex_coord.x)
                +. (wb *. b.inv_w *. b.tex_coord.x)
                +. (wc *. c.inv_w *. c.tex_coord.x)
              and tex_v_numerator =
                (wa *. a.inv_w *. a.tex_coord.y)
                +. (wb *. b.inv_w *. b.tex_coord.y)
                +. (wc *. c.inv_w *. c.tex_coord.y)
              in
              let horizontal_denominator = denominator +. denominator_dx
              and vertical_denominator = denominator +. denominator_dy in
              let horizontal_u =
                if abs_float horizontal_denominator <= 1e-12 then
                  tex_u
                  +. (a.tex_coord.x *. wa_dx)
                  +. (b.tex_coord.x *. wb_dx)
                  +. (c.tex_coord.x *. wc_dx)
                else
                  (tex_u_numerator +. tex_u_numerator_dx)
                  /. horizontal_denominator
              and horizontal_v =
                if abs_float horizontal_denominator <= 1e-12 then
                  tex_v
                  +. (a.tex_coord.y *. wa_dx)
                  +. (b.tex_coord.y *. wb_dx)
                  +. (c.tex_coord.y *. wc_dx)
                else
                  (tex_v_numerator +. tex_v_numerator_dx)
                  /. horizontal_denominator
              and vertical_u =
                if abs_float vertical_denominator <= 1e-12 then
                  tex_u
                  +. (a.tex_coord.x *. wa_dy)
                  +. (b.tex_coord.x *. wb_dy)
                  +. (c.tex_coord.x *. wc_dy)
                else
                  (tex_u_numerator +. tex_u_numerator_dy)
                  /. vertical_denominator
              and vertical_v =
                if abs_float vertical_denominator <= 1e-12 then
                  tex_v
                  +. (a.tex_coord.y *. wa_dy)
                  +. (b.tex_coord.y *. wb_dy)
                  +. (c.tex_coord.y *. wc_dy)
                else
                  (tex_v_numerator +. tex_v_numerator_dy)
                  /. vertical_denominator
              in
              let texture_width =
                float_of_int (Texture.width texture.Scene3.value)
              and texture_height = float_of_int (Texture.height texture.value) in
              let horizontal_du = (horizontal_u -. tex_u) *. texture_width
              and horizontal_dv = (horizontal_v -. tex_v) *. texture_height
              and vertical_du = (vertical_u -. tex_u) *. texture_width
              and vertical_dv = (vertical_v -. tex_v) *. texture_height in
              let horizontal_footprint = sqrt
                  ((horizontal_du *. horizontal_du)
                   +. (horizontal_dv *. horizontal_dv))
              and vertical_footprint = sqrt
                  ((vertical_du *. vertical_du)
                   +. (vertical_dv *. vertical_dv)) in
              let rho = Float.max horizontal_footprint vertical_footprint in
              let lod = if rho <= 1. then 0. else log rho /. log 2. in
              let sampled =
                Texture.Private.sample_lod_packed
                  ~filter:texture.Scene3.filter ~wrap_u:texture.wrap_u
                  ~wrap_v:texture.wrap_v texture.value ~lod ~u:tex_u ~v:tex_v
              in
              let red =
                ((color_a.red *. pwa) +. (color_b.red *. pwb)
                 +. (color_c.red *. pwc))
                *. (float_of_int ((sampled lsr 24) land 0xff) /. 255.)
              and green =
                ((color_a.green *. pwa) +. (color_b.green *. pwb)
                 +. (color_c.green *. pwc))
                *. (float_of_int ((sampled lsr 16) land 0xff) /. 255.)
              and blue =
                ((color_a.blue *. pwa) +. (color_b.blue *. pwb)
                 +. (color_c.blue *. pwc))
                *. (float_of_int ((sampled lsr 8) land 0xff) /. 255.)
              and alpha =
                ((color_a.alpha *. pwa) +. (color_b.alpha *. pwb)
                 +. (color_c.alpha *. pwc))
                *. (float_of_int (sampled land 0xff) /. 255.)
              in
              if simple_depth_stencil
                 && (blend = Scene3.Replace
                     || (blend = Scene3.Alpha && alpha >= 0.999))
                 && Float.is_finite depth && depth >= 0. && depth <= 1.
              then begin
                let index = (y * width) + x in
                if depth < framebuffer.depths.(index) then begin
                  if depth_state.Scene3.write then
                    framebuffer.depths.(index) <- depth;
                  framebuffer.opaque_red.(index) <- red;
                  framebuffer.opaque_green.(index) <- green;
                  framebuffer.opaque_blue.(index) <- blue;
                  framebuffer.opaque_alpha.(index) <-
                    (if blend = Scene3.Alpha then 1. else clamp alpha);
                  Bytes.set framebuffer.opaque_set index '\001'
                end
              end else begin
                let index = test_pixel_index framebuffer
                    ~depth_state ~stencil_state x y depth in
                if index >= 0 then
                  commit_pixel_components framebuffer index
                    ~depth_state ~stencil_state ~blend depth red green blue alpha
              end
          | `General ->
              let color =
                interpolate_color a.color b.color c.color pwa pwb pwc
              and direct =
                interpolate_color_arrays a.direct b.direct c.direct pwa pwb pwc
              and specular =
                interpolate_color_arrays
                  a.specular b.specular c.specular pwa pwb pwc
              in
              let world = interpolate_vec3 a.world b.world c.world pwa pwb pwc
              and normal =
                interpolate_vec3 a.normal b.normal c.normal pwa pwb pwc
              and tex_coord =
                interpolate_vec2 a.tex_coord b.tex_coord c.tex_coord pwa pwb pwc
              and varyings =
                interpolate_varyings a.varyings b.varyings c.varyings
                  pwa pwb pwc
              in
              let lod =
                match texture with
                | None -> 0.
                | Some texture ->
                    let texture_coordinate = Option.get texture_coordinate in
                    let horizontal = texture_coordinate (px +. 1.) py
                    and vertical = texture_coordinate px (py +. 1.) in
                    let width =
                      float_of_int (Texture.width texture.Scene3.value)
                    and height =
                      float_of_int (Texture.height texture.value)
                    in
                    let footprint target =
                      let du = (target.Vec2.x -. tex_coord.x) *. width
                      and dv = (target.y -. tex_coord.y) *. height in
                      sqrt ((du *. du) +. (dv *. dv))
                    in
                    let rho =
                      Float.max (footprint horizontal) (footprint vertical) in
                    if rho <= 1. then 0. else log rho /. log 2.
              in
              let color =
                fixed_color ~lod texture ~separate_specular ~lights ~shadows
                  ~world ~normal tex_coord color direct specular
              in
              Option.iter
                (fun (depth, color) ->
                  write_pixel framebuffer ~depth_state ~stencil_state ~blend
                    x y depth color)
                (run_fragment shader ~camera ~fog ~front_facing
                   ~x:px ~y:py ~depth ~world ~normal ~tex_coord ~varyings color)
      done
    done
  end

let raster_line texture shader ~line_width ~blend ~separate_specular
    ~camera ~fog ~lights ~shadows ~depth_state ~stencil_state
    framebuffer a b =
  let dx = b.x -. a.x and dy = b.y -. a.y in
  let length_sq = (dx *. dx) +. (dy *. dy) in
  let radius = Float.max 0.5 (line_width /. 2.) in
  let min_x = int_of_float (Float.floor (Float.min a.x b.x -. radius))
  and max_x = int_of_float (Float.ceil (Float.max a.x b.x +. radius))
  and min_y = int_of_float (Float.floor (Float.min a.y b.y -. radius))
  and max_y = int_of_float (Float.ceil (Float.max a.y b.y +. radius)) in
  for y = min_y to max_y do
    for x = min_x to max_x do
      let px = float_of_int x +. 0.5
      and py = float_of_int y +. 0.5 in
      let amount =
        if length_sq <= 1e-12 then 0.
        else
          (((px -. a.x) *. dx) +. ((py -. a.y) *. dy)) /. length_sq
          |> Float.max 0. |> Float.min 1.
      in
      let closest_x = a.x +. (dx *. amount)
      and closest_y = a.y +. (dy *. amount) in
      let distance_sq =
        ((px -. closest_x) *. (px -. closest_x))
        +. ((py -. closest_y) *. (py -. closest_y))
      in
      if distance_sq <= radius *. radius then begin
        let depth = a.depth +. ((b.depth -. a.depth) *. amount) in
        let left_weight = (1. -. amount) *. a.inv_w
        and right_weight = amount *. b.inv_w in
        let denominator = left_weight +. right_weight in
        let left_weight, right_weight =
          if abs_float denominator <= 1e-12 then 1. -. amount, amount
          else left_weight /. denominator, right_weight /. denominator
        in
        let color =
          interpolate_color a.color b.color b.color
            left_weight right_weight 0.
        and direct =
          interpolate_color_arrays a.direct b.direct b.direct
            left_weight right_weight 0.
        and specular =
          interpolate_color_arrays a.specular b.specular b.specular
            left_weight right_weight 0.
        in
        let world =
          interpolate_vec3 a.world b.world b.world
            left_weight right_weight 0.
        and normal =
          interpolate_vec3 a.normal b.normal b.normal
            left_weight right_weight 0.
        and tex_coord =
          interpolate_vec2 a.tex_coord b.tex_coord b.tex_coord
            left_weight right_weight 0.
        and varyings =
          interpolate_varyings a.varyings b.varyings b.varyings
            left_weight right_weight 0.
        in
        let color =
          fixed_color texture ~separate_specular ~lights ~shadows
            ~world ~normal tex_coord color direct specular
        in
        Option.iter
          (fun (depth, color) ->
            write_pixel framebuffer ~depth_state ~stencil_state ~blend
              x y depth color)
          (run_fragment shader ~camera ~fog ~front_facing:true
             ~x:px ~y:py ~depth ~world ~normal ~tex_coord ~varyings color)
      end
    done
  done

let raster_point texture shader ~point_size ~blend ~separate_specular
    ~camera ~fog ~lights ~shadows ~depth_state ~stencil_state
    framebuffer vertex =
  let center_x = int_of_float (Float.round vertex.x)
  and center_y = int_of_float (Float.round vertex.y)
  and diameter = max 1 (int_of_float (Float.ceil point_size)) in
  let first_x = center_x - ((diameter - 1) / 2)
  and first_y = center_y - ((diameter - 1) / 2) in
  for y = first_y to first_y + diameter - 1 do
    for x = first_x to first_x + diameter - 1 do
      let color =
        fixed_color texture ~separate_specular ~lights ~shadows
          ~world:vertex.world ~normal:vertex.normal vertex.tex_coord
          vertex.color vertex.direct vertex.specular
      in
      Option.iter
        (fun (depth, color) ->
          write_pixel framebuffer ~depth_state ~stencil_state ~blend
            x y depth color)
        (run_fragment shader ~camera ~fog ~front_facing:true
           ~x:(float_of_int x +. 0.5) ~y:(float_of_int y +. 0.5)
           ~depth:vertex.depth ~world:vertex.world ~normal:vertex.normal
           ~tex_coord:vertex.tex_coord ~varyings:vertex.varyings color)
    done
  done

type transforms = {
  position_transform : Mat4.t;
  normal_transform : Mat4.t;
}

let validate_shader_output shader (output : Shader3.vertex_output) =
  let expected_varyings =
    Option.fold ~none:0 ~some:Shader3.varying_count shader
  in
  if List.length output.Shader3.varyings <> expected_varyings then
    invalid_arg
      "Shader3 stage returned a varying count different from \
       Shader3.create ~varying_count"

let clip_of_shader_output ~lighting ~shader
    (output : Shader3.vertex_output) =
  validate_shader_output shader output;
  let clip_x, clip_y, clip_z, clip_w = output.Shader3.clip_position in
  let world = output.world_position
  and normal = Vec3.normalize output.world_normal in
  let shaded =
    shade lighting ~vertex_color:(rgba output.color) ~world ~normal
  in
  {
    clip_x;
    clip_y;
    clip_z;
    clip_w;
    world;
    normal;
    tex_coord = output.tex_coord;
    color = shaded.indirect;
    direct = shaded.direct;
    specular = shaded.specular;
    varyings = Array.of_list output.varyings;
  }

let transform_vertex ~lighting
    ~view ~projection ~model_view_projection ~transforms ~shader ~vertex_index
    ~vertex_color ~tex_coord position normal =
  let input : Shader3.vertex_input = {
    vertex_index;
    position;
    normal;
    color = vertex_color;
    tex_coord;
    model = transforms.position_transform;
    view;
    projection;
    model_view_projection;
    normal_matrix = transforms.normal_transform;
    uniforms =
      Option.fold ~none:Shader3.empty_uniforms
        ~some:Shader3.uniforms shader;
  } in
  let output =
    match shader with
    | None -> Shader3.default_vertex input
    | Some shader -> Shader3.Private.vertex shader input
  in
  output,
  clip_of_shader_output ~lighting ~shader output

let transform_fixed_vertex ~lighting
    ~collapse_lighting ~model_view_projection ~transforms
    ~vertex_color ~tex_coord
    position normal =
  let world = Mat4.transform_point transforms.position_transform position in
  let normal =
    Mat4.transform_direction transforms.normal_transform normal
    |> Vec3.normalize in
  let clip_x, clip_y, clip_z, clip_w =
    Mat4.transform model_view_projection
      (position.Vec3.x, position.y, position.z, 1.) in
  let shaded =
    shade ~collapse:collapse_lighting lighting
      ~vertex_color:(rgba vertex_color) ~world ~normal in
  {
    clip_x;
    clip_y;
    clip_z;
    clip_w;
    world;
    normal;
    tex_coord;
    color = shaded.indirect;
    direct = shaded.direct;
    specular = shaded.specular;
    varyings = [||];
  }

let project width height vertex =
  if vertex.clip_w <= 1e-12 then None
  else
    let inv_w = 1. /. vertex.clip_w in
    let ndc_x = vertex.clip_x *. inv_w
    and ndc_y = vertex.clip_y *. inv_w
    and ndc_z = vertex.clip_z *. inv_w in
    Some {
      x = (ndc_x +. 1.) *. 0.5 *. float_of_int width;
      y = (1. -. ndc_y) *. 0.5 *. float_of_int height;
      depth = (ndc_z +. 1.) *. 0.5;
      inv_w;
      world = vertex.world;
      normal = vertex.normal;
      tex_coord = vertex.tex_coord;
      color = vertex.color;
      direct = vertex.direct;
      specular = vertex.specular;
      varyings = vertex.varyings;
    }

let interpolate_vec3_pair left right amount =
  Vec3.lerp left right amount

let interpolate_clip left right amount =
  let mix a b = a +. ((b -. a) *. amount) in
  {
    clip_x = mix left.clip_x right.clip_x;
    clip_y = mix left.clip_y right.clip_y;
    clip_z = mix left.clip_z right.clip_z;
    clip_w = mix left.clip_w right.clip_w;
    world = interpolate_vec3_pair left.world right.world amount;
    normal =
      Vec3.normalize (interpolate_vec3_pair left.normal right.normal amount);
    tex_coord = Vec2.lerp left.tex_coord right.tex_coord amount;
    color =
      {
        red = mix left.color.red right.color.red;
        green = mix left.color.green right.color.green;
        blue = mix left.color.blue right.color.blue;
        alpha = mix left.color.alpha right.color.alpha;
      };
    direct =
      Array.init (Array.length left.direct) (fun index ->
        {
          red = mix left.direct.(index).red right.direct.(index).red;
          green = mix left.direct.(index).green right.direct.(index).green;
          blue = mix left.direct.(index).blue right.direct.(index).blue;
          alpha = 0.;
        });
    specular =
      Array.init (Array.length left.specular) (fun index ->
        {
          red = mix left.specular.(index).red right.specular.(index).red;
          green = mix left.specular.(index).green right.specular.(index).green;
          blue = mix left.specular.(index).blue right.specular.(index).blue;
          alpha = 0.;
        });
    varyings =
      Array.init (Array.length left.varyings) (fun index ->
        mix left.varyings.(index) right.varyings.(index));
  }

let clip_planes =
  [
    (fun vertex -> vertex.clip_x +. vertex.clip_w);
    (fun vertex -> vertex.clip_w -. vertex.clip_x);
    (fun vertex -> vertex.clip_y +. vertex.clip_w);
    (fun vertex -> vertex.clip_w -. vertex.clip_y);
    (fun vertex -> vertex.clip_z +. vertex.clip_w);
    (fun vertex -> vertex.clip_w -. vertex.clip_z);
  ]

let clip_against plane polygon =
  match polygon with
  | [] -> []
  | _ ->
      let previous = ref (List.hd (List.rev polygon)) in
      let previous_distance = ref (plane !previous) in
      let output = ref [] in
      List.iter
        (fun current ->
          let current_distance = plane current in
          let previous_inside = !previous_distance >= 0.
          and current_inside = current_distance >= 0. in
          if previous_inside <> current_inside then begin
            let denominator = !previous_distance -. current_distance in
            if abs_float denominator > 1e-12 then
              output :=
                interpolate_clip !previous current
                  (!previous_distance /. denominator)
                :: !output
          end;
          if current_inside then output := current :: !output;
          previous := current;
          previous_distance := current_distance)
        polygon;
      List.rev !output

let clip_polygon polygon =
  List.fold_left (fun polygon plane -> clip_against plane polygon)
    polygon clip_planes

let clip_line_segment left right =
  List.fold_left
    (fun segment plane ->
      match segment with
      | None -> None
      | Some (left, right) ->
          let left_distance = plane left
          and right_distance = plane right in
          if left_distance < 0. && right_distance < 0. then None
          else if left_distance >= 0. && right_distance >= 0. then
            Some (left, right)
          else
            let denominator = left_distance -. right_distance in
            if abs_float denominator <= 1e-12 then None
            else
              let crossing =
                interpolate_clip left right
                  (left_distance /. denominator)
              in
              if left_distance < 0. then Some (crossing, right)
              else Some (left, crossing))
    (Some (left, right)) clip_planes

let clip_point vertex =
  List.for_all (fun plane -> plane vertex >= 0.) clip_planes

let indexed_pairs mode indices =
  let count = Array.length indices in
  match mode with
  | Mesh.Lines ->
      List.init (count / 2) (fun pair ->
        indices.(pair * 2), indices.((pair * 2) + 1))
  | Line_strip ->
      List.init (max 0 (count - 1)) (fun index ->
        indices.(index), indices.(index + 1))
  | Line_loop when count > 1 ->
      List.init count (fun index ->
        indices.(index), indices.((index + 1) mod count))
  | Points | Triangles | Triangle_strip | Triangle_fan | Line_loop -> []

module Mesh_identity = struct
  type t = Mesh.t

  let equal left right = left == right
  let hash mesh =
    Hashtbl.hash
      (Mesh.mode mesh, Mesh.vertex_count mesh, Mesh.index_count mesh)
end

module Mesh_cache = Ephemeron.K1.Make (Mesh_identity)

type 'a bounded_mesh_cache = {
  table : 'a Mesh_cache.t;
  order : Mesh.t Weak.t Queue.t;
}

let mesh_cache_capacity = 256

let create_mesh_cache () = {
  table = Mesh_cache.create 32;
  order = Queue.create ();
}

let cache_mesh cache key value =
  Mesh_cache.replace cache.table key value;
  let weak = Weak.create 1 in
  Weak.set weak 0 (Some key);
  Queue.add weak cache.order;
  while Queue.length cache.order > mesh_cache_capacity do
    match Weak.get (Queue.take cache.order) 0 with
    | None -> ()
    | Some expired -> Mesh_cache.remove cache.table expired
  done

type prepared_mesh = {
  value : Mesh.t;
  view : Mesh.Private.packed_view;
  triangles : (int * int * int) array;
  pairs : (int * int) array;
}

let smooth_mesh_cache = create_mesh_cache ()
let flat_mesh_cache = create_mesh_cache ()

let prepare_mesh shading source =
  let cache, prepare =
    match shading with
    | Scene3.Smooth ->
        smooth_mesh_cache,
        (fun mesh ->
          if Mesh.has_normals mesh then mesh
          else Mesh.recalculate_normals mesh)
    | Flat -> flat_mesh_cache, Mesh.flat_shaded
  in
  match Mesh_cache.find_opt cache.table source with
  | Some prepared -> prepared
  | None ->
      let value = prepare source in
      let view = Mesh.Private.packed_view value in
      let prepared = {
        value;
        view;
        triangles = Mesh.Private.triangle_indices value;
        pairs =
          Array.of_list (indexed_pairs view.mode view.indices);
      } in
      cache_mesh cache source prepared;
      prepared

let render_drawing framebuffer ~camera ~ambient ~lights
    ~shadows ~fog ~separate_specular
    ~sample_factor ~view ~projection ~view_projection ~transform drawing =
  let width = framebuffer.width and height = framebuffer.height in
  let line_width =
    drawing.Scene3.Private.raster.line_width *. float_of_int sample_factor
  and point_size =
    drawing.Scene3.Private.raster.point_size *. float_of_int sample_factor
  in
  let prepared =
    prepare_mesh drawing.Scene3.Private.shading drawing.mesh
  in
  let mesh = prepared.view in
  let positions = mesh.vertices in
  let indices = mesh.indices in
  let mesh_colors = Option.value ~default:[||] mesh.colors in
  let mesh_tex_coords = Option.value ~default:[||] mesh.tex_coords in
  let normal_transform =
    Mat4.inverse transform
    |> Option.fold ~none:Mat4.identity ~some:Mat4.transpose
  in
  let transforms = {
    position_transform = transform;
    normal_transform;
  } in
  let model_view_projection =
    Mat4.mul view_projection transforms.position_transform in
  let lighting =
    prepare_lighting ~camera ~ambient ~lights ~material:drawing.material in
  let collapse_lighting =
    match drawing.texture, drawing.shader, fog, shadows with
    | None, None, None, [] -> true
    | Some _, None, None, [] when not separate_specular -> true
    | _ -> false
  in
  let default_normal = Vec3.unit_z in
  let position index =
    Vec3.create positions.x.(index) positions.y.(index) positions.z.(index)
  in
  let attributes index =
        let normal =
          match mesh.normals with
          | Some normals when index < Array.length normals.x ->
              Vec3.create normals.x.(index) normals.y.(index) normals.z.(index)
          | _ -> default_normal
        and vertex_color =
          if index < Array.length mesh_colors then mesh_colors.(index)
          else Color.white
        and tex_coord =
          if index < Array.length mesh_tex_coords then mesh_tex_coords.(index)
          else Vec2.zero
        in normal, vertex_color, tex_coord in
  let geometry = Option.bind drawing.shader Shader3.Private.geometry in
  let shader_vertices, transformed =
    match drawing.shader with
    | None ->
        [||],
        Array.init (Array.length positions.x) (fun index ->
          let position = position index in
          let normal, vertex_color, tex_coord = attributes index in
          transform_fixed_vertex ~lighting ~collapse_lighting
            ~model_view_projection ~transforms
            ~vertex_color ~tex_coord position normal)
    | Some _ ->
        let staged = Array.init (Array.length positions.x) (fun index ->
          let position = position index in
          let normal, vertex_color, tex_coord = attributes index in
          transform_vertex ~lighting ~view ~projection
            ~model_view_projection ~transforms ~shader:drawing.shader
            ~vertex_index:index ~vertex_color ~tex_coord position normal) in
        Array.map fst staged, Array.map snd staged in
  let projected =
    Array.map (fun vertex ->
      if clip_point vertex then project width height vertex else None)
      transformed in
  let clip_vertex index =
    if index < 0 || index >= Array.length transformed then None
    else Some transformed.(index)
  in
  let draw_clip_line left right =
    match clip_line_segment left right with
    | Some (left, right) ->
        (match project width height left, project width height right with
         | Some left, Some right ->
             raster_line drawing.texture drawing.shader
               ~line_width ~blend:drawing.blend
               ~separate_specular
               ~camera ~fog ~lights ~shadows
               ~depth_state:drawing.depth ~stencil_state:drawing.stencil
               framebuffer left right
         | _ -> ())
    | None -> ()
  in
  let draw_line left right =
    match clip_vertex left, clip_vertex right with
    | Some left, Some right -> draw_clip_line left right
    | _ -> ()
  in
  let draw_projected_point =
    raster_point drawing.texture drawing.shader
      ~point_size ~blend:drawing.blend
      ~separate_specular ~camera ~fog ~lights ~shadows
      ~depth_state:drawing.depth ~stencil_state:drawing.stencil framebuffer
  in
  let draw_clip_point value =
    if clip_point value then Option.iter draw_projected_point
        (project width height value)
  in
  let draw_point index =
    if index >= 0 && index < Array.length projected then
      Option.iter draw_projected_point projected.(index)
  in
  let draw_projected_triangle first second third =
    let signed_area =
      edge first.x first.y second.x second.y third.x third.y in
    let front = signed_area > 0. in
    let visible = match drawing.cull with
      | Scene3.Cull_none -> true
      | Cull_back -> front
      | Cull_front -> not front in
    if visible then match drawing.mode with
      | Scene3.Faces ->
          raster_triangle drawing.texture drawing.shader
            ~blend:drawing.blend ~separate_specular
            ~camera ~fog ~lights ~shadows
            ~depth_state:drawing.depth ~stencil_state:drawing.stencil
            framebuffer ~front_facing:front first second third
      | Wireframe ->
          let draw left right =
            raster_line drawing.texture drawing.shader
              ~line_width
              ~blend:drawing.blend ~separate_specular
              ~camera ~fog ~lights ~shadows
              ~depth_state:drawing.depth ~stencil_state:drawing.stencil
              framebuffer left right in
          draw first second;
          draw second third;
          draw third first
      | Vertices ->
          draw_projected_point first;
          draw_projected_point second;
          draw_projected_point third
  in
  let draw_clip_triangle a b c =
    let polygon = clip_polygon [a; b; c] in
    let polygon = List.filter_map (project width height) polygon in
    match polygon with
    | first :: second :: third :: rest ->
        let signed_area =
          edge first.x first.y second.x second.y third.x third.y
        in
        let front = signed_area > 0. in
        let visible =
          match drawing.cull with
          | Scene3.Cull_none -> true
          | Cull_back -> front
          | Cull_front -> not front
        in
        if visible then
          (match drawing.mode with
           | Scene3.Faces ->
               let rec fan = function
                 | left :: right :: rest ->
                     raster_triangle drawing.texture drawing.shader
                       ~blend:drawing.blend ~separate_specular
                       ~camera ~fog ~lights ~shadows
                       ~depth_state:drawing.depth
                       ~stencil_state:drawing.stencil framebuffer
                       ~front_facing:front first left right;
                     fan (right :: rest)
                 | _ -> ()
               in
               fan (second :: third :: rest)
           | Wireframe ->
               let rec edges = function
                 | left :: (right :: _ as rest) ->
                     raster_line drawing.texture drawing.shader
                       ~line_width
                       ~blend:drawing.blend ~separate_specular
                       ~camera ~fog ~lights ~shadows
                       ~depth_state:drawing.depth
                       ~stencil_state:drawing.stencil
                       framebuffer left right;
                     edges rest
                 | [last] ->
                     raster_line drawing.texture drawing.shader
                       ~line_width
                       ~blend:drawing.blend ~separate_specular
                       ~camera ~fog ~lights ~shadows
                       ~depth_state:drawing.depth
                       ~stencil_state:drawing.stencil
                       framebuffer last first
                 | [] -> ()
               in
               edges polygon
           | Vertices -> List.iter draw_clip_point [a; b; c])
    | _ -> ()
  in
  let draw_triangle (a, b, c) =
    match clip_vertex a, clip_vertex b, clip_vertex c with
    | Some clip_a, Some clip_b, Some clip_c ->
        (match projected.(a), projected.(b), projected.(c) with
         | Some a, Some b, Some c -> draw_projected_triangle a b c
         | _ -> draw_clip_triangle clip_a clip_b clip_c)
    | _ -> ()
  in
  let render_emitted = function
    | Shader3.Point vertex ->
        clip_of_shader_output ~lighting ~shader:drawing.shader vertex
        |> draw_clip_point
    | Line (left, right) ->
        let convert =
          clip_of_shader_output ~lighting ~shader:drawing.shader
        in
        draw_clip_line (convert left) (convert right)
    | Triangle (a, b, c) ->
        let convert =
          clip_of_shader_output ~lighting ~shader:drawing.shader
        in
        draw_clip_triangle (convert a) (convert b) (convert c)
  in
  let run_geometry primitive_index primitive geometry =
    geometry
      {
        Shader3.primitive_index;
        primitive;
        uniforms =
          Option.fold ~none:Shader3.empty_uniforms
            ~some:Shader3.uniforms drawing.shader;
      }
    |> List.iter render_emitted
  in
  match geometry with
  | Some geometry ->
      (match mesh.mode with
       | Mesh.Points ->
           Array.iteri
             (fun primitive_index index ->
               run_geometry primitive_index
                 (Shader3.Point shader_vertices.(index)) geometry)
             indices
       | Lines | Line_strip | Line_loop ->
           Array.iteri
             (fun primitive_index (left, right) ->
               run_geometry primitive_index
                 (Shader3.Line
                    (shader_vertices.(left), shader_vertices.(right)))
                 geometry)
             prepared.pairs
       | Triangles | Triangle_strip | Triangle_fan ->
           Array.iteri
             (fun primitive_index (a, b, c) ->
               run_geometry primitive_index
                 (Shader3.Triangle
                    ( shader_vertices.(a),
                      shader_vertices.(b),
                      shader_vertices.(c) ))
                 geometry)
             prepared.triangles)
  | None ->
      (match mesh.mode with
       | Mesh.Points -> Array.iter draw_point indices
       | Lines | Line_strip | Line_loop ->
           Array.iter (fun (a, b) -> draw_line a b) prepared.pairs
       | Triangles | Triangle_strip | Triangle_fan ->
           Array.iter draw_triangle prepared.triangles)

let renderer_size renderer =
  let logical_width, logical_height = Sdl.render_get_logical_size renderer in
  if logical_width > 0 && logical_height > 0 then
    logical_width, logical_height
  else
    match Sdl.get_renderer_output_size renderer with
    | Ok size -> size
    | Error (`Msg message) ->
        failwith ("3D renderer size query failed: " ^ message)

type rasterized = {
  width : int;
  height : int;
  colors : Color.t array;
  depths : float array;
  stencils : int array;
  pixels :
    (int, Bigarray.int8_unsigned_elt, Bigarray.c_layout) Bigarray.Array1.t;
}

type streaming_texture = {
  renderer : Sdl.renderer;
  width : int;
  height : int;
  texture : Sdl.texture;
}

let streaming_texture_cache : streaming_texture option ref = ref None

let release_renderer renderer =
  Renderer3d_gpu.release ();
  match !streaming_texture_cache with
  | Some cached when cached.renderer == renderer ->
      Sdl.destroy_texture cached.texture;
      streaming_texture_cache := None
  | _ -> ()

let acquire_streaming_texture renderer ~width ~height =
  match !streaming_texture_cache with
  | Some cached
    when cached.renderer == renderer
         && cached.width = width && cached.height = height ->
      Ok cached.texture
  | previous ->
      Option.iter (fun cached -> Sdl.destroy_texture cached.texture) previous;
      streaming_texture_cache := None;
      match
        Sdl.create_texture renderer Sdl.Pixel.format_rgba32
          Sdl.Texture.access_streaming ~w:width ~h:height
      with
      | Error _ as error -> error
      | Ok texture ->
          ignore (Sdl.set_texture_blend_mode texture Sdl.Blend.mode_blend);
          streaming_texture_cache :=
            Some { renderer; width; height; texture };
          Ok texture

let rasterize ?(attachments = true) ~width ~height ~camera scene =
  if width <= 0 || height <= 0 then
    invalid_arg "Renderer3d.rasterize: dimensions must be positive";
  let samples = Scene3.Private.samples scene in
  let factor = int_of_float (sqrt (float_of_int samples)) in
  let render_width = width * factor and render_height = height * factor in
  let framebuffer = acquire_framebuffer ~width:render_width ~height:render_height
      ~depth_clear:(Scene3.Private.depth_clear scene)
      ~stencil_clear:(Scene3.Private.stencil_clear scene) in
  let render_viewport = 0, 0, render_width, render_height in
  let view = Camera.view_matrix camera
  and projection = Camera.projection_matrix ~viewport:render_viewport camera in
  let view_projection = Mat4.mul projection view in
  let lights = Array.of_list (Scene3.Private.lights scene) in
  let render = render_drawing framebuffer ~camera
      ~ambient:(Scene3.Private.ambient scene)
      ~lights
      ~shadows:(Scene3.Private.shadows scene)
      ~fog:(Scene3.Private.fog scene)
      ~separate_specular:(Scene3.Private.separate_specular scene)
      ~sample_factor:factor
      ~view ~projection ~view_projection in
  Scene3.Private.iter_batches
    (fun drawing instances ->
      match instances with
      | None -> render ~transform:drawing.Scene3.Private.transform drawing
      | Some transforms ->
          Array.iter (fun transform ->
            render
              ~transform:(Mat4.mul drawing.Scene3.Private.transform transform)
              drawing) transforms)
    scene;
  let colors, pixels =
    if factor = 1 && not attachments then [||], pack_framebuffer framebuffer
    else if not attachments then
      [||], downsample_framebuffer_pixels framebuffer ~factor ~width ~height
    else
      let sample_colors = resolve framebuffer in
      let colors =
        downsample_colors framebuffer sample_colors ~factor ~width ~height
      in
      colors, pack_colors colors
  in
  let depths, stencils = if attachments then
      downsample_attachments framebuffer ~factor ~width ~height
    else [||], [||] in
  {
    width;
    height;
    colors = if attachments then Array.map color_of_rgba colors else [||];
    depths;
    stencils;
    pixels;
  }

let render_software ?viewport ~camera scene =
  let renderer = Graphics.get_renderer () in
  let renderer_width, renderer_height = renderer_size renderer in
  let viewport =
    match viewport with
    | None -> 0, 0, renderer_width, renderer_height
    | Some (x, y, width, height) ->
        if width <= 0 || height <= 0 then
          invalid_arg "Scene.view3d: viewport dimensions must be positive";
        x, y, width, height
  in
  let x, y, width, height = viewport in
  let output = rasterize ~attachments:false ~width ~height ~camera scene in
  match acquire_streaming_texture renderer ~width ~height with
  | Error (`Msg message) ->
      failwith ("3D texture creation failed: " ^ message)
  | Ok texture ->
      (match Sdl.update_texture texture None output.pixels (width * 4) with
       | Ok () -> ()
       | Error (`Msg message) ->
           failwith ("3D texture upload failed: " ^ message));
      let tx, ty = Graphics.transform_point (x, y) in
      let bx, by = Graphics.transform_point (x + width, y + height) in
      let destination =
        Sdl.Rect.create ~x:(min tx bx) ~y:(min ty by)
          ~w:(abs (bx - tx)) ~h:(abs (by - ty))
      in
      match Sdl.render_copy ~dst:destination renderer texture with
      | Ok () -> ()
      | Error (`Msg message) ->
          failwith ("3D texture draw failed: " ^ message)

let warned_gpu_fallback = ref false

let render ?viewport ~camera scene =
  if Backend.is_displayless () then render_software ?viewport ~camera scene
  else match Renderer3d_gpu.render ?viewport ~camera scene with
    | Ok () -> ()
    | Error message ->
        if not !warned_gpu_fallback then begin
          warned_gpu_fallback := true;
          Printf.eprintf
            "Prismel native GPU fallback: %s; using the software Scene3 reference for this unsupported scene\n%!"
            message
        end;
        render_software ?viewport ~camera scene

let composite_over background foreground =
  if foreground.Color.a = 255 then foreground
  else if foreground.a = 0 then background
  else
    let alpha = float_of_int foreground.a /. 255. in
    let channel foreground background =
      int_of_float ((float_of_int foreground *. alpha)
        +. (float_of_int background *. (1. -. alpha)) +. 0.5) in
    Color.rgba
      (channel foreground.r background.r)
      (channel foreground.g background.g)
      (channel foreground.b background.b) 255

let capture_software ~width ~height ~background ~camera scene =
  let output = rasterize ~attachments:true ~width ~height ~camera scene in
  Ok (Array.map (composite_over background) output.colors)

let capture ~width ~height ~background ~camera scene =
  if width <= 0 || height <= 0 then Error "3D capture dimensions must be positive"
  else if width > 16384 || height > 16384
      || Int64.mul (Int64.of_int width) (Int64.of_int height) > 100_000_000L
  then Error "3D capture exceeds the 16384-axis or 100-megapixel safety limit"
  else if Backend.is_displayless () then
    capture_software ~width ~height ~background ~camera scene
  else match Renderer3d_gpu.capture ~width ~height ~background ~camera scene with
    | Ok _ as output -> output
    | Error message ->
        Printf.eprintf
          "Prismel native GPU capture fallback: %s; using software\n%!" message;
        capture_software ~width ~height ~background ~camera scene

let present_gpu_if_pending = Renderer3d_gpu.present_if_pending
