let fail text = failwith ("runtime-next web network: " ^ text)
let get = function Ok value -> value | Error error -> fail (Ogpu.Error.to_string error)

let write_all socket bytes =
  let rec loop offset = if offset < Bytes.length bytes then
    let count = Unix.single_write socket bytes offset (Bytes.length bytes - offset) in
    if count = 0 then raise End_of_file else loop (offset + count) in
  loop 0

let read_exact socket length =
  let bytes = Bytes.create length in
  let rec loop offset = if offset < length then
    let count = Unix.read socket bytes offset (length - offset) in
    if count = 0 then raise End_of_file else loop (offset + count) in
  loop 0; bytes

let read_until socket marker =
  let result = Buffer.create 512 and byte = Bytes.create 1 in
  let rec loop () =
    if Unix.read socket byte 0 1 = 0 then raise End_of_file;
    Buffer.add_char result (Bytes.get byte 0);
    let text = Buffer.contents result in
    if String.ends_with ~suffix:marker text then text else loop () in
  loop ()

let connect port =
  let socket = Unix.socket Unix.PF_INET Unix.SOCK_STREAM 0 in
  Unix.setsockopt_float socket Unix.SO_RCVTIMEO 3.;
  Unix.connect socket (Unix.ADDR_INET (Unix.inet_addr_loopback, port)); socket

let request socket port path headers =
  Printf.sprintf "GET %s HTTP/1.1\r\nHost: 127.0.0.1:%d\r\n%s\r\n" path port headers
  |> Bytes.of_string |> write_all socket

let find_between text prefix suffix =
  let rec loop index =
    if index + String.length prefix > String.length text then fail (prefix ^ " absent")
    else if String.sub text index (String.length prefix) = prefix then
      let first = index + String.length prefix in
      let last = String.index_from text first suffix in
      String.sub text first (last - first)
    else loop (index + 1) in loop 0

let websocket_payload socket =
  let header = read_exact socket 2 in
  let first = Char.code (Bytes.get header 0) and short = Char.code (Bytes.get header 1) land 0x7f in
  let length = if short < 126 then short else if short = 126 then
    let bytes = read_exact socket 2 in (Char.code (Bytes.get bytes 0) lsl 8) lor Char.code (Bytes.get bytes 1)
  else let bytes = read_exact socket 8 and value = ref 0 in
    for index = 0 to 7 do value := (!value lsl 8) lor Char.code (Bytes.get bytes index) done; !value in
  first land 0xf, first land 0x80 <> 0, read_exact socket length

let masked payload =
  if Bytes.length payload > 125 then invalid_arg "payload";
  let mask = Bytes.of_string "\x12\x34\x56\x78" in
  let result = Bytes.create (6 + Bytes.length payload) in
  Bytes.set result 0 (Char.chr 0x82); Bytes.set result 1 (Char.chr (0x80 lor Bytes.length payload));
  Bytes.blit mask 0 result 2 4;
  Bytes.iteri (fun index value -> Bytes.set result (6 + index)
    (Char.chr (Char.code value lxor Char.code (Bytes.get mask (index land 3))))) payload;
  result

let i32 bytes offset value = for index = 0 to 3 do
  Bytes.set bytes (offset + index) (Char.chr ((value lsr (8 * index)) land 255)) done

let event opcode values =
  let bytes = Bytes.make (2 + 4 * Array.length values) '\000' in
  Bytes.set bytes 0 '\001'; Bytes.set bytes 1 (Char.chr opcode);
  Array.iteri (fun index value -> i32 bytes (2 + index * 4) value) values; bytes

let text opcode value =
  let bytes = Bytes.create (2 + String.length value) in
  Bytes.set bytes 0 '\001'; Bytes.set bytes 1 (Char.chr opcode);
  Bytes.blit_string value 0 bytes 2 (String.length value); bytes

let upload name contents =
  let bytes = Bytes.create (4 + String.length name + String.length contents) in
  Bytes.set bytes 0 '\001'; Bytes.set bytes 1 '\011';
  Bytes.set bytes 2 (Char.chr (String.length name)); Bytes.set bytes 3 '\000';
  Bytes.blit_string name 0 bytes 4 (String.length name);
  Bytes.blit_string contents 0 bytes (4 + String.length name) (String.length contents); bytes

let open_browser port =
  let http = connect port in request http port "/" "";
  let page = read_until http "</html>" in Unix.close http;
  let token = find_between page "data-token=\"" '"' in
  let socket = connect port in
  request socket port ("/ws?token=" ^ token)
    "Upgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Version: 13\r\nSec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==\r\n";
  let response = read_until socket "\r\n\r\n" in
  if not (String.starts_with ~prefix:"HTTP/1.1 101" response) then fail "upgrade";
  token, socket

