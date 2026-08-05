open Prismel
open Pdk

type kind =
  | Tetrahedron
  | Cube
  | Octahedron
  | Icosahedron
  | Dodecahedron
  | Soccer_ball

let pdk_kind = function
  | Tetrahedron -> Ops.Platonic_tetrahedron
  | Cube -> Ops.Platonic_cube
  | Octahedron -> Ops.Platonic_octahedron
  | Icosahedron -> Ops.Platonic_icosahedron
  | Dodecahedron -> Ops.Platonic_dodecahedron
  | Soccer_ball -> Ops.Platonic_soccer_ball

let get_ok operation = function
  | Ok value -> value
  | Error error -> invalid_arg (operation ^ ": " ^ Error.to_string error)

let geometry ?(flat = false) kind ~radius =
  Ops.platonic ~kind:(pdk_kind kind)
    ~normals:(if flat then Ops.Platonic_vertex_normals
      else Ops.Platonic_point_normals) ~radius ()
  |> get_ok "Polyhedra3.geometry"

let vertices kind ~radius =
  let values = geometry ~flat:false kind ~radius |> Geometry.positions
      |> Packed.Float3.Private.view in
  List.init (Array.length values.x) (fun point ->
    Vec3.create values.x.(point) values.y.(point) values.z.(point))

let mesh ?flat kind ~radius =
  geometry ?flat kind ~radius |> Prismel_mesh.to_mesh
  |> get_ok "Polyhedra3.mesh"

let tetrahedron ?flat ~radius () = mesh ?flat Tetrahedron ~radius
let cube ?flat ~radius () = mesh ?flat Cube ~radius
let octahedron ?flat ~radius () = mesh ?flat Octahedron ~radius
let icosahedron ?flat ~radius () = mesh ?flat Icosahedron ~radius
let dodecahedron ?flat ~radius () = mesh ?flat Dodecahedron ~radius
let soccer_ball ?flat ~radius () = mesh ?flat Soccer_ball ~radius
