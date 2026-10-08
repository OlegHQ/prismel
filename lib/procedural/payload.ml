type t = Geometry of Rdk.Geometry.t | Image of Image.t
let data_id = function Geometry geometry -> Rdk.Geometry.data_id geometry | Image image -> Image.data_id image
let payload_components = function
  | Geometry geometry -> Rdk.Geometry.payload_components geometry
  | Image image -> [Image.data_id image, Image.payload_bytes image]
let element_count = function
  | Geometry geometry -> Rdk.Geometry.point_count geometry
  | Image image -> Image.width image * Image.height image
let wrong expected = Error (Diagnostic.error ~code:"E_PAYLOAD" ("Expected a cooked " ^ expected ^ " payload."))
let geometry = function Geometry geometry -> Ok geometry | Image _ -> wrong "geometry"
let image = function Image image -> Ok image | Geometry _ -> wrong "image"
