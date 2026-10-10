type filter = Hard | Pcf_3x3 | Pcf_5x5

type t = {

  view_projection : Mat4.t;
  width : int;
  height : int;
  depths : float array;
  bias : float;
  normal_bias : float;
  filter : filter;
  strength : float;
  id : int;  (* process-local identity; shadows are immutable *)
}

module Private = struct
  type snapshot = {
    view_projection : Mat4.t;
    width : int;
    height : int;
    depths : float array;
    bias : float;
    normal_bias : float;
    filter : filter;
    strength : float;
  }

  let identity (shadow:t) = shadow.id
  let snapshot (shadow:t) =
    { view_projection=shadow.view_projection;width=shadow.width;height=shadow.height;
      depths=Array.copy shadow.depths;bias=shadow.bias;normal_bias=shadow.normal_bias;
      filter=shadow.filter;strength=shadow.strength }

end
