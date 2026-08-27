type style = { fill : Color.t option; stroke : Color.t option }
type blend = Replace | Alpha | Add | Multiply
type node =
  | Clear of Color.t
  | Point of (int * int) * Color.t option
  | Line of (int * int) * (int * int) * Color.t option * int
  | Rect of (int * int) * int * int * int option * style
  | Circle of (int * int) * int * style
  | Ellipse of (int * int) * int * int * style
  | Triangle of (int * int) * (int * int) * (int * int) * style
  | Polygon of (int * int) list * style
  | Polyline of (int * int) list * Color.t option
  | Arc of (int * int) * int * float * float * Color.t option
  | Pie of (int * int) * int * float * float * style
  | Bezier of (int * int) list * int * Color.t option
  | Path of Path.t * int * Path.fill_rule * style
  | Text of (int * int) * string * Color.t option * int
  | Debug_text of (int * int) * string * Color.t option
  | Font_text of Font.t * (int * int) * string * Color.t option * int option * Font.alignment option
  | Image of Image.t * (int * int) * float option * float option * (int * int) option * bool option
  | View3d of Camera.t * Scene3.t * (int * int * int * int) option
  | Text_input_region of (int * int) * int * int * bool
  | Group of node list
  | Translate of int * int * node list
  | Rotate of float * node list
  | Scale of float * float * node list
  | Clip of (int * int) * int * int * node list
  | Blend of blend * node list
type t = node list
