type resource = Buffer of Buffer.t | Texture of Texture.t
type t = { portable:Ogpu.Diagnostics.t }

let create device ~capacity =
  if capacity <= 0 then Error (Ogpu.Error.make "Ogpu_metal.Diagnostics.create" Ogpu.Error.Invalid_argument "capacity must be positive")
  else Result.map (fun portable->{portable})
    (Ogpu.Diagnostics.create ~device:(Device.Private.handle device) ~message_capacity:capacity
       ~trace_capacity:capacity ~max_label_length:256 ~max_message_length:4096)

let classify_metal_error ~operation value = Adapter.error ~operation value

let category = function
  | Ogpu.Error.Device_lost -> Ogpu.Diagnostics.Submission
  | Stale_handle | Cross_device -> Resource
  | Invalid_argument | Invalid_state | Unsupported | No_adapter | Capacity -> Validation

let add_error value ?label error =
  Ogpu.Diagnostics.add_message value.portable ~severity:Ogpu.Diagnostics.Error
    ~category:(category error.Ogpu.Error.kind) ?label error.message

let messages value = Ogpu.Diagnostics.messages value.portable
let dropped value = Ogpu.Diagnostics.dropped_messages value.portable

let add_field buffer key value =
  Stdlib.Buffer.add_string buffer key; Stdlib.Buffer.add_char buffer '=';
  Stdlib.Buffer.add_string buffer (string_of_int (String.length value)); Stdlib.Buffer.add_char buffer ':';
  Stdlib.Buffer.add_string buffer value; Stdlib.Buffer.add_char buffer '\n'

let int64 = Int64.to_string
let float value = Printf.sprintf "%.17g" value
let label = Option.value ~default:""

let resource_row device = function
  | Buffer value -> Result.map (fun (descriptor:Ogpu.Types.buffer_descriptor) ->
      (Buffer.id value, Printf.sprintf "buffer|%s|%s|%s"
        (int64 (Buffer.id value)) (int64 (Buffer.generation value)) (label descriptor.Ogpu.Types.label)))
      (Buffer.descriptor device value)
  | Texture value -> Result.map (fun (descriptor:Ogpu.Types.texture_descriptor) ->
      (Texture.id value, Printf.sprintf "texture|%s|%s|%s|%d|%d|%d|%d"
        (int64 (Texture.id value)) (int64 (Texture.generation value)) (label descriptor.Ogpu.Types.label)
        descriptor.width descriptor.height descriptor.mip_levels descriptor.sample_count))
      (Texture.descriptor device value)

let operation_row = function
  | Command.Private.Copy (source,source_offset,destination,destination_offset,length) ->
      Printf.sprintf "copy|%s|%s|%s|%s|%s" (int64(Buffer.id source)) (int64 source_offset)
        (int64(Buffer.id destination)) (int64 destination_offset) (int64 length)
  | Compute (source,entry,buffer,threads) ->
      Printf.sprintf "compute|%s|%s|%s|%d" (Digest.to_hex(Digest.string source)) entry (int64(Buffer.id buffer)) threads
  | Dispatch (pipeline,buffer,threads) ->
      Printf.sprintf "dispatch|%s|%s|%d" (Pipeline.key pipeline) (int64(Buffer.id buffer)) threads
  | Clear (texture,(r,g,b,a)) ->
      Printf.sprintf "clear|%s|%s|%s|%s|%s" (int64(Texture.id texture)) (float r) (float g) (float b) (float a)
  | Draw_triangle (pipeline,texture) ->
      Printf.sprintf "draw|%s|%s" (Pipeline.key pipeline) (int64(Texture.id texture))

let serialize_capture device ~label:capture_label ~resources ~commands =
  let operation="Ogpu_metal.Diagnostics.serialize_capture" in
  if capture_label="" || String.contains capture_label '\000' then
    Error(Ogpu.Error.make operation Ogpu.Error.Invalid_argument "capture label is invalid")
  else if List.exists (fun command ->
    let descriptions=Command.descriptions command in
    Array.length descriptions=0 || descriptions.(Array.length descriptions-1)<>Ogpu.Command.End_encoder) commands then
    Error(Ogpu.Error.make operation Ogpu.Error.Invalid_state "capture commands must be ended")
  else
    let rec gather acc = function
      | [] -> Ok acc
      | resource::rest -> (match resource_row device resource with Error _ as failure->failure|Ok row->gather(row::acc)rest)
    in
    match gather [] resources with Error _ as failure->failure|Ok rows->
    let rows=List.sort(fun(a,_)(b,_)->Int64.compare a b)rows in
    let rec unique = function []|[_]->true|(a,_)::((b,_)::_ as rest)->a<>b&&unique rest in
    if not(unique rows)then Error(Ogpu.Error.make operation Ogpu.Error.Invalid_argument "capture resources contain duplicate IDs")else
    let output=Stdlib.Buffer.create 1024 in add_field output "manifest" "ogpu-metal-v1";add_field output "label" capture_label;
    List.iter(fun(_,row)->add_field output "resource" row)rows;
    List.iteri(fun command_index command->
      List.iteri(fun operation_index operation->add_field output "command"
        (Printf.sprintf "%d|%d|%s"command_index operation_index(operation_row operation)))
        (Command.Private.operations command))commands;
    Ok(Stdlib.Buffer.contents output)

let capture_hash device ~label ~resources ~commands =
  Result.map (fun value->Digest.to_hex(Digest.string value))
    (serialize_capture device ~label ~resources ~commands)

let destroy value = Ogpu.Diagnostics.destroy value.portable
