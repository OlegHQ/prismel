type opcode = Continuation | Text | Binary | Close | Ping | Pong

type frame = {
  fin : bool;
  opcode : opcode;
  payload : bytes;
}

let opcode_value = function
  | Continuation -> 0x0
  | Text -> 0x1
  | Binary -> 0x2
  | Close -> 0x8
  | Ping -> 0x9
  | Pong -> 0xa

let opcode_of_int = function
  | 0x0 -> Some Continuation
  | 0x1 -> Some Text
  | 0x2 -> Some Binary
  | 0x8 -> Some Close
  | 0x9 -> Some Ping
  | 0xa -> Some Pong
  | _ -> None

let base64 bytes =
  let alphabet =
    "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/" in
  let length = Bytes.length bytes in
  let output = Buffer.create (((length + 2) / 3) * 4) in
  let rec encode offset =
    if offset < length then begin
      let first = Char.code (Bytes.unsafe_get bytes offset) in
      let second =
        if offset + 1 < length then Char.code (Bytes.unsafe_get bytes (offset + 1))
        else 0 in
      let third =
        if offset + 2 < length then Char.code (Bytes.unsafe_get bytes (offset + 2))
        else 0 in
      Buffer.add_char output alphabet.[first lsr 2];
      Buffer.add_char output alphabet.[((first land 0x3) lsl 4) lor (second lsr 4)];
      Buffer.add_char output
        (if offset + 1 < length then
           alphabet.[((second land 0xf) lsl 2) lor (third lsr 6)]
         else '=');
      Buffer.add_char output
        (if offset + 2 < length then alphabet.[third land 0x3f] else '=');
      encode (offset + 3)
    end
  in
  encode 0;
  Buffer.contents output

let accept_key key =
  Sha1.digest (key ^ "258EAFA5-E914-47DA-95CA-C5AB0DC85B11") |> base64

let rec write_all descriptor bytes offset length =
  if length > 0 then
    let written = Unix.single_write descriptor bytes offset length in
    if written = 0 then raise End_of_file
    else write_all descriptor bytes (offset + written) (length - written)

let rec write_all_bigarray descriptor values offset length =
  if length > 0 then
    let written = Unix.single_write_bigarray descriptor values offset length in
    if written = 0 then raise End_of_file
    else write_all_bigarray descriptor values (offset + written) (length - written)

let frame_header ~fin ~opcode length =
  if length < 0 then invalid_arg "Websocket.frame_header: negative length";
  let prefix = (if fin then 0x80 else 0) lor opcode_value opcode in
  if length <= 125 then begin
    let output = Bytes.create 2 in
    Bytes.unsafe_set output 0 (Char.chr prefix);
    Bytes.unsafe_set output 1 (Char.chr length);
    output
  end else if length <= 0xffff then begin
    let output = Bytes.create 4 in
    Bytes.unsafe_set output 0 (Char.chr prefix);
    Bytes.unsafe_set output 1 (Char.chr 126);
    Bytes.unsafe_set output 2 (Char.chr (length lsr 8));
    Bytes.unsafe_set output 3 (Char.chr (length land 0xff));
    output
  end else begin
    let output = Bytes.make 10 '\000' in
    Bytes.unsafe_set output 0 (Char.chr prefix);
    Bytes.unsafe_set output 1 (Char.chr 127);
    let length = Int64.of_int length in
    for index = 0 to 7 do
      Bytes.unsafe_set output (index + 2)
        (Char.chr
           (Int64.to_int
              (Int64.shift_right_logical length ((7 - index) * 8)) land 0xff))
    done;
    output
  end

let write_bytes descriptor ~fin ~opcode payload =
  let header = frame_header ~fin ~opcode (Bytes.length payload) in
  write_all descriptor header 0 (Bytes.length header);
  write_all descriptor payload 0 (Bytes.length payload)

let write_bigarray descriptor ~fin ~opcode payload =
  let length = Bigarray.Array1.dim payload in
  let header = frame_header ~fin ~opcode length in
  write_all descriptor header 0 (Bytes.length header);
  write_all_bigarray descriptor payload 0 length

let rec read_exact descriptor bytes offset length =
  if length > 0 then
    let received = Unix.read descriptor bytes offset length in
    if received = 0 then raise End_of_file
    else read_exact descriptor bytes (offset + received) (length - received)

let read_u16 descriptor =
  let bytes = Bytes.create 2 in
  read_exact descriptor bytes 0 2;
  (Char.code (Bytes.unsafe_get bytes 0) lsl 8)
  lor Char.code (Bytes.unsafe_get bytes 1)

let read_u64 descriptor =
  let bytes = Bytes.create 8 in
  read_exact descriptor bytes 0 8;
  let value = ref 0L in
  for index = 0 to 7 do
    value := Int64.logor (Int64.shift_left !value 8)
      (Int64.of_int (Char.code (Bytes.unsafe_get bytes index)))
  done;
  !value

let read_frame ?(max_payload = 65_536) descriptor =
  let header = Bytes.create 2 in
  read_exact descriptor header 0 2;
  let first = Char.code (Bytes.unsafe_get header 0)
  and second = Char.code (Bytes.unsafe_get header 1) in
  if first land 0x70 <> 0 then invalid_arg "WebSocket reserved bits are set";
  let fin = first land 0x80 <> 0 in
  let opcode =
    match opcode_of_int (first land 0x0f) with
    | Some value -> value
    | None -> invalid_arg "WebSocket opcode is unsupported"
  in
  if second land 0x80 = 0 then
    invalid_arg "WebSocket client frame is not masked";
  let short_length = second land 0x7f in
  let payload_length =
    if short_length < 126 then Int64.of_int short_length
    else if short_length = 126 then Int64.of_int (read_u16 descriptor)
    else read_u64 descriptor
  in
  if payload_length < 0L || payload_length > Int64.of_int max_payload then
    invalid_arg "WebSocket client frame exceeds the configured limit";
  let is_control = match opcode with Close | Ping | Pong -> true | _ -> false in
  if is_control && (not fin || payload_length > 125L) then
    invalid_arg "Invalid fragmented or oversized WebSocket control frame";
  let mask = Bytes.create 4 in
  read_exact descriptor mask 0 4;
  let length = Int64.to_int payload_length in
  let payload = Bytes.create length in
  read_exact descriptor payload 0 length;
  for index = 0 to length - 1 do
    Bytes.unsafe_set payload index
      (Char.chr
         (Char.code (Bytes.unsafe_get payload index)
          lxor Char.code (Bytes.unsafe_get mask (index land 3))))
  done;
  { fin; opcode; payload }
