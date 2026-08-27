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
