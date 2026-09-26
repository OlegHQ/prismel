type kind = Rect | Textured | Wire | Grid

type xform = { scale : float; tx : float; ty : float }
let identity = { scale = 1.; tx = 0.; ty = 0. }

type clip = { x : float; y : float; width : float; height : float }

type batch = {
  first : int;
  count : int;
  clip : clip option;
  xform : xform;
  texture : int;
}

type t = { bytes : bytes; count : int; batches : batch array }

let instance_bytes = 64
let instances value = value.bytes
let count value = value.count
let batches value = value.batches
let empty = { bytes = Bytes.empty; count = 0; batches = [||] }

let textures value =
  Array.fold_left (fun ids batch ->
    if batch.texture > 0 && not (List.mem batch.texture ids)
    then batch.texture :: ids else ids) [] value.batches
  |> List.rev

let kind_code = function Rect -> 0l | Textured -> 1l | Wire -> 2l | Grid -> 3l

let float value ~instance ~word =
  Int32.float_of_bits
    (Bytes.get_int32_le value.bytes ((instance * instance_bytes) + (word * 4)))

module Builder = struct
  type batch_table = t

  type t = {
    mutable bytes : bytes;
    mutable length : int;
    mutable batches : batch list;
    mutable open_first : int;
    mutable open_texture : int;
    mutable clip : clip option;
    mutable xform : xform;
  }

  let create ?(capacity = 256) () =
    { bytes = Bytes.create (max 1 capacity * instance_bytes); length = 0;
      batches = []; open_first = 0; open_texture = 0; clip = None;
      xform = identity }

  let close builder =
    if builder.length > builder.open_first then
      builder.batches <- { first = builder.open_first;
        count = builder.length - builder.open_first; clip = builder.clip;
        xform = builder.xform; texture = builder.open_texture }
        :: builder.batches;
    builder.open_first <- builder.length;
    builder.open_texture <- 0

  let reset builder =
    builder.length <- 0; builder.batches <- []; builder.open_first <- 0;
    builder.open_texture <- 0; builder.clip <- None; builder.xform <- identity

  let set_clip builder clip =
    if clip <> builder.clip then begin close builder; builder.clip <- clip end

  let set_xform builder xform =
    if xform <> builder.xform then begin close builder; builder.xform <- xform end

  (* Untextured instances never split a batch; a second texture does. *)
  let use_texture builder texture =
    if builder.open_texture <> 0 && builder.open_texture <> texture then
      close builder;
    builder.open_texture <- texture

  let reserve builder =
    let needed = (builder.length + 1) * instance_bytes in
    if needed > Bytes.length builder.bytes then begin
      let grown = Bytes.create (max needed (2 * Bytes.length builder.bytes)) in
      Bytes.blit builder.bytes 0 grown 0 (builder.length * instance_bytes);
      builder.bytes <- grown
    end;
    let offset = builder.length * instance_bytes in
    Bytes.fill builder.bytes offset instance_bytes '\000';
    builder.length <- builder.length + 1;
    offset

  let set_float bytes offset word value =
    Bytes.set_int32_le bytes (offset + (word * 4)) (Int32.bits_of_float value)
  let set_word bytes offset word value =
    Bytes.set_int32_le bytes (offset + (word * 4)) value

  let quad builder offset x0 y0 x1 y1 =
    set_float builder.bytes offset 0 x0; set_float builder.bytes offset 1 y0;
    set_float builder.bytes offset 2 x1; set_float builder.bytes offset 3 y1

  let rect builder ~x ~y ~width ~height ?(color = 0l) ?(border_color = 0l)
      ?(border = 0.) ?(radius = 0.) ?(anti_alias = false) () =
    if width > 0. && height > 0. then begin
      let offset = reserve builder in
      quad builder offset x y (x +. width) (y +. height);
      set_word builder.bytes offset 8 color;
      set_word builder.bytes offset 9 border_color;
      set_word builder.bytes offset 10 (kind_code Rect);
      set_float builder.bytes offset 11 radius;
      set_float builder.bytes offset 12 border;
      set_float builder.bytes offset 13
        (if anti_alias || radius > 0. then 1. else 0.)
    end

  let textured builder ~texture ~x ~y ~width ~height ~u0 ~v0 ~u1 ~v1 ~color =
    if texture <= 0 then invalid_arg "Ui_batch.textured: texture must be positive";
    if width > 0. && height > 0. then begin
      use_texture builder texture;
      let offset = reserve builder in
      quad builder offset x y (x +. width) (y +. height);
      set_float builder.bytes offset 4 u0; set_float builder.bytes offset 5 v0;
      set_float builder.bytes offset 6 u1; set_float builder.bytes offset 7 v1;
      set_word builder.bytes offset 8 color;
      set_word builder.bytes offset 10 (kind_code Textured)
    end

  let wire builder (x0, y0) (x1, y1) (x2, y2) (x3, y3) ~width ~color =
    let distance ax ay bx by = Float.hypot (bx -. ax) (by -. ay) in
    let length = distance x0 y0 x1 y1 +. distance x1 y1 x2 y2
      +. distance x2 y2 x3 y3 in
    let segments = max 4 (min 48 (int_of_float (Float.ceil (length /. 16.)))) in
    let point t =
      let s = 1. -. t in
      let a = s *. s *. s and b = 3. *. s *. s *. t and c = 3. *. s *. t *. t
      and d = t *. t *. t in
      (a *. x0) +. (b *. x1) +. (c *. x2) +. (d *. x3),
      (a *. y0) +. (b *. y1) +. (c *. y2) +. (d *. y3) in
    (* Skip chords whose padded bounds miss the clip, in screen space. *)
    let visible (ax, ay) (bx, by) = match builder.clip with
      | None -> true
      | Some clip ->
          let xform = builder.xform in
          let pad = (width *. xform.scale) +. 2. in
          let sx value = (value *. xform.scale) +. xform.tx
          and sy value = (value *. xform.scale) +. xform.ty in
          Float.min (sx ax) (sx bx) -. pad <= clip.x +. clip.width
          && Float.max (sx ax) (sx bx) +. pad >= clip.x
          && Float.min (sy ay) (sy by) -. pad <= clip.y +. clip.height
          && Float.max (sy ay) (sy by) +. pad >= clip.y in
    for segment = 0 to segments - 1 do
      let t0 = float_of_int segment /. float_of_int segments
      and t1 = float_of_int (segment + 1) /. float_of_int segments in
      if visible (point t0) (point t1) then begin
      let offset = reserve builder in
      quad builder offset x0 y0 x1 y1;
      set_float builder.bytes offset 4 x2; set_float builder.bytes offset 5 y2;
      set_float builder.bytes offset 6 x3; set_float builder.bytes offset 7 y3;
      set_word builder.bytes offset 8 color;
      set_word builder.bytes offset 10 (kind_code Wire);
      set_float builder.bytes offset 12 width;
      set_float builder.bytes offset 14 t0;
      set_float builder.bytes offset 15 t1
      end
    done

  let grid builder ~x ~y ~width ~height ~origin_x ~origin_y ~spacing ~dot
      ~color =
    if width > 0. && height > 0. && spacing > 0. then begin
      let offset = reserve builder in
      quad builder offset x y (x +. width) (y +. height);
      set_float builder.bytes offset 4 origin_x;
      set_float builder.bytes offset 5 origin_y;
      set_float builder.bytes offset 6 spacing;
      set_float builder.bytes offset 7 dot;
      set_word builder.bytes offset 8 color;
      set_word builder.bytes offset 10 (kind_code Grid)
    end

  let publish builder =
    close builder;
    { bytes = Bytes.sub builder.bytes 0 (builder.length * instance_bytes);
      count = builder.length;
      batches = Array.of_list (List.rev builder.batches) }
end
