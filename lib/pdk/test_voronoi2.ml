open Pdk
open Prismel_math

let point x y = Vec2.create x y
let get = function Ok value -> value | Error error -> failwith (Error.to_string error)
let check condition message = if not condition then failwith message

let run () =
  let bounds = Bounds2.make ~min:(point 0. 0.) ~max:(point 10. 10.) in
  let sites = [point 0. 0.; point 10. 0.; point 10. 10.;
    point 0. 10.; point 5. 5.; point 5. 5.] in
  let expected = [
    point 0. 0., [point 0. 5.; point 0. 0.; point 5. 0.];
    point 10. 0., [point 10. 5.; point 5. 0.; point 10. 0.];
    point 10. 10., [point 5. 10.; point 10. 5.; point 10. 10.];
    point 0. 10., [point 0. 5.; point 5. 10.; point 0. 10.];
    point 5. 5., [point 0. 5.; point 5. 0.; point 10. 5.; point 5. 10.]
  ] in
  let cells domains = Parallel.run ~domains (fun () ->
    Voronoi2.cells ~bounds sites |> get) in
  let one = cells 1 and four = cells 4 in
  let signature cells = List.map (fun (cell : Voronoi2.cell) ->
    cell.site, cell.vertices) cells in
  check (signature one = expected) "Voronoi baseline ordering/vertices changed";
  check (signature four = expected) "Voronoi domain parity changed";
  check (List.length one = 5) "Voronoi cardinality changed";
  (match Voronoi2.cells ~epsilon:(-1.) ~bounds sites with
   | Error _ -> () | Ok _ -> failwith "negative epsilon succeeded");
  (match Voronoi2.cells ~bounds [point Float.nan 0.] with
   | Error _ -> () | Ok _ -> failwith "nonfinite site succeeded");
  let cancel = Cancel.create () in
  Cancel.cancel cancel;
  (match Voronoi2.cells ~cancel ~bounds sites with
   | Error error when Error.code error = "cancelled" -> ()
   | _ -> failwith "cancelled Voronoi succeeded");
  print_endline "bounded Voronoi PDK fixture passed"
