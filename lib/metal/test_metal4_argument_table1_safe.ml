open Metal

let get = function
  | Ok value -> value
  | Error error -> failwith (Format.asprintf "%a" pp_error error)

let reject kind = function
  | Error error when error.kind = kind -> ()
  | Error error -> failwith (Format.asprintf "%a" pp_error error)
  | Ok _ -> failwith "expected Metal4 argument-table resource rejection"

let () =
  match Device.system_default () with
  | Error _ -> print_endline "MTL4ArgumentTable1 safe: skipped"
  | Ok device ->
      match Command4.Argument_table.create ~max_buffers:1 device () with
      | Error error when error.kind = Unsupported || error.kind = Native_error ->
          ignore (Device.destroy device);
          print_endline "MTL4ArgumentTable1 safe: skipped (Metal4 unavailable)"
      | Error error -> failwith (Format.asprintf "%a" pp_error error)
      | Ok table ->
          let descriptor =
            Texture.descriptor_2d ~storage:Buffer.Private
              ~usage:[ Texture.Shader_read ] ~format:Texture.Rgba8_unorm
              ~width:4 ~height:4 ()
          in
          let first = get (Texture.create ~device descriptor) in
          let second = get (Texture.create ~device descriptor) in
          reject Invalid_argument
            (Metal4_argument_table_resource.set table ~buffer_index:1
               (Texture first));
          get
            (Metal4_argument_table_resource.set table ~buffer_index:0
               (Texture first));
          reject Parent_has_dependents (Texture.destroy first);
          get
            (Metal4_argument_table_resource.set table ~buffer_index:0
               (Texture second));
          get (Texture.destroy first);
          reject Parent_has_dependents (Texture.destroy second);
          let allocator = get (Command4.Allocator.create device) in
          let commands = get (Command4.Command_buffer.create allocator ()) in
          let encoder = get (Command4.Compute_encoder.create commands) in
          get (Command4.Compute_encoder.set_argument_table encoder (Some table));
          reject Parent_has_dependents (Command4.Argument_table.destroy table);
          get (Command4.Compute_encoder.end_encoding encoder);
          get (Command4.Command_buffer.end_recording commands);
          get (Command4.Command_buffer.destroy commands);
          get (Command4.Argument_table.destroy table);
          get (Texture.destroy second);
          get (Command4.Allocator.reset allocator);
          get (Command4.Allocator.destroy allocator);
          get (Device.destroy device);
          print_endline
            "MTL4ArgumentTable1 safe: exact1 texture ID/retention/index passed"
