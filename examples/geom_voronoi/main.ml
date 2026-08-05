open Prismel
open Geom

type model = {
  sites : Vec2.t list;
  phase : float;
  frames_left : int option;
}

let rec random_sites count generator points =
  if count = 0 then List.rev points
  else
    let x, generator = Rand.range ~min:58. ~max:842. generator in
    let y, generator = Rand.range ~min:72. ~max:550. generator in
    random_sites (count - 1) generator (Vec2.create x y :: points)

let init _frame =
  {
    sites = random_sites 64 (Rand.seed 0x6e6f6465) [];
    phase = 0.;
    frames_left = if Sketch.is_headless () then Some 3 else None;
  }

let update model (frame : Frame.t) =
  let frames_left =
    match model.frames_left with
    | Some 1 -> Sketch.quit (); Some 0
    | Some count -> Some (count - 1)
    | None -> None
  in
  {
    model with
    phase = model.phase +. frame.dt;
    frames_left;
  }

let animated_sites phase sites =
  List.mapi
    (fun index point ->
      let index = float_of_int index in
      Vec2.add point
        (Vec2.create
           (7. *. sin ((phase *. 0.37) +. (index *. 1.73)))
           (7. *. cos ((phase *. 0.31) +. (index *. 1.17)))))
    sites

let view model _frame =
  let sites = animated_sites model.phase model.sites in
  let bounds =
    Bounds2.make ~min:(Vec2.create 40. 58.) ~max:(Vec2.create 860. 566.)
  in
  let triangles = Delaunay2.triangulate sites in
  let cells = Delaunay2.voronoi_cells ~bounds sites in
  let fill (cell : Delaunay2.cell) =
    let hue =
      195.
      +. (145. *. (Bounds2.map_normalized bounds cell.site).Vec2.x)
      +. (18. *. sin (model.phase +. (cell.site.y *. 0.012)))
    in
    Color.hsl ~alpha:0.72 hue 0.72 0.55
  in
  Scene.(
    [
      clear (Color.hex_exn "#070b18");
      Render2.voronoi ~fill
        ~stroke:(Color.rgba 229 231 255 40) cells;
      blend Add [
        Render2.segments
          ~color:(Color.rgba 103 232 249 54)
          (Delaunay2.unique_edges triangles);
      ];
      Render2.points ~radius:2 ~color:(Color.hex_exn "#f8fafc") sites;
      text ~at:(22, 16) ~size:17 "Geom · Delaunay / Voronoi";
      text ~at:(22, 42) ~size:12
        "64 deterministic sites · bounded cells · dual triangulation";
    ])

let config = {
  Sketch.default_config with
  width = 900;
  height = 600;
  title = "Prismel Geom Voronoi";
  clock = Sketch.Fixed (1. /. 60.);
}

let () =
  match Sys.getenv_opt "PRISMEL_EXPORT_DIR" with
  | Some directory ->
      ignore
        (Sketch.export_state ~config ~directory ~prefix:"geom-voronoi"
           ~frames:1 ~init ~update ~view ())
  | None ->
      ignore (Sketch.run_state ~config ~init ~update ~view ())
