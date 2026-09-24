let ok = function Ok value -> value | Error error -> failwith error
let error = function Error _ -> () | Ok _ -> failwith "expected Drawable rejection"

let () =
  let open Binding_drawable_safe_package in
  validate_handoff ();
  let layer = { token = 3; device = 7; destroyed = false } in
  let drawable = ok (create ~layer ~drawable_id:42 ~max_handlers:2) in
  if drawable_id drawable <> 42 || (parent_layer drawable).token <> 3 || device drawable <> 7 then
    failwith "drawable identity/parent/device";
  let calls = ref [] in
  ignore (ok (add_presented_handler drawable (fun time -> calls := time :: !calls)));
  ignore (ok (add_presented_handler drawable (fun _ -> failwith "handler")));
  error (add_presented_handler drawable (fun _ -> ()));
  ignore (ok (present ~now:10. drawable (After_minimum_duration 0.5)));
  error (present ~now:10. drawable Immediate);
  error (mark_presented drawable ~time:10.4);
  error (destroy drawable);
  ignore (ok (mark_presented drawable ~time:10.5));
  if !calls <> [ 10.5 ] || presented_time drawable <> Some 10.5
     || rooted_handler_count drawable <> 0 || callback_error_count drawable <> 1
  then failwith "presentation completion/lifetime";
  error (mark_presented drawable ~time:11.);
  let late = ref 0 in
  ignore (ok (add_presented_handler drawable (fun _ -> incr late)));
  if !late <> 1 then failwith "post-presentation handler exactly once";
  ignore (ok (destroy drawable)); ignore (ok (destroy drawable));
  error (create ~layer:{ layer with destroyed = true } ~drawable_id:1 ~max_handlers:1);
  let invalid = ok (create ~layer ~drawable_id:43 ~max_handlers:1) in
  error (present ~now:10. invalid (At_time 9.));
  error (present ~now:10. invalid (After_minimum_duration (-1.)));
  for index=0 to 9_999 do
    let value=ok(create~layer~drawable_id:index~max_handlers:1)in
    let fired=ref 0 in
    ignore(ok(add_presented_handler value(fun _->incr fired)));
    if index land 1=0 then begin
      ignore(ok(present~now:0. value Immediate));
      ignore(ok(mark_presented value~time:0.));
      if !fired<>1||rooted_handler_count value<>0 then failwith"drawable callback/root leak"
    end else begin
      ignore(ok(destroy value));
      if !fired<>0||rooted_handler_count value<>0 then failwith"drawable cancellation/root leak"
    end
  done;
  Printf.printf
    "Drawable10 reconciled: callable8 metadata2 excluded; timing/idempotence/parent/device/lifetime and 10k callback roots passed\n%!"
