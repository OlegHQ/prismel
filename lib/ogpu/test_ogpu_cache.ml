let fail message = raise (Failure message)
let ok = function Ok value -> value | Error error -> fail (Ogpu.Error.to_string error)
let expect_invalid = function
  | Error (error : Ogpu.Error.t) when error.kind = Invalid_argument -> ()
  | _ -> fail "expected invalid argument"

let () =
  expect_invalid (Ogpu.Cache.create ~capacity:0 ~on_evict:(fun ~key:_ _ _ -> ()));
  let events = ref [] in
  let cache = ok (Ogpu.Cache.create ~capacity:3 ~on_evict:(fun ~key value reason ->
    events := (key, value, reason) :: !events)) in
  List.iter (fun (key, value) -> ignore (ok (Ogpu.Cache.insert cache key value)))
    [ "a", 1; "b", 2; "c", 3 ];
  ignore (Ogpu.Cache.get cache "a");
  ignore (ok (Ogpu.Cache.insert cache "d" 4));
  if Ogpu.Cache.keys_lru cache <> [ "c"; "a"; "d" ] then fail "deterministic eviction order drift";
  if List.hd !events <> ("b", 2, Ogpu.Cache.Capacity) then fail "wrong capacity eviction";
  ignore (ok (Ogpu.Cache.insert cache "a" 10));
  if Ogpu.Cache.keys_lru cache <> [ "c"; "d"; "a" ] then fail "replacement did not promote";
  if List.hd !events <> ("a", 1, Ogpu.Cache.Replaced) then fail "replacement callback drift";
  expect_invalid (Ogpu.Cache.insert cache "" 1);
  if Ogpu.Cache.length cache <> 3 then fail "invalid insertion changed cardinality";
  let raising = ok (Ogpu.Cache.create ~capacity:2 ~on_evict:(fun ~key:_ _ _ -> raise Exit)) in
  ignore (ok (Ogpu.Cache.insert raising "x" 1));
  ignore (ok (Ogpu.Cache.insert raising "y" 2));
  ignore (ok (Ogpu.Cache.insert raising "z" 3));
  Ogpu.Cache.drain_device_loss raising;
  if Ogpu.Cache.length raising <> 0 || Ogpu.Cache.callback_errors raising <> 3 then
    fail "raising callback interrupted deterministic drain";
  let bounded = ok (Ogpu.Cache.create ~capacity:64 ~on_evict:(fun ~key:_ _ _ -> ())) in
  for index = 0 to 99_999 do
    ignore (ok (Ogpu.Cache.insert bounded (string_of_int index) index));
    if Ogpu.Cache.length bounded > 64 then fail "cache exceeded capacity"
  done;
  if Ogpu.Cache.length bounded <> 64 then fail "100k cache cardinality drift";
  let prepare start = List.init 100 (fun offset -> Printf.sprintf "%08d" (start + offset)) in
  let sequential = List.concat_map prepare [ 0; 100; 200; 300 ] |> List.sort String.compare in
  let workers = Array.init 4 (fun domain -> Domain.spawn (fun () -> prepare (domain * 100))) in
  let parallel = Array.to_list workers |> List.concat_map (fun worker -> Domain.join worker) |> List.sort String.compare in
  if parallel <> sequential then fail "multi-domain prepared-key ordering drift";
  Ogpu.Cache.clear bounded;
  if Ogpu.Cache.length bounded <> 0 then fail "clear did not drain cache";
  print_endline "OGPU bounded deterministic LRU cache passed"
