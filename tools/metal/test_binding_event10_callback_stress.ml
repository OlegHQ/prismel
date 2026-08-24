type state = Pending | Fired | Cancelled

type token =
  { mutable state : state
  ; mutable rooted : bool
  ; mutable calls : int
  }

let live_roots = ref 0
let live_tokens = ref 0

let create () =
  incr live_roots;
  incr live_tokens;
  { state = Pending; rooted = true; calls = 0 }

let release_root token =
  if token.rooted then begin
    token.rooted <- false;
    decr live_roots
  end

let fire token =
  match token.state with
  | Fired | Cancelled -> false
  | Pending ->
      token.state <- Fired;
      token.calls <- token.calls + 1;
      release_root token;
      true

let cancel token =
  match token.state with
  | Fired | Cancelled -> false
  | Pending ->
      token.state <- Cancelled;
      release_root token;
      true

let destroy_token token =
  ignore (cancel token);
  decr live_tokens

let () =
  Binding_event10_safe_closure.validate ();
  for index = 0 to 9_999 do
    let token = create () in
    if index land 1 = 0 then begin
      if not (fire token) || cancel token then failwith "fire/cancel arbitration";
      if fire token then failwith "notification fired twice"
    end else begin
      if not (cancel token) || fire token then failwith "cancel/fire arbitration";
      if cancel token then failwith "notification cancelled twice"
    end;
    if token.calls > 1 then failwith "callback invoked more than once";
    destroy_token token
  done;
  if !live_roots <> 0 || !live_tokens <> 0 then
    failwith "Event10 callback root/token leak";
  Printf.printf
    "Event10 exact closure and 10k fire-vs-cancel root/token stress passed\n%!"

