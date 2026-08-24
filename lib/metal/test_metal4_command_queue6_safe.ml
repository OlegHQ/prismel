open Metal

let get = function
  | Ok value -> value
  | Error error -> failwith (Format.asprintf "%a" pp_error error)

let expect kind = function
  | Error error when error.kind = kind -> ()
  | Error error -> failwith (Format.asprintf "unexpected error: %a" pp_error error)
  | Ok _ -> failwith "expected Metal safe rejection"

let () =
  match Device.system_default () with
  | Error _ -> print_endline "MTL4CommandQueue6 safe: skipped"
  | Ok device ->
      match Command4.Queue.create ~label:"queue6" device with
      | Error _ ->
          ignore (Device.destroy device);
          print_endline "MTL4CommandQueue6 safe: skipped"
      | Ok queue ->
          if not (Device.same device (Command4.Queue.device queue)) then
            failwith "Metal4 queue device identity";
          if get (Command4.Queue.label queue) <> Some "queue6" then
            failwith "Metal4 queue label snapshot";
          let source = get (Buffer.create ~device ~length:64L ~storage:Buffer.Shared ()) in
          let destination = get (Buffer.create ~device ~length:64L ~storage:Buffer.Shared ()) in
          expect Invalid_argument
            (Command4.Queue.copy_buffer_mappings queue ~source ~destination []);
          let event = get (Device.new_event device) in
          get (Command4.Queue.wait_for_event queue (Command4.Queue.Event event) ~value:0L);
          expect Invalid_argument
            (Command4.Queue.wait_for_event queue (Command4.Queue.Event event) ~value:(-1L));
          expect Parent_has_dependents (Event.destroy event);
          get (Buffer.destroy source);
          get (Buffer.destroy destination);
          get (Command4.Queue.destroy queue);
          get (Event.destroy event);
          get (Device.destroy device);
          print_endline
            "MTL4CommandQueue6 safe: exact6 identity/state/device/retention passed"
