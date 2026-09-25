module Cache = Lru.Make (Int)

let fail message = prerr_endline ("test_lru: " ^ message); exit 1
let check condition message = if not condition then fail message
let keys cache = let out = ref [] in Cache.iter cache (fun k _ -> out := k :: !out); List.rev !out

let () =
  let released = ref [] in
  let cache = Cache.create ~release:(fun k v -> released := (k, v) :: !released) 3 in
  Cache.add cache 1 "a"; Cache.add cache 2 "b"; Cache.add cache 3 "c";
  check (keys cache = [1; 2; 3]) "insertion order oldest first";
  check (Cache.find cache 1 = "a") "hit";
  check (Cache.find_opt cache 9 = None && (try ignore (Cache.find cache 9); false with Not_found -> true)) "miss";
  check (keys cache = [1; 2; 3]) "hit only marks the entry";
  check (Cache.peek cache 2 = Some "b" && keys cache = [1; 2; 3]) "peek keeps order";
  Cache.add cache 4 "d";
  check (keys cache = [3; 4; 1] && !released = [2, "b"]) "the found entry gets a second chance; the untouched oldest goes";
  Cache.add cache 3 "C";
  check (keys cache = [4; 1; 3] && List.hd !released = (3, "c")) "replace releases the old value";
  check (Cache.find_first cache (fun _ v -> v = "d") = Some "d") "find_first";
  check (Cache.take cache 3 = Some "C" && Cache.length cache = 2 && List.hd !released <> (3, "C")) "take does not release";
  Cache.add cache 3 "C";
  Cache.remove cache 4;
  check (Cache.length cache = 2 && List.hd !released = (4, "d")) "remove releases";
  check (Cache.drop_oldest cache && keys cache = [3] && Cache.drop_oldest cache && not (Cache.drop_oldest cache)) "drop_oldest";
  (* Byte capacity and pinned entries. *)
  let pinned = ref 10 in
  let cache = Cache.create ~byte_capacity:10 ~evictable:(fun k _ -> k <> !pinned) 100 in
  Cache.add cache ~bytes:4 10 "p"; Cache.add cache ~bytes:4 11 "q"; Cache.add cache ~bytes:4 12 "r";
  check (keys cache = [12; 10] && Cache.bytes cache = 8) "byte eviction skips the pinned entry (it moves to newest)";
  Cache.add cache ~bytes:11 13 "big";
  check (Cache.peek cache 13 = None && Cache.bytes cache = 4 && keys cache = [10])
    "oversize entry leaves at once after evicting what it can";
  pinned := -1; Cache.add cache ~bytes:8 14 "s";
  check (keys cache = [14] && Cache.bytes cache = 8) "unpinned entry evicts";
  let count = ref 0 in
  let cache = Cache.create ~release:(fun _ _ -> incr count) 8 in
  for i = 1 to 20 do Cache.add cache i i done;
  Cache.clear cache;
  check (!count = 20 && Cache.length cache = 0 && Cache.bytes cache = 0) "clear releases everything";
  (* Steady-state hits and re-adds of present keys allocate nothing. *)
  let cache = Cache.create 64 in
  for i = 0 to 63 do Cache.add cache i i done;
  let before = Gc.minor_words () in
  for round = 0 to 999 do ignore (Sys.opaque_identity (Cache.find cache (round land 63))) done;
  for round = 0 to 999 do ignore (Sys.opaque_identity (Cache.find cache (round * 7 land 63))) done;
  check (Gc.minor_words () -. before < 64.) "hit path allocates";
  print_endline "lru: order, eviction, bytes, pinning, release, allocation-free hits"
