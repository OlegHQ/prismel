type eviction_reason = Replaced | Capacity | Cleared | Device_lost
type 'value node =
  { key : string; mutable value : 'value
  ; mutable previous : 'value node option; mutable next : 'value node option }
type 'value t =
  { capacity : int; table : (string, 'value node) Hashtbl.t
  ; on_evict : key:string -> 'value -> eviction_reason -> unit
  ; mutable oldest : 'value node option; mutable newest : 'value node option
  ; mutable callback_errors : int }

let create ~capacity ~on_evict =
  if capacity <= 0 then
    Error (Error.make "Ogpu.Cache.create" Error.Invalid_argument "capacity must be positive")
  else Ok { capacity; table = Hashtbl.create capacity; on_evict
          ; oldest = None; newest = None; callback_errors = 0 }

let capacity value = value.capacity
let length value = Hashtbl.length value.table
let callback_errors value = value.callback_errors

let unlink value node =
  (match node.previous with None -> value.oldest <- node.next | Some previous -> previous.next <- node.next);
  (match node.next with None -> value.newest <- node.previous | Some next -> next.previous <- node.previous);
  node.previous <- None;
  node.next <- None

let append value node =
  node.previous <- value.newest;
  node.next <- None;
  (match value.newest with None -> value.oldest <- Some node | Some newest -> newest.next <- Some node);
  value.newest <- Some node

let promote value node =
  match value.newest with
  | Some newest when newest == node -> ()
  | None | Some _ -> unlink value node; append value node

let notify value node reason =
  try value.on_evict ~key:node.key node.value reason
  with _ -> value.callback_errors <- value.callback_errors + 1

let get value key =
  match Hashtbl.find_opt value.table key with
  | None -> None
  | Some node -> promote value node; Some node.value

let remove_reason value key reason =
  match Hashtbl.find_opt value.table key with
  | None -> false
  | Some node ->
      unlink value node;
      Hashtbl.remove value.table key;
      notify value node reason;
      true

let insert value key item =
  if key = "" || String.contains key '\000' then
    Error (Error.make "Ogpu.Cache.insert" Error.Invalid_argument "cache key is empty or contains NUL")
  else begin
    (match Hashtbl.find_opt value.table key with
     | Some node ->
         let old = { node with value = node.value; previous = None; next = None } in
         node.value <- item;
         promote value node;
         notify value old Replaced
     | None ->
         let node = { key; value = item; previous = None; next = None } in
         Hashtbl.add value.table key node;
         append value node;
         if Hashtbl.length value.table > value.capacity then
           match value.oldest with None -> assert false
           | Some oldest -> ignore (remove_reason value oldest.key Capacity));
    Ok ()
  end

let remove value key = remove_reason value key Cleared

let keys_lru value =
  let rec loop acc = function None -> List.rev acc | Some node -> loop (node.key :: acc) node.next in
  loop [] value.oldest

let drain value reason =
  let rec loop () = match value.oldest with
    | None -> () | Some node -> ignore (remove_reason value node.key reason); loop ()
  in
  loop ()

let clear value = drain value Cleared
let drain_device_loss value = drain value Device_lost
