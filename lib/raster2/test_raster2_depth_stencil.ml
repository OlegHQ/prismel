open Raster2.Depth_stencil

let ok = function Ok value -> value | Error _ -> failwith "depth/stencil error"

let stencil = Some { compare=Equal; fail=Increment_wrap; depth_fail=Decrement_clamp; pass=Replace; read_mask=0x0f; write_mask=0x3f; reference=3 }
let state depth_compare = { depth_compare; depth_write=true; stencil }

let render () =
  let value = ok (create ~width:2 ~height:2 ~pitch:24 ()) in
  Bytes.fill (bytes value) 0 (Bytes.length (bytes value)) '\x7f';
  ok (clear value ~depth:1. ~stencil:3);
  assert (ok (test_and_update value (state Less) ~x:0 ~y:0 ~depth:0.5));
  assert (ok (get value ~x:0 ~y:0) = (0.5,3));
  assert (not (ok (test_and_update value (state Greater) ~x:0 ~y:0 ~depth:0.25)));
  assert (ok (get value ~x:0 ~y:0) = (0.5,2));
  let changed = { (Option.get stencil) with reference=4 } in
  let base = state Always in
  let failed = { base with stencil=Some changed } in
  assert (not (ok (test_and_update value failed ~x:0 ~y:0 ~depth:0.1)));
  assert (ok (get value ~x:0 ~y:0) = (0.5,3));
  assert (Bytes.get (bytes value) 16 = '\x7f');
  Bytes.copy (bytes value)

let () =
  (match create ~width:2 ~height:1 ~pitch:15 () with Error (Invalid_pitch _) -> () | _ -> failwith "short pitch");
  (match of_bytes ~width:2 ~height:2 ~pitch:16 (Bytes.create 31) with Error (Storage_too_small _) -> () | _ -> failwith "short storage");
  let value = ok (create ~width:1 ~height:1 ()) in
  (match clear value ~depth:nan ~stencil:0 with Error (Invalid_depth _) -> () | _ -> failwith "NaN depth");
  (match clear value ~depth:1. ~stencil:256 with Error (Invalid_stencil_value 256) -> () | _ -> failwith "wide stencil");
  let expected = render () in
  let workers = Array.init 4 (fun _ -> Domain.spawn render) in
  Array.iter (fun worker -> assert (Domain.join worker = expected)) workers;
  let checked=ok(create~width:1~height:1())and direct=ok(create~width:1~height:1())in
  ok(clear checked~depth:1.~stencil:3);ok(clear direct~depth:1.~stencil:3);
  let hot_state=state Less in
  List.iter(fun depth->
    let expected=ok(test_and_update checked hot_state~x:0~y:0~depth)in
    let actual=Private.test_and_update_unchecked direct hot_state~x:0~y:0~depth in
    assert(expected=actual&&bytes checked=bytes direct))[0.75;0.8;0.5;0.25];
  ok(clear direct~depth:1.~stencil:3);Gc.full_major();
  let allocated=Gc.allocated_bytes()in
  for _=1 to 100_000 do
    ignore(Private.test_and_update_unchecked direct hot_state~x:0~y:0~depth:0.5)
  done;
  let per_test=(Gc.allocated_bytes()-.allocated)/.100_000. in
  (* The stored binary32 conversion retains one boxed float word on OCaml 5;
     the primitive allocates no Result/error container on the valid path. *)
  if per_test>8.1 then failwith(Printf.sprintf"private depth test allocated %.2f bytes/call"per_test);
  print_endline "Raster2 deterministic packed depth/stencil passed"
