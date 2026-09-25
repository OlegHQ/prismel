module Make (K : Hashtbl.HashedType) = struct
  module Table = Hashtbl.Make (K)
  (* A circular ring: [oldest.older] is the newest entry. A hit only sets
     [touched] (one immediate store, no write barrier); eviction walks from
     the oldest and gives touched entries a second chance by moving them to
     the newest position, so the victim is still the least recently used
     untouched entry (CLOCK). *)
  type 'v node = { key : K.t; value : 'v; size : int; mutable touched : bool;
    mutable newer : 'v node; mutable older : 'v node }
  type 'v t = { capacity : int; byte_capacity : int;
    evictable : K.t -> 'v -> bool; release : K.t -> 'v -> unit;
    table : 'v node Table.t;
    (* [oldest] holds one node or nothing; mutating the cell instead of
       rebinding an option keeps every hit allocation-free. *)
    mutable oldest : 'v node array;
    mutable bytes : int }

  let create ?(byte_capacity = max_int) ?(evictable = fun _ _ -> true)
      ?(release = fun _ _ -> ()) capacity =
    { capacity; byte_capacity; evictable; release;
      table = Table.create (max 1 (min 1024 capacity)); oldest = [||]; bytes = 0 }

  let unlink t node =
    if node.newer == node then t.oldest <- [||]
    else begin
      node.older.newer <- node.newer; node.newer.older <- node.older;
      if t.oldest.(0) == node then t.oldest.(0) <- node.newer
    end

  let link_newest t node =
    if Array.length t.oldest = 0 then begin
      node.newer <- node; node.older <- node; t.oldest <- [| node |]
    end else begin
      let oldest = t.oldest.(0) in
      let newest = oldest.older in
      node.older <- newest; node.newer <- oldest;
      newest.newer <- node; oldest.older <- node
    end

  let move_newest t node =
    if t.oldest.(0).older != node then begin unlink t node; link_newest t node end

  let drop t node =
    unlink t node; Table.remove t.table node.key;
    t.bytes <- t.bytes - node.size; t.release node.key node.value

  let over t = Table.length t.table > t.capacity || t.bytes > t.byte_capacity

  (* One lap at most: a touched or pinned entry moves to newest and loses
     its touch; the first untouched evictable entry is the victim. *)
  let victim t =
    if Array.length t.oldest = 0 then None else
    let rec lap remaining node =
      if remaining = 0 then None
      else if node.touched || not (t.evictable node.key node.value) then begin
        let next = node.newer in
        node.touched <- false; move_newest t node;
        if next == node then None else lap (remaining - 1) next
      end else Some node in
    lap (Table.length t.table) t.oldest.(0)

  let rec evict t =
    if over t then match victim t with
      | None -> ()
      | Some node -> drop t node; evict t

  let find t key = let node = Table.find t.table key in node.touched <- true; node.value

  let find_opt t key = match Table.find_opt t.table key with
    | None -> None
    | Some node -> node.touched <- true; Some node.value

  let peek t key = match Table.find_opt t.table key with
    | None -> None
    | Some node -> Some node.value

  let add t ?(bytes = 0) key value =
    (match Table.find_opt t.table key with Some old -> drop t old | None -> ());
    let rec node = { key; value; size = bytes; touched = false; newer = node; older = node } in
    Table.replace t.table key node; link_newest t node;
    t.bytes <- t.bytes + bytes; evict t

  let remove t key = match Table.find_opt t.table key with
    | None -> () | Some node -> drop t node

  let take t key = match Table.find_opt t.table key with
    | None -> None
    | Some node ->
        unlink t node; Table.remove t.table node.key;
        t.bytes <- t.bytes - node.size; Some node.value

  let drop_oldest t = match victim t with
    | None -> false | Some node -> drop t node; true

  let find_first t f =
    if Array.length t.oldest = 0 then None else
    let oldest = t.oldest.(0) in
    let rec go node =
      if f node.key node.value then Some node.value
      else if node.newer == oldest then None else go node.newer in
    go oldest

  let iter t f =
    if Array.length t.oldest > 0 then begin
      let oldest = t.oldest.(0) in
      let rec go node =
        let next = node.newer in
        f node.key node.value; if next != oldest then go next in
      go oldest
    end

  let length t = Table.length t.table
  let bytes t = t.bytes
  let rec clear t =
    if Array.length t.oldest > 0 then begin drop t t.oldest.(0); clear t end
end
