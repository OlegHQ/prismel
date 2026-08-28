open Runtime_next_provider

let expect_error predicate = function
  | Error error when predicate error -> ()
  | Ok _ | Error _ -> failwith "unexpected provider registry result"

let provider target name version =
  let module Provider = struct
    let abi_version = version
    let target = target
    let name = name
  end in
  Pack (module Provider : S)

let () =
  Private.reset ();
  expect_error (function Missing_target Web -> true | _ -> false) (find Web);
  expect_error
    (function Abi_mismatch { expected; actual=0; _ } -> expected=abi_version | _ -> false)
    (register (provider Web "stale" 0));
  if register (provider Web "web" abi_version) <> Ok () then
    failwith "valid provider rejected";
  expect_error (function Duplicate_target Web -> true | _ -> false)
    (register (provider Web "duplicate" abi_version));
  (match find Web with
   | Ok (Pack (module Provider)) when Provider.name="web" -> ()
   | _ -> failwith "registered provider identity changed");
  print_endline "runtime-next provider registry: missing/ABI/duplicate/pinned identity"
