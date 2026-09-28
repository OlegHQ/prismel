open Flow

let get = function Ok value -> value
  | Error diagnostic -> failwith (Diagnostic.to_string diagnostic)

let () =
  let source = "; heading\n(graph demo :context sop\n  (let* [box ^:bypass (sop/box :size [1 2 3])] box))" in
  let forms = get (Sexp.parse source) in
  let graph = List.hd forms in
  assert (graph.position = Diagnostic.{line = 2; col = 1}
    && graph.span.start = 10 && graph.span.finish = String.length source);
  let body = match graph.node with Sexp.List forms -> List.nth forms 4
    | _ -> failwith "reader lost the graph list" in
  let bindings = match body.node with Sexp.List forms -> List.nth forms 1
    | _ -> failwith "reader lost the let* form" in
  (match bindings.node with
   | Sexp.Vector [_; {node = Sexp.Meta ("bypass", _); _}] -> ()
   | _ -> failwith "reader lost the metadata or vector structure");
  let quoted = get (Sexp.parse "(graph x :label \"line\\n\\\"quoted\\\"\")") in
  (match (List.hd quoted).node with
   | Sexp.List [_;_;_;{node = Sexp.Atom (Sexp.String value); _}]
     -> assert (value = "line\n\"quoted\"")
   | _ -> failwith "reader lost a string escape");
  let numbers = get (Sexp.parse "[-.5 1. 3 - 1e3]") in
  (match (List.hd numbers).node with
   | Sexp.Vector [{node = Sexp.Atom (Sexp.Number "-.5"); _};
       {node = Sexp.Atom (Sexp.Number "1."); _};
       {node = Sexp.Atom (Sexp.Number "3"); _};
       {node = Sexp.Atom (Sexp.Symbol "-"); _};
       {node = Sexp.Atom (Sexp.Symbol "1e3"); _}] -> ()
   | _ -> failwith "reader misclassified numeric tokens");
  List.iter (fun (source, code, offset) -> match Sexp.parse source with
    | Ok _ -> failwith ("accepted invalid s-expression: " ^ source)
    | Error diagnostic ->
        assert (diagnostic.code = code);
        let position = Sexp.position_of_offset source offset in
        assert (diagnostic.position = Some position);
        assert (Option.map (fun span -> span.Diagnostic.start)
          diagnostic.span = Some offset))
    ["(", "E_UNCLOSED", 0;
     "[1 2)", "E_UNEXPECTED", 4;
     ")", "E_UNEXPECTED", 0;
     "^:bypass", "E_UNEXPECTED", 0;
     "\"bad\\q\"", "E_UNEXPECTED", 4;
     "\"unfinished", "E_UNCLOSED", 0];
  assert (Sexp.position_of_offset "a\nb\nc" 4
    = Diagnostic.{line = 3; col = 1});
  assert ((Diagnostic.warning ~position:Diagnostic.{line = 2; col = 3}
    ~code:"W_SOFT_RANGE" "Outside slider range").severity
    = Diagnostic.Warning);
  print_endline "Flow S-expression reader: positioned forms, escapes and syntax diagnostics pass"
