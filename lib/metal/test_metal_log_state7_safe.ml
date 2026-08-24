open Metal

let get = function
  | Ok value -> value
  | Error error -> failwith (Format.asprintf "%a" pp_error error)

let expect_kind kind = function
  | Error error when error.kind = kind -> ()
  | Error error ->
      failwith (Format.asprintf "unexpected rejection: %a" pp_error error)
  | Ok _ -> failwith "expected LogState rejection"

let () =
  match Device.system_default () with
  | Error _ -> print_endline "metal LogState safe: skipped (no Metal device)"
  | Ok device ->
      match Command4.Log_state.Descriptor.create ~level:Notice ~buffer_size:4096L () with
      | Error error when error.kind = Unsupported || error.kind = Native_error ->
          get (Device.destroy device);
          print_endline "metal LogState safe: skipped (LogState unavailable)"
      | Error error -> failwith (Format.asprintf "%a" pp_error error)
      | Ok descriptor ->
          if Command4.Log_state.Descriptor.level descriptor <> Notice
             || Command4.Log_state.Descriptor.buffer_size descriptor <> 4096L
          then failwith "LogState descriptor snapshot changed";
          expect_kind Invalid_argument
            (Command4.Log_state.Descriptor.set descriptor ~level:Fault
               ~buffer_size:0L);
          get (Command4.Log_state.Descriptor.set descriptor ~level:Debug
                 ~buffer_size:8192L);
          let state = get (Command4.Log_state.create_with_descriptor device descriptor) in
          let deliveries = Atomic.make 0 in
          let handler =
            get (Command4.Log_state.add_handler state (fun _message ->
              Atomic.incr deliveries))
          in
          if Command4.Log_state.Handler.cancelled handler then
            failwith "fresh LogState handler is cancelled";
          get (Command4.Log_state.Handler.cancel handler);
          if not (Command4.Log_state.Handler.cancelled handler) then
            failwith "cancelled LogState handler stayed active";
          expect_kind Invalid_state (Command4.Log_state.Handler.cancel handler);
          get (Command4.Log_state.Handler.destroy handler);
          get (Command4.Log_state.destroy state);
          get (Command4.Log_state.Descriptor.destroy descriptor);
          get (Device.destroy device);
          ignore (Atomic.get deliveries);
          print_endline "metal LogState safe: ok"
