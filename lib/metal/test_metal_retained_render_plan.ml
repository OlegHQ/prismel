open Metal

let get = function Ok value -> value | Error error -> failwith error.message
let expect kind = function
  | Error error when error.kind = kind -> ()
  | Error error -> failwith ("unexpected error: " ^ error.message)
  | Ok _ -> failwith "expected failure"

let () =
  let device = get (Device.system_default ()) in
  let descriptor =
    Indirect_command_buffer.descriptor ~command_types:[ Indirect_draw ] ()
  in
  let builds = ref 0 in
  let build buffer =
    incr builds;
    let command = get (Indirect_command_buffer.Render_command.at buffer 0) in
    get (Indirect_command_buffer.Render_command.reset command);
    get (Indirect_command_buffer.Render_command.destroy command);
    Ok ()
  in
  let cache = get (Retained_render_plan.create ~device ~capacity:2 ()) in
  let first, hit =
    get
      (Retained_render_plan.find_or_create cache ~key:"a" ~generation:1L
         ~command_count:1 ~descriptor ~build)
  in
  assert (not hit && !builds = 1 && Retained_render_plan.length cache = 1);
  let same, hit =
    get
      (Retained_render_plan.find_or_create cache ~key:"a" ~generation:1L
         ~command_count:1 ~descriptor ~build)
  in
  assert (hit && same == first && !builds = 1);
  let replacement, hit =
    get
      (Retained_render_plan.find_or_create cache ~key:"a" ~generation:2L
         ~command_count:1 ~descriptor ~build)
  in
  assert (not hit && replacement != first && Indirect_command_buffer.destroyed first);
  let second, _ =
    get
      (Retained_render_plan.find_or_create cache ~key:"b" ~generation:1L
         ~command_count:1 ~descriptor ~build)
  in
  let third, _ =
    get
      (Retained_render_plan.find_or_create cache ~key:"c" ~generation:1L
         ~command_count:1 ~descriptor ~build)
  in
  assert (Indirect_command_buffer.destroyed replacement);
  assert (not (Indirect_command_buffer.destroyed second));
  assert (not (Indirect_command_buffer.destroyed third));
  expect Invalid_argument
    (Retained_render_plan.find_or_create cache ~key:"overflow" ~generation:1L
       ~command_count:65_537 ~descriptor ~build);
  let before = Retained_render_plan.length cache in
  expect Invalid_argument
    (Retained_render_plan.find_or_create cache ~key:"failed" ~generation:1L
       ~command_count:1 ~descriptor
       ~build:(fun buffer ->
         Indirect_command_buffer.reset buffer ~location:(-1) ~length:1));
  assert (Retained_render_plan.length cache = before);
  let unsupported = get (Retained_render_plan.create ~device ~enabled:false ()) in
  expect Unsupported
    (Retained_render_plan.find_or_create unsupported ~key:"x" ~generation:1L
       ~command_count:1 ~descriptor ~build);
  assert (Retained_render_plan.length unsupported = 0);
  get (Retained_render_plan.destroy unsupported);
  get (Retained_render_plan.invalidate cache "b");
  assert (Indirect_command_buffer.destroyed second);
  get (Retained_render_plan.destroy cache);
  assert (Indirect_command_buffer.destroyed third);
  expect Destroyed (Retained_render_plan.invalidate cache "c");
  let handed=ref[]in
  let handoff=get(Retained_render_plan.create~device~capacity:1~on_evict:(fun~key~generation buffer->handed:=(key,generation,buffer)::!handed)())in
  let h1,_=get(Retained_render_plan.find_or_create handoff~key:"h1"~generation:7L~command_count:1~descriptor~build)in
  expect Invalid_argument(Retained_render_plan.find_or_create handoff~key:"bad"~generation:1L~command_count:1~descriptor~build:(fun buffer->Indirect_command_buffer.reset buffer~location:(-1)~length:1));
  assert(!handed=[]);
  let h2,_=get(Retained_render_plan.find_or_create handoff~key:"h2"~generation:8L~command_count:1~descriptor~build)in
  (match!handed with[(key,generation,buffer)]->assert(key="h1"&&generation=7L&&buffer==h1&&not(Indirect_command_buffer.destroyed h1))|_->assert false);
  get(Retained_render_plan.invalidate handoff"h2");
  (match!handed with[(k2,g2,b2);(k1,g1,b1)]->assert(k2="h2"&&g2=8L&&b2==h2&&k1="h1"&&g1=7L&&b1==h1)|_->assert false);
  get(Retained_render_plan.destroy handoff);get(Retained_render_plan.destroy handoff);
  assert(List.length!handed=2);get(Indirect_command_buffer.destroy h1);get(Indirect_command_buffer.destroy h2);
  get (Device.destroy device);
  print_endline "metal retained render plan: hit/rebuild/evict/unsupported/atomic/destroy"
