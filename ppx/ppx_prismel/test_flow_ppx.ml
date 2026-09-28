let program = [%flow {|(graph demo :context sop
  (let* [cube (sop/box :size [1 2 3])
         moved (sop/transform cube)]
    moved))|}]

let () =
  assert (program.Flow_sop.Program.name = "demo");
  assert (program.display = Some 2);
  assert (List.length (Procedural.Edit_graph.inspect program.network.geometry) = 2)
