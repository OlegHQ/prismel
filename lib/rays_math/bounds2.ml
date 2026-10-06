
type t = {
  min : Vec2.t;
  max : Vec2.t;
}

let make ~(min : Vec2.t) ~(max : Vec2.t) =
  {
    min = Vec2.create (Float.min min.Vec2.x max.x) (Float.min min.y max.y);
    max = Vec2.create (Float.max min.x max.x) (Float.max min.y max.y);
  }

let corners bounds =
  [
    bounds.min;
    Vec2.create bounds.max.x bounds.min.y;
    bounds.max;
    Vec2.create bounds.min.x bounds.max.y;
  ]
