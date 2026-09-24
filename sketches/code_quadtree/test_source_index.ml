let require condition message = if not condition then failwith message

let () =
  let fixture=Yojson.Basic.from_string {|[
    {"name":"Outer","kind":2,"range":{"start":{"line":0},"end":{"line":8}},
     "children":[{"name":"f","kind":12,"range":{"start":{"line":2},"end":{"line":4}}}]}
  ]|} in
  let parsed=Source_index.symbols fixture in
  require (Source_index.count parsed=2) "nested symbol count";
  require (Source_index.symbols (`List (List.map Source_index.symbol_json parsed))=parsed)
    "cache round-trip lost symbol structure";
  (match parsed with
   |[{name="Outer";children=[{name="f";first_line=2;last_line=4;_}];_}]->()
   |_->failwith "symbol ranges/nesting changed");
  require (Source_index.symbols `Null=[]) "empty symbol response";
  require (Source_index.uri "/a b/#é.ml"="file:///a%20b/%23%C3%A9.ml") "URI escaping";
  require (Source_index.params_field `Null=[]) "shutdown must omit absent params";
  if Array.mem "--live" Sys.argv then begin
    let root=Filename.temp_file "prismel lsp " ".fixture" in
    Sys.remove root;Unix.mkdir root 0o700;
    let file=Filename.concat root "nested source.ml" in
    let cache_directory=Filename.concat root "cache" in
    let write source =
      let out=open_out_bin file in
      Fun.protect ~finally:(fun () -> close_out out) (fun () -> output_string out source) in
    Fun.protect ~finally:(fun () -> Sys.remove file;
      Sys.remove (Filename.concat cache_directory "symbols.json");
      Unix.rmdir cache_directory;Unix.rmdir root) (fun () ->
      write "module Outer = struct\n  type t = A | B\n  let f x = x + 1\nend\n";
      let paths=[|"nested source.ml";"unindexed.c"|] in
      let trees,first=Source_index.load ~cache_directory ~server:"ocamllsp" ~root paths in
      require (first.parsed=1 && first.unsupported=1 && first.symbol_count>=3)
        "live index coverage";
      let rec contains_nested = function
        |[]->false
        |s::rest -> (s.Source_index.name="Outer" &&
            List.exists (fun child -> child.Source_index.name="f") s.children)
            || contains_nested s.children || contains_nested rest in
      require (contains_nested (Option.get trees.(0))) "server hierarchy flattened";
      let cached,second=Source_index.load ~cache_directory ~server:"ocamllsp" ~root paths in
      require (trees=cached && second.reused=1 && second.parsed=0) "cache miss/drift";
      write "module Outer = struct\n let changed x = x\nend\n";
      let changed,third=Source_index.load ~cache_directory ~server:"ocamllsp" ~root paths in
      require (third.parsed=1 && changed<>cached) "edited source reused stale cache";
      print_endline "live LSP: nesting/ranges, escaped URI, cache reuse/invalidation, clean shutdown")
  end;
  print_endline "source index: nested symbols, ranges, URI, cache codec"