let mesh extent =
  let vertices = Bytes.make 48 '\000' in
  let set index x y = Bytes.set_int64_le vertices (index*16) (Int64.bits_of_float x);
    Bytes.set_int64_le vertices (index*16+8) (Int64.bits_of_float y) in
  set 0 0. 0.; set 1 (float extent) 0.; set 2 0. (float extent);
  let indices = Bytes.make 12 '\000' in Bytes.set_int32_le indices 4 1l; Bytes.set_int32_le indices 8 2l;
  {Scene_execution.key="network-"^string_of_int extent;vertices;vertex_count=3;indices;index_count=3}

let draw extent = {Scene_execution.mesh=mesh extent;
  state={viewport=(0,0,extent,extent);scissor=(0,0,extent,extent)}}

let wait_events runtime expected =
  let deadline = Unix.gettimeofday () +. 3. in
  let rec loop acc =
    let acc = acc @ Runtime_next_web.drain_events runtime in
    if List.length acc >= expected then acc else if Unix.gettimeofday () > deadline then fail "event timeout"
    else (Thread.delay 0.002; loop acc) in loop []

let () =
  let config={Wap.default_config with interface="127.0.0.1";port=0;max_events=64;
    max_clients=2;max_connections=4;max_queued_event_bytes=4096;max_frame_pool_bytes=4096;
    compress_frames=false} in
  let runtime=get(Runtime_next_web.create~wap_config:config~logical_width:4~logical_height:4
    ~drawable_width:4~drawable_height:4())in
  Fun.protect ~finally:(fun()->ignore(Runtime_next_web.destroy runtime))(fun()->
    let port=Runtime_next_web.port runtime in
    let token,slow=open_browser port in
    let unauthorized=connect port in request unauthorized port "/asset/missing?token=bad" "";
    let denied=read_until unauthorized "\r\n\r\n"in Unix.close unauthorized;
    if not(String.starts_with~prefix:"HTTP/1.1 404"denied)then fail"asset auth";
    let asset=match Runtime_next_web.register_bytes runtime~content_type:"text/plain"(Bytes.of_string"owned-upload")with Some x->x|None->fail"asset"in
    let fetch=connect port in request fetch port("/asset/"^asset^"?token="^token)"";
    let served=read_until fetch "owned-upload"in Unix.close fetch;
    if not(String.starts_with~prefix:"HTTP/1.1 200"served)then fail"asset delivery";
    let regions=[{Wap.x=1;y=1;width=2;height=2;focused=true}]in
    get(Runtime_next_web.set_text_input_regions runtime regions);
    let opcode,fin,command=websocket_payload slow in
    if opcode<>1||not fin||not(String.contains(Bytes.to_string command)'1')then fail"text focus wire";
    List.iter(fun frame->for _=1 to frame-(if frame=1 then 0 else 1)do
      ignore(get(Runtime_next_web.render runtime[draw 4]))done)[1;2;60;600];
    let stats=Runtime_next_web.stats runtime in
    if stats.frames_submitted<>660||stats.frames_suppressed<659 then fail"slow client bound";
    Unix.close slow;
    let _,socket=open_browser port in
    let payloads=[event 1[|3;5|];event 2[|1;3;5|];event 4[|0;1|];text 5"a";text 7"A";
      text 6"a";event 3[|1;3;5|];event 12[|1|];event 9[|8;6|];upload"browser.txt""upload";
      event 10[||]]@List.init 22(fun i->event 1[|i;i+1|])in
    List.iter(fun value->write_all socket(masked value))payloads;
    let observed=wait_events runtime 33 in
    if List.length observed<>33 then fail"33 event cardinality";
    (match List.nth observed 7 with Wap.Pointer_cancelled Left->()|_->fail"cancel distinct");
    (match List.nth observed 9 with Wap.File_uploaded{name="browser.txt";contents}
      when Bytes.to_string contents="upload"->()|_->fail"upload lifetime");
    get(Runtime_next_web.resize runtime~logical_width:8~logical_height:6~drawable_width:16~drawable_height:12);
    ignore(get(Runtime_next_web.render runtime[draw 12]));
    Runtime_next_web.remove_asset runtime asset;
    Unix.close socket;
    if Runtime_next_web.backend_trace_stats runtime|>fst>256 then fail"trace bound";
    let buffers,textures,pipelines,queues,surfaces=Runtime_next_web.backend_live_counts runtime in
    if (buffers,textures,pipelines,queues,surfaces)<>(2,1,6,1,1)then
      fail(Printf.sprintf"live bound %d,%d,%d,%d,%d"buffers textures pipelines queues surfaces));
  if Runtime_next_web.backend_live_counts runtime<>(0,0,0,0,0)then fail"teardown";
  print_endline"runtime-next web network: auth/frame/slow/33-event/reconnect passed"
