open Procedural
let ok = function Ok value -> value | Error error -> failwith (Diagnostic.error_to_string error)
let session bytes = Result.get_ok (Session.create ~max_entries:1 ~max_payload_bytes:bytes)
let context domains = Result.get_ok (Context.create ~domains ~grain:17 ())
let bytes image = Marshal.to_string (Image.width image, Image.height image, Image.Private.storage image) [Marshal.No_sharing]
let () =
  let source = [|0.1;0.2;0.3;1.|] in
  let image = ok (Image.create ~width:1 ~height:1 ~rgba:source) in
  source.(0) <- 0.9;
  let copy = Image.rgba image in copy.(1) <- 0.8;
  assert (Image.Private.storage image = [|0.1;0.2;0.3;1.|]);
  List.iter (fun (width,height,rgba) -> assert (Result.is_error (Image.create ~width ~height ~rgba)))
    [0,1,[||];max_int,2,[||];1,1,[|nan;0.;0.;1.|];1,1,[|0.;0.;0.;2.|];1,1,[||]];
  let node = Image_nodes.noise ~width:32 ~height:24 ~frequency:0.12 ~seed:31 () in
  let one = session 65536 and eight = session 65536 in
  Fun.protect ~finally:(fun () -> Session.close one; Session.close eight) (fun () ->
    let first = ok (Session.cook one ~context:(context 1) node) in
    let parallel = ok (Session.cook eight ~context:(context 8) node) in
    let image = ok (Payload.image first.payload) in
    assert (bytes image = bytes (ok (Payload.image parallel.payload)));
    assert ((Session.stats one).retained_payload_bytes = 32*24*4*8);
    let second = ok (Session.cook one ~context:(context 1) node) in
    assert (second.payload == first.payload);
    assert ((Session.stats one).hits = 1 && (Session.stats one).cooks = 1);
    ignore (ok (Session.cook one ~context:(context 1) (Image_nodes.noise ~width:8 ~height:4 ())));
    assert ((Session.stats one).retained_entries = 1 && (Session.stats one).evictions = 1);
    (* CLOCK protects the just-hit image once, dropping the newest entry. *)
    assert ((Session.stats one).retained_payload_bytes = Image.payload_bytes image);
    ignore (ok (Session.cook one ~context:(context 1) (Image_nodes.noise ~width:4 ~height:4 ())));
    assert ((Session.stats one).retained_payload_bytes = 4*4*4*8);
    (match Session.cook one ~context:(context 1) (Sop.transform node) with
     | Error error -> assert (error.code = "E_PAYLOAD") | Ok _ -> assert false));
  let tiny = session 1 in
  Fun.protect ~finally:(fun () -> Session.close tiny) (fun () ->
    ignore (ok (Session.cook tiny ~context:(context 1) node));
    assert ((Session.stats tiny).retained_entries = 0 && (Session.stats tiny).retained_payload_bytes = 0));
  let image_input = Node.Private.make ~operation:"image/instances-test" ~version:1
    ~parameters:"" ~cook_mode:Node.Generator ~dependencies:Context.Dependencies.static ~inputs:[||]
    (fun ~node_id:_ _ _ -> Ok Node.Private.{payload=Payload.Image image; diagnostics=[];
      instances=Some [|Rays_math.Mat4.identity|]}) in
  let passthrough = Node.Private.make ~operation:"image/pass-test" ~version:1
    ~parameters:"" ~cook_mode:Node.Generic ~dependencies:Context.Dependencies.static ~inputs:[|image_input|]
    (fun ~node_id:_ _ inputs -> Ok Node.Private.{payload=inputs.(0); diagnostics=[]; instances=None}) in
  let passing = session 65536 in
  Fun.protect ~finally:(fun () -> Session.close passing) (fun () ->
    let output = ok (Session.cook passing ~context:(context 1) passthrough) in
    assert (ok (Payload.image output.payload) == image));
  print_endline "payload: immutable image, exact domains, cache/eviction accounting and typed geometry refusal passed"
