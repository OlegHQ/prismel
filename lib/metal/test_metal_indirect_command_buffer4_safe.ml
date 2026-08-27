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
          ~command_types:[Indirect_command_buffer.Indirect_draw]
          ~support_dynamic_attribute_stride:true
          ~max_vertex_buffer_bind_count:2 ~max_fragment_buffer_bind_count:1
          ~max_object_buffer_bind_count:1 ~max_mesh_buffer_bind_count:1 ()
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
      let buffer = get (Buffer.create ~device ~length:64L ~storage:Buffer.Shared ()) in
      get (Indirect_command_buffer.Render_command.set_object_buffer first
        ~index:0 ~offset:0L buffer);
      get (Indirect_command_buffer.Render_command.set_mesh_buffer first
        ~index:0 ~offset:0L buffer);
      get (Indirect_command_buffer.Render_command.set_vertex_buffer_stride first
        ~index:0 ~offset:0L ~stride:4L buffer);
      expect Invalid_argument
        (Indirect_command_buffer.Render_command.set_vertex_buffer_stride first
          ~index:2 ~offset:0L ~stride:4L buffer);
      get (Indirect_command_buffer.Render_command.draw_indexed first
        ~primitive:Indirect_command_buffer.Render_command.Triangle
        ~index_type:Indirect_command_buffer.Render_command.Uint16
        ~index_buffer:buffer ~index_offset:0L ~index_count:3L ());
      expect Invalid_argument
        (Indirect_command_buffer.Render_command.draw_indexed first
          ~primitive:Indirect_command_buffer.Render_command.Triangle
          ~index_type:Indirect_command_buffer.Render_command.Uint32
          ~index_buffer:buffer ~index_offset:2L ~index_count:3L ());
      get (Indirect_command_buffer.Render_command.reset first);
      get (Indirect_command_buffer.Render_command.reset second);
      expect Parent_has_dependents (Indirect_command_buffer.destroy commands);
      get (Indirect_command_buffer.Render_command.destroy first);
      get (Indirect_command_buffer.Render_command.destroy second);
      get (Indirect_command_buffer.destroy commands);
      get (Buffer.destroy buffer);
      expect Destroyed (Indirect_command_buffer.gpu_resource_id commands);
      get (Device.destroy device);
      print_endline "indirect-command-buffer4 safe: indexed ownership/resource ID ok"
