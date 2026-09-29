(* The one renderer choice every sketch shows in its settings block, so the
   editor shell reads the same across sketches. *)
open Prismel

type t = Path_traced | Raster | Wireframe

let kind = Editor_core.Param.choice ~equal:( = )
    [ "Path traced", Path_traced; "Raster", Raster; "Wireframe", Wireframe ]

let field ~default ~get ~set =
  Editor_core.Param.field ~name:"renderer" ~label:"Renderer" ~kind ~default ~get ~set ()

let of_env name = match Sys.getenv_opt name with
  | Some "path" -> Some Path_traced
  | Some "raster" -> Some Raster
  | Some "wireframe" -> Some Wireframe
  | Some _ | None -> None

let wire_color background =
  let lightness = 299 * background.Color.r + 587 * background.g
    + 114 * background.b in
  if lightness >= 128000 then Color.hex_exn "#285f77"
  else Color.hex_exn "#bed7e1"

(* Every polygon edge once, as a line mesh. *)
let wire_mesh geometry =
  let topology = Pdk.Geometry.topology geometry in
  let edges = Pdk.Topology_index.create topology in
  let points = Pdk.Geometry.positions geometry in
  let vertices = Array.init (Pdk.Packed.Float3.length points) (fun index ->
    let x, y, z = Pdk.Packed.Float3.get points index in Vec3.create x y z) in
  let indices = Array.make (Pdk.Topology_index.edge_count edges * 2) 0 in
  for edge = 0 to Pdk.Topology_index.edge_count edges - 1 do
    let a, b = Pdk.Topology_index.edge_points edges edge in
    indices.(edge * 2) <- a; indices.(edge * 2 + 1) <- b
  done;
  Mesh.Private.create_owned ~mode:Mesh.Lines ~indices vertices
