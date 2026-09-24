open Prismel
open Chromatic_art
let digest scene = Scene3.Private.drawings scene
  |> List.map(fun (d:Scene3.Private.drawing)->Mesh.Private.packed_view d.mesh)
  |> fun v -> Digest.string(Marshal.to_string v [])
let validate p time =
  let art=Drift.build p time in
  let count=ref 0 in
  List.iter(fun (d:Scene3.Private.drawing)->
    let v=Mesh.Private.packed_view d.mesh in
    let n=Array.length v.vertices.x in count:= !count+n;
    Array.iter(fun a->Array.iter(fun x->assert(Float.is_finite x)) a)
      [|v.vertices.x;v.vertices.y;v.vertices.z|];
    (match v.normals with None->assert false | Some normals ->
      for i=0 to n-1 do
        let length=normals.x.(i)**2.+.normals.y.(i)**2.+.normals.z.(i)**2. in
        assert(Float.is_finite length && abs_float(length-.1.)<1e-10)
      done);
    Array.iter(fun i->assert(i>=0 && i<n)) v.indices
  ) (Scene3.Private.drawings art);
  assert(!count=Drift.vertex_count p); art
let () =
  let p=Drift.default in
  let a=digest(validate p 0.) in
  let drawing=List.nth (Scene3.Private.drawings(Drift.build p 0.)) 3 in
  let colors=Option.get (Mesh.Private.packed_view drawing.mesh).colors in
  assert(Array.exists(fun (c:Color.t)->c.r<100) colors);
  assert(Array.exists(fun (c:Color.t)->c.r>180) colors);
  assert(a=digest(validate p 0.));
  assert(a<>digest(validate p 1.));
  assert(a<>digest(validate {p with seed=95} 0.));
  List.iter(fun quality -> ignore(validate {p with quality;depth=0.3;curl=1.} 1.)) [1;2;3];
  assert(a<>digest(validate {p with depth=0.} 0.));
  let g=Drift.grain 42 0.35 ~size:1.3 ~height:1600 in
  assert(digest g=digest(Drift.grain 42 0.35 ~size:1.3 ~height:1600));
  List.iter(fun (d:Scene3.Private.drawing)->
    assert(Mesh.vertex_count d.mesh=4);
    match d.texture with None->assert false | Some t ->
      assert(Texture.size t.value=(256,256));
      let pixels=Texture.pixels t.value in
      assert(List.exists(fun (c:Color.t)->c.a>0 && c.r=255) pixels);
      assert(List.exists(fun (c:Color.t)->c.a>0 && c.r=0) pixels))
    (Scene3.Private.drawings g);
  List.iter (fun changed -> assert(a<>digest(validate changed 0.)))
    [{p with hue=90.}; {p with saturation=0.3}; {p with exposure=0.15};
     {p with color_mix=1.}; {p with variation=1.5}; {p with warp=2.};
     {p with detail=1.}; {p with independent=1.}; {p with offset=0.3};
     {p with sweep=0.}; {p with radiance=0.}; {p with color_depth=0.}];
  for palette=0 to 3 do
    for seed=0 to 12 do
      let p={p with palette;seed;bend=0.55;scale=2.4;spread=0.65;warp=2.;detail=1.;independent=1.;breathing=1.;sweep=1.2;slope=1.4} in
      ignore(validate p 100.);
      let noise=Noise.create seed in
      for i=0 to 128 do
        let edges=Drift.boundaries p noise 100. (-2.+.float i/.32.) in
        for j=0 to 4 do assert(edges.(j)<edges.(j+1)) done
      done
    done
  done;
  print_endline "Chromatic Drift: deterministic motion/seeds, finite geometry, bounded cardinality and ordered bands passed"
