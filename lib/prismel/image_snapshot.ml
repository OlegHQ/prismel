type snapshot = {
  id : int;
  generation : int64;
  width : int;
  height : int;
  rgba : bytes;
}

type entry = { key : Obj.t; mutable snapshot : snapshot }

let next_id = Atomic.make 1
let entries : entry list ref = ref []

let find key =
  List.find_opt (fun entry -> entry.key == key) !entries
  |> Option.map (fun entry -> entry.snapshot)

let register key ~width ~height rgba =
  let snapshot = {
    id = Atomic.fetch_and_add next_id 1;
    generation = 1L; width; height; rgba = Bytes.copy rgba;
  } in
  entries := { key; snapshot } ::
    List.filter (fun entry -> entry.key != key) !entries

let register_generation key ~generation ~width ~height rgba =
  let snapshot = {
    id = Atomic.fetch_and_add next_id 1;
    generation; width; height; rgba = Bytes.copy rgba;
  } in
  entries := { key; snapshot } ::
    List.filter (fun entry -> entry.key != key) !entries

let replace ~target ~replacement =
  match find replacement with
  | None -> ()
  | Some source ->
      let generation = match find target with
        | None -> 1L
        | Some previous -> Int64.succ previous.generation
      in
      let id = match find target with
        | None -> Atomic.fetch_and_add next_id 1
        | Some previous -> previous.id
      in
      let snapshot = { source with id; generation; rgba = Bytes.copy source.rgba } in
      entries := { key = target; snapshot } ::
        List.filter (fun entry -> entry.key != target && entry.key != replacement)
          !entries

let remove key =
  entries := List.filter (fun entry -> entry.key != key) !entries

let live_bytes () =
  List.fold_left (fun total entry -> total + Bytes.length entry.snapshot.rgba)
    0 !entries

let rgba_of_surface source =
  let open Tsdl in
  match Sdl.convert_surface_format source Sdl_compat.format_rgba32 with
  | Error (`Msg message) -> Error message
  | Ok surface ->
      Fun.protect ~finally:(fun () -> Sdl.free_surface surface) (fun () ->
        let width, height = Sdl.get_surface_size surface in
        match Sdl.lock_surface surface with
        | Error (`Msg message) -> Error message
        | Ok () -> Fun.protect ~finally:(fun () -> Sdl.unlock_surface surface)
            (fun () ->
              match Sdl.alloc_format Sdl_compat.format_rgba32 with
              | Error (`Msg message) -> Error message
              | Ok format -> Fun.protect ~finally:(fun () -> Sdl.free_format format)
                  (fun () ->
                    let values = Sdl.get_surface_pixels surface Bigarray.int32
                    and stride = Sdl.get_surface_pitch surface / 4 in
                    let rgba = Bytes.create (width * height * 4) in
                    for y = 0 to height - 1 do
                      for x = 0 to width - 1 do
                        let r, g, b, a = Sdl.get_rgba format values.{y * stride + x} in
                        let offset = (y * width + x) * 4 in
                        Bytes.set rgba offset (Char.chr r);
                        Bytes.set rgba (offset + 1) (Char.chr g);
                        Bytes.set rgba (offset + 2) (Char.chr b);
                        Bytes.set rgba (offset + 3) (Char.chr a)
                      done
                    done;
                    Ok (width, height, rgba))))
