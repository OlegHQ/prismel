open Metal

let get = function
  | Ok value -> value
  | Error error -> failwith (Format.asprintf "%a" pp_error error)

let expect kind = function
  | Error error when error.kind = kind -> ()
  | Error error -> failwith (Format.asprintf "unexpected error: %a" pp_error error)
  | Ok _ -> failwith "expected indirect-command rejection"

let () =
  match Device.system_default () with
  | Error _ -> print_endline "indirect-command-buffer4 safe: skipped"
  | Ok device ->
      let descriptor =
        Indirect_command_buffer.descriptor
          ~command_types:[Indirect_command_buffer.Indirect_draw] ()
      in
      let commands =
        get (Indirect_command_buffer.create ~device ~max_command_count:2 descriptor)
      in
      let identifier = get (Indirect_command_buffer.gpu_resource_id commands) in
      if identifier = 0L then failwith "Metal returned an empty ICB resource ID";
      expect Invalid_argument
        (Indirect_command_buffer.Render_command.at commands 2);
      let first = get (Indirect_command_buffer.Render_command.at commands 0) in
      let second = get (Indirect_command_buffer.Render_command.at commands 1) in
      get (Indirect_command_buffer.Render_command.reset first);
      get (Indirect_command_buffer.Render_command.reset second);
      expect Parent_has_dependents (Indirect_command_buffer.destroy commands);
      get (Indirect_command_buffer.Render_command.destroy first);
      get (Indirect_command_buffer.Render_command.destroy second);
      get (Indirect_command_buffer.destroy commands);
      expect Destroyed (Indirect_command_buffer.gpu_resource_id commands);
      get (Device.destroy device);
      print_endline "indirect-command-buffer4 safe: indexed ownership/resource ID ok"
