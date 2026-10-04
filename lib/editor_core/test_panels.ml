open Editor_core.Panels

let v = Leaf (View "main") and g = Leaf Graph
let h ?(ratio = 0.5) a b = Split { axis = `H; ratio; a; b }
let s ?(ratio = 0.5) a b = Split { axis = `V; ratio; a; b }

let () =
  let check tree expected =
    if label tree <> expected then failwith (Printf.sprintf "%s: %S, expected %S" (to_string tree) (label tree) expected) in
  check v "View";
  check (s (h v g) (Leaf Timeline)) "(View | Graph) / Timeline";
  check (h v (s g (Leaf Lisp))) "View | Graph / Lisp";
  check (h (h v g) (Leaf Inspector)) "View | Graph | Inspector";
  check (Tile [ v; v; v; v ]) "View \xc3\x974";
  check (h v (h v g)) "View \xc3\x972 | Graph";
  check (h g (Float (Leaf Lisp))) "Graph + Lisp";
  check (h (Leaf Outline) (h v (h g (Leaf Inspector)))) "Outline | View | Graph | Inspector";
  check (h v (Float (Leaf Inspector))) "View + Inspector";
  assert (labels [ h ~ratio:0.3 v g; h ~ratio:0.7 v g ]
          = [ "View | Graph \xc2\xb7 Graph 70%"; "View | Graph \xc2\xb7 View 70%" ]);
  assert (labels [ v; v; g ] = [ "View \xc2\xb7 View 100%"; "View \xc2\xb7 View 100% (2)"; "Graph" ])
