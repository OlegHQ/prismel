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

let exercise device path expected =
  let queue = get (Device.new_io_queue device ~label:"safe-io" ()) in
  let source = get (Device.open_io_file device ~label:"safe-source" path) in
  let destination =
    get (Buffer.create ~device ~length:(Int64.of_int (Bytes.length expected))
           ~storage:Buffer.Shared ())
  in
  let commands = get (IO.Queue.create_command_buffer queue ()) in
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
  expect_kind Invalid_state
    (IO.Command_buffer.load_buffer commands ~destination
       ~destination_offset:0L ~size:0L ~source ~source_offset:0L);
  expect_kind Invalid_state (IO.Command_buffer.commit_and_wait commands);
  let actual = get (Buffer.read_bytes destination ~offset:0L
                      ~length:(Bytes.length expected)) in
  if actual <> expected then failwith "IO load changed file bytes";
  destroy IO.Command_buffer.destroy commands;
  destroy IO.File.destroy source;
  destroy Buffer.destroy destination;
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
               exercise device path expected;
               get (Device.destroy device);
               print_endline "metal io safe: ok"))
