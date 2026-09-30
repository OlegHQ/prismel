type error =
  | Cook_error of Diagnostic.error
  | Prepare_error of string
  | Uncaught_exception of string

type status =
  | Idle
  | Cooking of {
      request_id : int;
      seconds : float;
      queued : bool;
    }

type 'a completion = {
  request_id : int;
  seconds : float;
  result : ('a, error) result;
}

type 'a request = {
  id : int;
  context : Context.t;
  nodes : Node.t list;
  prepare : Session.output list -> ('a, string) result;
}

type active = {
  started : float;
  cancel : Pdk.Cancel.t;
}

type 'a t = {
  session : Session.t;
  mutex : Mutex.t;
  ready : Condition.t;
  finished : Condition.t;  (* a request completed or the worker stopped *)
  mutable worker : unit Domain.t option;
  mutable pending : 'a request option;
  mutable active : active option;
  mutable completion : 'a completion option;
  mutable latest_id : int;
  mutable stopping : bool;
  mutable closed : bool;
}

let error_to_string = function
  | Cook_error error -> Diagnostic.error_to_string error
  | Prepare_error message -> message
  | Uncaught_exception cause -> "background cook raised: " ^ cause

let with_lock value operation =
  Mutex.lock value.mutex;
  Fun.protect ~finally:(fun () -> Mutex.unlock value.mutex) operation

let cancel_request request =
  Pdk.Cancel.cancel (Context.cancel_token request.context)

let execute session request =
  try
    let rec cook outputs = function
      | [] -> Ok (List.rev outputs)
      | node :: rest ->
          (match Session.cook session ~context:request.context node with
           | Error error -> Error (Cook_error error)
           | Ok output -> cook (output :: outputs) rest) in
    match cook [] request.nodes with
    | Error error -> Error error
    | Ok outputs ->
        (match request.prepare outputs with
         | Ok prepared -> Ok prepared
         | Error message -> Error (Prepare_error message))
  with exn -> Error (Uncaught_exception (Printexc.to_string exn))

let rec worker_loop value =
  let request = with_lock value (fun () ->
    while not value.stopping && Option.is_none value.pending do
      Condition.wait value.ready value.mutex
    done;
    if value.stopping then None
    else
      let request = Option.get value.pending in
      value.pending <- None;
      value.active <- Some {
        started = Unix.gettimeofday ();
        cancel = Context.cancel_token request.context;
      };
      Some request)
  in
  match request with
  | None -> ()
  | Some request ->
      let started = Unix.gettimeofday () in
      let result = execute value.session request in
      let seconds = max 0. (Unix.gettimeofday () -. started) in
      with_lock value (fun () ->
        value.active <- None;
        if not value.stopping && request.id = value.latest_id then
          value.completion <- Some {
            request_id = request.id;
            seconds;
            result;
          };
        Condition.broadcast value.finished);
      worker_loop value

let create ~max_entries ~max_payload_bytes =
  Result.map (fun session ->
    let value = {
      session;
      mutex = Mutex.create ();
      ready = Condition.create ();
      finished = Condition.create ();
      worker = None;
      pending = None;
      active = None;
      completion = None;
      latest_id = 0;
      stopping = false;
      closed = false;
    } in
    let worker = Domain.spawn (fun () ->
      Fun.protect
        ~finally:Prismel_math.Parallel.release_current_domain_pools
        (fun () -> worker_loop value)) in
    value.worker <- Some worker;
    value)
    (Session.create ~max_entries ~max_payload_bytes)

let submit_all value ~context ~nodes ~prepare =
  with_lock value (fun () ->
    if value.closed || value.stopping then
      Error "Async_cook.submit: worker is closed"
    else begin
      Option.iter cancel_request value.pending;
      Option.iter (fun active -> Pdk.Cancel.cancel active.cancel) value.active;
      value.latest_id <- value.latest_id + 1;
      let id = value.latest_id in
      value.pending <- Some { id; context; nodes; prepare };
      value.completion <- None;
      Condition.signal value.ready;
      Ok id
    end)

let submit value ~context ~node ~prepare =
  submit_all value ~context ~nodes:[node] ~prepare:(function
    | [output] -> prepare output
    | _ -> Error "Async_cook.submit: expected one output")

let set_volatile value predicate = Session.set_volatile value.session predicate

let stats value = Session.stats value.session

let await value = with_lock value (fun () ->
  if value.closed || value.stopping then invalid_arg "Async_cook.await: worker is closed";
  if Option.is_none value.completion && Option.is_none value.pending && Option.is_none value.active then
    invalid_arg "Async_cook.await: nothing was submitted";
  while Option.is_none value.completion && (Option.is_some value.pending || Option.is_some value.active) do
    Condition.wait value.finished value.mutex
  done;
  match value.completion with
  | Some completion -> value.completion <- None; completion
  | None -> invalid_arg "Async_cook.await: request was superseded")

let poll value = with_lock value (fun () ->
  let completion = value.completion in
  value.completion <- None;
  completion)

let status value = with_lock value (fun () ->
  match value.active, value.pending with
  | None, None -> Idle
  | Some active, pending -> Cooking {
      request_id = value.latest_id;
      seconds = max 0. (Unix.gettimeofday () -. active.started);
      queued = Option.is_some pending;
    }
  | None, Some pending -> Cooking {
      request_id = pending.id;
      seconds = 0.;
      queued = true;
    })

let close value =
  let worker = with_lock value (fun () ->
    if value.closed then None
    else begin
      value.closed <- true;
      value.stopping <- true;
      Option.iter cancel_request value.pending;
      Option.iter (fun active -> Pdk.Cancel.cancel active.cancel) value.active;
      value.pending <- None;
      value.completion <- None;
      Condition.broadcast value.ready;
      Condition.broadcast value.finished;
      value.worker
    end)
  in
  Option.iter (fun worker -> ignore (Domain.join worker)) worker;
  Option.iter (fun _ -> Session.close value.session) worker

let is_closed value = with_lock value (fun () -> value.closed)
