open Raster2

let ok = function Ok value -> value | Error _ -> failwith "unexpected atlas error"
let rgba r g b a = Bytes.init 4 (function 0 -> Char.chr r | 1 -> Char.chr g | 2 -> Char.chr b | _ -> Char.chr a)
let key n = Atlas.Glyph { font = 1L; codepoint = n; density = 2 }

let snapshot () =
  let atlas = ok (Atlas.create ~page_width:8 ~page_height:8 ~max_pages:2 ~max_entries:4 ~padding:1) in
  let p0 = ok (Atlas.add atlas (key 0) ~width:1 ~height:1 (rgba 1 2 3 4)) in
  let p1 = ok (Atlas.add atlas (key 1) ~width:2 ~height:1 (Bytes.cat (rgba 5 6 7 8) (rgba 9 10 11 12))) in
  if p0 <> { Atlas.page = 0; x = 1; y = 1; width = 1; height = 1 } then failwith "first placement";
  if p1.x <= p0.x + p0.width then failwith "padding/overlap";
  let page = Option.get (Atlas.page_bytes atlas ~page:0) in
  let offset = ((p0.y * 8) + p0.x) * 4 in
  if Bytes.sub page offset 4 <> rgba 1 2 3 4 then failwith "pixel copy";
  ignore (Atlas.find atlas (key 0));
  for i = 2 to 100_001 do ignore (ok (Atlas.add atlas (key i) ~width:1 ~height:1 (rgba (i land 255) 0 0 255))) done;
  if Atlas.length atlas <> 4 || Atlas.page_count atlas > 2 then failwith "bounded plateau";
  let before = Atlas.placements atlas in
  Atlas.invalidate_density atlas ~density:7;
  if Atlas.placements atlas <> before then failwith "precise density invalidation";
  Atlas.invalidate_density atlas ~density:2;
  if Atlas.length atlas <> 0 || Atlas.page_count atlas <> 0 then failwith "density invalidation";
  before

let () =
  let first = snapshot () in
  let results = Array.init 4 (fun _ -> snapshot ()) in
  Array.iter (fun result -> if result <> first then failwith "domain drift") results;
  let atlas = ok (Atlas.create ~page_width:4 ~page_height:4 ~max_pages:1 ~max_entries:1 ~padding:1) in
  begin match Atlas.add atlas (key 1) ~width:3 ~height:3 (Bytes.make 36 '\000') with
  | Error Atlas.Full -> () | _ -> failwith "oversize accepted"
  end;
  print_endline "raster2 bounded deterministic atlas passed"
