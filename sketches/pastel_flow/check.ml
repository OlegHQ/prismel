open Prismel
let ui () = Artwork.preset false
let validate ui =
  let art,vertices=Artwork.build ui 0. in
  assert(vertices>0 && vertices<600_000);
  List.iter(fun (d:Scene3.Private.drawing)->
    let mesh=Mesh.Private.packed_view d.mesh in
    let n=Array.length mesh.vertices.x in
    assert(n=Array.length mesh.vertices.y && n=Array.length mesh.vertices.z);
    Array.iter(fun plane->Array.iter(fun x->assert(Float.is_finite x)) plane)
      [|mesh.vertices.x;mesh.vertices.y;mesh.vertices.z|];
    Array.iter(fun i->assert(i>=0 && i<n)) mesh.indices;
    assert(Array.length mesh.indices mod 3=0);
    assert(Option.is_some mesh.normals);
    Option.iter (Array.iter(fun (c:Color.t)->
      List.iter(fun v->assert(v>=0 && v<=255)) [c.r;c.g;c.b;c.a])) mesh.colors
  ) (Scene3.Private.drawings art);
  art
let digest art =
  Scene3.Private.drawings art |> List.map(fun (d:Scene3.Private.drawing)->
    Mesh.Private.packed_view d.mesh) |> fun meshes ->
  Digest.string(Marshal.to_string meshes [])
let () =
  let ui=ui () in
  let a=validate ui in
  assert(digest a=digest(validate ui));
  List.iter(fun (c:Artwork.control)->
    List.iter(fun value->ignore(validate(Artwork.set ui c.key value)))
      [c.lo;c.hi]) Artwork.controls;
  List.iter(fun high->ignore(validate(List.fold_left(fun ui (c:Artwork.control)->
    Artwork.set ui c.key (if high then c.hi else c.lo)) ui Artwork.controls))) [false;true];
  let path=Filename.temp_file "pastel-flow" ".json" in
  Fun.protect ~finally:(fun()->Sys.remove path) (fun()->
    let settings = List.map (fun (key, value) -> key, Pxui.Settings.Float value) ui in
    assert(Pxui.Settings.save path settings=Ok());
    match Pxui.Settings.load path with Error e->failwith e | Ok loaded->
      let loaded = List.map (fun (c:Artwork.control) ->
        c.key, Option.get (Pxui.Settings.float loaded c.key)) Artwork.controls in
      assert(Artwork.signature ui=Artwork.signature loaded));
  let no_grain ui = Artwork.set ui "grain" 0. in
  let seed_a = no_grain (Artwork.set ui "seed" 11.) in
  let seed_b = no_grain (Artwork.set ui "seed" 97.) in
  assert(digest(validate seed_a)=digest(validate seed_b));
  let chaos ui seed =
    ui |> fun ui -> Artwork.set ui "seed" seed
    |> fun ui -> Artwork.set ui "randomness" 0.65
    |> no_grain
  in
  assert(digest(validate(chaos ui 11.))<>digest(validate(chaos ui 97.)));
  Printf.printf "Checked %d control boundaries, combined extrema, seed chaos, repeatability and settings round-trip.\n"
    (List.length Artwork.controls * 2)
