let rotate_left value amount =
  Int32.logor (Int32.shift_left value amount)
    (Int32.shift_right_logical value (32 - amount))

let get_u32_be bytes offset =
  let byte index = Int32.of_int (Char.code (Bytes.unsafe_get bytes index)) in
  Int32.logor (Int32.shift_left (byte offset) 24)
    (Int32.logor (Int32.shift_left (byte (offset + 1)) 16)
       (Int32.logor (Int32.shift_left (byte (offset + 2)) 8)
          (byte (offset + 3))))

let set_u32_be bytes offset value =
  Bytes.unsafe_set bytes offset
    (Char.chr (Int32.to_int (Int32.shift_right_logical value 24) land 0xff));
  Bytes.unsafe_set bytes (offset + 1)
    (Char.chr (Int32.to_int (Int32.shift_right_logical value 16) land 0xff));
  Bytes.unsafe_set bytes (offset + 2)
    (Char.chr (Int32.to_int (Int32.shift_right_logical value 8) land 0xff));
  Bytes.unsafe_set bytes (offset + 3)
    (Char.chr (Int32.to_int value land 0xff))

let digest input =
  let input_length = String.length input in
  let padded_length = ((input_length + 9 + 63) / 64) * 64 in
  let bytes = Bytes.make padded_length '\000' in
  Bytes.blit_string input 0 bytes 0 input_length;
  Bytes.unsafe_set bytes input_length '\x80';
  let bit_length = Int64.mul (Int64.of_int input_length) 8L in
  for index = 0 to 7 do
    let shift = (7 - index) * 8 in
    Bytes.unsafe_set bytes (padded_length - 8 + index)
      (Char.chr
         (Int64.to_int (Int64.shift_right_logical bit_length shift) land 0xff))
  done;
  let h0 = ref 0x67452301l and h1 = ref 0xefcdab89l
  and h2 = ref 0x98badcfel and h3 = ref 0x10325476l
  and h4 = ref 0xc3d2e1f0l in
  let words = Array.make 80 0l in
  for block = 0 to (padded_length / 64) - 1 do
    let offset = block * 64 in
    for index = 0 to 15 do
      words.(index) <- get_u32_be bytes (offset + (index * 4))
    done;
    for index = 16 to 79 do
      words.(index) <-
        rotate_left
          (Int32.logxor words.(index - 3)
             (Int32.logxor words.(index - 8)
                (Int32.logxor words.(index - 14) words.(index - 16))))
          1
    done;
    let a = ref !h0 and b = ref !h1 and c = ref !h2
    and d = ref !h3 and e = ref !h4 in
    for index = 0 to 79 do
      let f, k =
        if index < 20 then
          (Int32.logor (Int32.logand !b !c)
             (Int32.logand (Int32.lognot !b) !d)),
          0x5a827999l
        else if index < 40 then
          Int32.logxor !b (Int32.logxor !c !d), 0x6ed9eba1l
        else if index < 60 then
          (Int32.logor (Int32.logand !b !c)
             (Int32.logor (Int32.logand !b !d) (Int32.logand !c !d))),
          0x8f1bbcdcl
        else
          Int32.logxor !b (Int32.logxor !c !d), 0xca62c1d6l
      in
      let temporary =
        Int32.add (rotate_left !a 5)
          (Int32.add f (Int32.add !e (Int32.add k words.(index))))
      in
      e := !d;
      d := !c;
      c := rotate_left !b 30;
      b := !a;
      a := temporary
    done;
    h0 := Int32.add !h0 !a;
    h1 := Int32.add !h1 !b;
    h2 := Int32.add !h2 !c;
    h3 := Int32.add !h3 !d;
    h4 := Int32.add !h4 !e
  done;
  let output = Bytes.create 20 in
  Array.iteri (fun index value -> set_u32_be output (index * 4) value)
    [|!h0; !h1; !h2; !h3; !h4|];
  output
