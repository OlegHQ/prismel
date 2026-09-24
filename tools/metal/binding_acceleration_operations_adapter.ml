type state = Live | Destroyed

type ('buffer, 'function_handle, 'visible_table) t =
  { device : int64
  ; buffers : ('buffer * int64) option array
  ; functions : 'function_handle option array
  ; visible_tables : 'visible_table option array
  ; mutable state : state }

let create ~device ~capacity =
  if capacity <= 0 || capacity > 1_000_000 then
    invalid_arg "Metal function-table capacity must be between 1 and 1000000";
  { device; buffers = Array.make capacity None
  ; functions = Array.make capacity None
  ; visible_tables = Array.make capacity None; state = Live }

let validate_index value index =
  if value.state = Destroyed then Error "Metal function table is destroyed"
  else if index < 0 || index >= Array.length value.functions then
    Error "Metal function-table index is out of range"
  else Ok ()

let set_buffer ~buffer_device value ~index binding =
  match validate_index value index with
  | Error _ as error -> error
  | Ok () ->
      (match binding with
      | Some (_, offset) when offset < 0L ->
          Error "Metal function-table buffer offset is negative"
      | Some (buffer, _) when buffer_device buffer <> value.device ->
          Error "Metal function-table buffer belongs to another device"
      | _ -> value.buffers.(index) <- binding; Ok ())

let set_function value ~index function_handle =
  match validate_index value index with
  | Error _ as error -> error
  | Ok () -> value.functions.(index) <- function_handle; Ok ()

let set_visible_table ~table_device value ~index table =
  match validate_index value index with
  | Error _ as error -> error
  | Ok () ->
      (match table with
      | Some table when table_device table <> value.device ->
          Error "Metal visible function table belongs to another device"
      | _ -> value.visible_tables.(index) <- table; Ok ())

let destroy value =
  if value.state = Live then begin
    value.state <- Destroyed;
    Array.fill value.buffers 0 (Array.length value.buffers) None;
    Array.fill value.functions 0 (Array.length value.functions) None;
    Array.fill value.visible_tables 0 (Array.length value.visible_tables) None
  end

let retained_count value =
  let count values =
    Array.fold_left (fun total -> function None -> total | Some _ -> total + 1)
      0 values
  in
  count value.buffers + count value.functions + count value.visible_tables

let destroyed value = value.state = Destroyed
