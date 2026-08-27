type t = { width : int; height : int; pitch : int; bytes : bytes }

type error =
  | Invalid_size of { width : int; height : int }
  | Invalid_pitch of { minimum : int; actual : int }
  | Storage_too_small of { required : int; actual : int }
  | Coordinate_out_of_bounds of { x : int; y : int }

let checked_layout ~width ~height ~pitch =
  if width < 0 || height < 0 then Error (Invalid_size { width; height })
  else if width > max_int / 4 then Error (Invalid_size { width; height })
  else
    let minimum = width * 4 in
    if pitch < minimum then Error (Invalid_pitch { minimum; actual = pitch })
    else if height <> 0 && pitch > max_int / height then
      Error (Invalid_size { width; height })
    else Ok (pitch * height)

let create ?pitch ~width ~height () =
  let pitch = Option.value pitch ~default:(if width > max_int / 4 then 0 else width * 4) in
  match checked_layout ~width ~height ~pitch with
  | Error _ as error -> error
  | Ok length -> Ok { width; height; pitch; bytes = Bytes.make length '\000' }

let of_bytes ~width ~height ~pitch bytes =
  match checked_layout ~width ~height ~pitch with
  | Error _ as error -> error
  | Ok required when Bytes.length bytes < required ->
      Error (Storage_too_small { required; actual = Bytes.length bytes })
  | Ok _ -> Ok { width; height; pitch; bytes }

let width t = t.width
let height t = t.height
let pitch t = t.pitch
let bytes t = t.bytes

let offset t ~x ~y =
  if x < 0 || y < 0 || x >= t.width || y >= t.height then
    Error (Coordinate_out_of_bounds { x; y })
  else Ok ((y * t.pitch) + (x * 4))

let channel color shift =
  Int32.(to_int (logand (shift_right_logical color shift) 0xffl))

let clear t color =
  let r = Char.chr (channel color 24)
  and g = Char.chr (channel color 16)
  and b = Char.chr (channel color 8)
  and a = Char.chr (channel color 0) in
  for y = 0 to t.height - 1 do
    let row = y * t.pitch in
    for x = 0 to t.width - 1 do
      let i = row + (x * 4) in
      Bytes.set t.bytes i r;
      Bytes.set t.bytes (i + 1) g;
      Bytes.set t.bytes (i + 2) b;
      Bytes.set t.bytes (i + 3) a
    done
  done

let get_rgba t ~x ~y =
  match offset t ~x ~y with
  | Error _ as error -> error
  | Ok i ->
      let byte j = Int32.of_int (Char.code (Bytes.get t.bytes (i + j))) in
      Ok Int32.(logor (shift_left (byte 0) 24)
          (logor (shift_left (byte 1) 16)
             (logor (shift_left (byte 2) 8) (byte 3))))

let set_rgba t ~x ~y color =
  match offset t ~x ~y with
  | Error _ as error -> error
  | Ok i ->
      Bytes.set t.bytes i (Char.chr (channel color 24));
      Bytes.set t.bytes (i + 1) (Char.chr (channel color 16));
      Bytes.set t.bytes (i + 2) (Char.chr (channel color 8));
      Bytes.set t.bytes (i + 3) (Char.chr (channel color 0));
      Ok ()
