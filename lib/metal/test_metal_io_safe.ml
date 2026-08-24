open Metal

let fail_error error =
  failwith (Format.asprintf "%a" pp_error error)

let get = function Ok value -> value | Error error -> fail_error error

let expect_kind kind = function
  | Error error when error.kind = kind -> ()
  | Error error ->
      failwith (Format.asprintf "expected another rejection, got %a" pp_error error)
  | Ok _ -> failwith "expected rejection"

let destroy get_result value = ignore (get (get_result value))

let exercise_scratch device =
  match IO.Scratch_allocator.create device with
  | Error error when error.kind = Unsupported || error.kind = Native_error -> ()
  | Error error -> fail_error error
  | Ok allocator ->
      expect_kind Invalid_argument
        (IO.Scratch_allocator.allocate allocator ~minimum_size:0L);
      let scratch =
        get (IO.Scratch_allocator.allocate allocator ~minimum_size:256L)
      in
      let buffer = IO.Scratch_buffer.buffer scratch in
      if Buffer.length buffer < 256L || not (Device.same device (Buffer.device buffer))
      then failwith "IO scratch buffer changed its checked device or size";
      expect_kind Parent_has_dependents (IO.Scratch_allocator.destroy allocator);
      let queue = get (IO.Scratch_allocator.create_queue allocator) in
      expect_kind Parent_has_dependents (IO.Scratch_allocator.destroy allocator);
      destroy IO.Queue.destroy queue;
      destroy IO.Scratch_buffer.destroy scratch;
      destroy Buffer.destroy buffer;
      destroy IO.Scratch_allocator.destroy allocator

let exercise device path expected =
  let queue = get (Device.new_io_queue device ~label:"safe-io" ()) in
  if get (IO.Queue.label queue) <> Some "safe-io" then
    failwith "IO queue label did not round-trip";
  expect_kind Invalid_argument (IO.Queue.set_label queue (Some "bad\000label"));
  get (IO.Queue.set_label queue (Some "safe-io-updated"));
  if get (IO.Queue.label queue) <> Some "safe-io-updated" then
    failwith "updated IO queue label did not round-trip";
  get (IO.Queue.enqueue_barrier queue);
  let unretained = get (IO.Queue.create_unretained_command_buffer queue) in
  destroy IO.Command_buffer.destroy unretained;
  let source = get (Device.open_io_file device ~label:"safe-source" path) in
  if get (IO.File.label source) <> Some "safe-source" then
    failwith "IO file label did not round-trip";
  expect_kind Invalid_argument (IO.File.set_label source (Some "bad\000label"));
  get (IO.File.set_label source (Some "safe-source-updated"));
  let destination =
    get (Buffer.create ~device ~length:(Int64.of_int (Bytes.length expected))
           ~storage:Buffer.Shared ())
  in
  let status_destination =
    get (Buffer.create ~device ~length:8L ~storage:Buffer.Shared ())
  in
  let commands = get (IO.Queue.create_command_buffer queue ()) in
  let completed = Atomic.make false in
  let loaded_bytes = Atomic.make None in
  get (IO.Command_buffer.add_completed_handler commands
         (fun () -> Atomic.set completed true));
  get (IO.Command_buffer.load_bytes commands
         ~size:(Int64.of_int (Bytes.length expected)) ~source ~source_offset:0L
         ~on_complete:(function
           | Ok bytes -> Atomic.set loaded_bytes (Some bytes)
           | Error message -> failwith message));
  get (IO.Command_buffer.set_label commands (Some "safe-command"));
  if get (IO.Command_buffer.label commands) <> Some "safe-command" then
    failwith "IO command label did not round-trip";
  expect_kind Invalid_argument
    (IO.Command_buffer.push_debug_group commands "bad\000label");
  get (IO.Command_buffer.push_debug_group commands "safe-load");
  get (IO.Command_buffer.pop_debug_group commands);
  get (IO.Command_buffer.add_barrier commands);
  expect_kind Invalid_argument
    (IO.Command_buffer.copy_status commands ~destination:status_destination
       ~offset:(-1L));
  get (IO.Command_buffer.copy_status commands ~destination:status_destination
         ~offset:0L);
  expect_kind Invalid_argument
    (IO.Command_buffer.load_buffer commands ~destination
       ~destination_offset:(-1L) ~size:1L ~source ~source_offset:0L);
  expect_kind Invalid_argument
    (IO.Command_buffer.load_buffer commands ~destination
       ~destination_offset:0L
       ~size:(Int64.succ (Int64.of_int (Bytes.length expected)))
       ~source ~source_offset:0L);
  get (IO.Command_buffer.load_buffer commands ~destination
         ~destination_offset:0L ~size:(Int64.of_int (Bytes.length expected))
         ~source ~source_offset:0L);
  expect_kind Parent_has_dependents (Buffer.destroy destination);
  expect_kind Parent_has_dependents (IO.File.destroy source);
  (match get (IO.Command_buffer.commit_and_wait commands) with
   | IO.Command_buffer.Complete -> ()
   | IO.Command_buffer.Recording | IO.Command_buffer.Submitted
   | IO.Command_buffer.Failed -> failwith "IO command did not complete");
  if not (Atomic.get completed) then
    failwith "IO completion handler did not run exactly before wait returned";
  if Atomic.get loaded_bytes <> Some expected then
    failwith "IO pinned byte load changed file bytes";
  expect_kind Invalid_state
    (IO.Command_buffer.load_buffer commands ~destination
       ~destination_offset:0L ~size:0L ~source ~source_offset:0L);
  expect_kind Invalid_state
    (IO.Command_buffer.set_label commands (Some "too-late"));
  expect_kind Invalid_state (IO.Command_buffer.commit_and_wait commands);
  let actual = get (Buffer.read_bytes destination ~offset:0L
                      ~length:(Bytes.length expected)) in
  if actual <> expected then failwith "IO load changed file bytes";
  destroy IO.Command_buffer.destroy commands;
  destroy IO.File.destroy source;
  destroy Buffer.destroy destination;
  destroy Buffer.destroy status_destination;
  destroy IO.Queue.destroy queue

let () =
  let path = Filename.temp_file "prismel-metal-io-" ".bin" in
  Fun.protect ~finally:(fun () -> try Sys.remove path with Sys_error _ -> ())
    (fun () ->
      let expected = Bytes.init 64 (fun index -> Char.chr ((index * 37) land 255)) in
      let channel = open_out_bin path in
      Fun.protect ~finally:(fun () -> close_out_noerr channel)
        (fun () -> output_bytes channel expected);
      match Device.system_default () with
      | Error _ -> print_endline "metal io safe: skipped (no Metal device)"
      | Ok device ->
          (match Device.new_io_queue device () with
           | Error error when error.kind = Unsupported || error.kind = Native_error ->
               ignore (Device.destroy device);
               print_endline "metal io safe: skipped (Metal IO unavailable)"
           | Error error -> fail_error error
           | Ok probe ->
               get (IO.Queue.destroy probe);
               exercise_scratch device;
               exercise device path expected;
               get (Device.destroy device);
               print_endline "metal io safe: ok"))
