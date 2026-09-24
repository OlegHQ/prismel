open Prismel

type cell = int * int * int

module Pages = Map.Make (Int)

let page_bits = 4096
let page_bytes = page_bits / 8

type t = {
  origin : Vec3.t;
  x_size : int;
  y_size : int;
  z_size : int;
  voxel_size : float;
  pages : bytes Pages.t;
  occupied_count : int;
}

let create ~origin ~dimensions:(x_size, y_size, z_size) ~voxel_size =
  if x_size <= 0 || y_size <= 0 || z_size <= 0 then invalid_arg "Voxel3.create: dimensions must be positive";
  if not (Float.is_finite voxel_size) || voxel_size <= 0. then invalid_arg "Voxel3.create: voxel_size must be finite and positive";
  { origin; x_size; y_size; z_size; voxel_size;
    pages = Pages.empty; occupied_count = 0 }

let origin voxels = voxels.origin
let dimensions voxels = voxels.x_size, voxels.y_size, voxels.z_size
let voxel_size voxels = voxels.voxel_size
let count voxels = voxels.occupied_count
let is_empty voxels = voxels.occupied_count = 0

let valid voxels (x, y, z) = x >= 0 && y >= 0 && z >= 0 && x < voxels.x_size && y < voxels.y_size && z < voxels.z_size

let code voxels (x, y, z) =
  ((x * voxels.y_size) + y) * voxels.z_size + z

let decode voxels code =
  let z = code mod voxels.z_size in
  let xy = code / voxels.z_size in
  let y = xy mod voxels.y_size and x = xy / voxels.y_size in
  x, y, z

let location code =
  let page = code / page_bits and offset = code mod page_bits in
  page, offset lsr 3, 1 lsl (offset land 7)

let page_contains bytes byte mask =
  Char.code (Bytes.get bytes byte) land mask <> 0

let contains cell voxels =
  if not (valid voxels cell) then false
  else
    let page, byte, mask = location (code voxels cell) in
    match Pages.find_opt page voxels.pages with
    | None -> false
    | Some bytes -> page_contains bytes byte mask

let contains_code code voxels =
  let page = code / page_bits in
  try
    let bytes = Pages.find page voxels.pages in
    let offset = code mod page_bits in
    page_contains bytes (offset lsr 3) (1 lsl (offset land 7))
  with Not_found -> false

let contains_xyz x y z voxels =
  x >= 0 && y >= 0 && z >= 0
  && x < voxels.x_size && y < voxels.y_size && z < voxels.z_size
  && contains_code (((x * voxels.y_size) + y) * voxels.z_size + z) voxels

let set_page_bit bytes byte mask =
  Bytes.set bytes byte (Char.chr (Char.code (Bytes.get bytes byte) lor mask))

let clear_page_bit bytes byte mask =
  Bytes.set bytes byte
    (Char.chr (Char.code (Bytes.get bytes byte) land (lnot mask land 0xff)))

let set cell voxels =
  if not (valid voxels cell) then Error "Voxel3.set: cell is outside voxel dimensions"
  else
    let page, byte, mask = location (code voxels cell) in
    match Pages.find_opt page voxels.pages with
    | Some bytes when page_contains bytes byte mask -> Ok voxels
    | previous ->
        let bytes = match previous with
          | None -> Bytes.make page_bytes '\000'
          | Some bytes -> Bytes.copy bytes in
        set_page_bit bytes byte mask;
        Ok { voxels with
          pages = Pages.add page bytes voxels.pages;
          occupied_count = voxels.occupied_count + 1;
        }

let unset cell voxels =
  if not (valid voxels cell) then voxels
  else
    let page, byte, mask = location (code voxels cell) in
    match Pages.find_opt page voxels.pages with
    | None -> voxels
    | Some bytes when not (page_contains bytes byte mask) -> voxels
    | Some previous ->
        let bytes = Bytes.copy previous in
        clear_page_bit bytes byte mask;
        let pages =
          if Bytes.for_all (( = ) '\000') bytes then Pages.remove page voxels.pages
          else Pages.add page bytes voxels.pages in
        { voxels with pages; occupied_count = voxels.occupied_count - 1 }
let toggle cell voxels = if contains cell voxels then Ok (unset cell voxels) else set cell voxels

let fold_codes operation accumulator voxels =
  Pages.fold (fun page bytes accumulator ->
    let page_start = page * page_bits in
    let accumulator = ref accumulator in
    for byte = 0 to Bytes.length bytes - 1 do
      let bits = Char.code (Bytes.get bytes byte) in
      if bits <> 0 then
        for bit = 0 to 7 do
          if bits land (1 lsl bit) <> 0 then
            accumulator := operation !accumulator
                (page_start + (byte * 8) + bit)
        done
    done;
    !accumulator) voxels.pages accumulator

let fold operation accumulator voxels =
  fold_codes (fun accumulator code ->
    operation accumulator (decode voxels code)) accumulator voxels

let cells voxels = fold (fun output cell -> cell :: output) [] voxels |> List.rev

type mutable_builder = {
  template : t;
  pages : (int, bytes) Hashtbl.t;
  mutable occupied_count : int;
}

let builder_of_voxels (voxels : t) =
  let pages = Hashtbl.create (max 16 (Pages.cardinal voxels.pages)) in
  Pages.iter (fun page bytes -> Hashtbl.add pages page (Bytes.copy bytes))
    voxels.pages;
  { template = voxels; pages; occupied_count = voxels.occupied_count }

let builder_add_code builder code =
  let page, byte, mask = location code in
  let bytes = match Hashtbl.find_opt builder.pages page with
    | Some bytes -> bytes
    | None ->
        let bytes = Bytes.make page_bytes '\000' in
        Hashtbl.add builder.pages page bytes;
        bytes in
  if not (page_contains bytes byte mask) then begin
    set_page_bit bytes byte mask;
    builder.occupied_count <- builder.occupied_count + 1
  end

let freeze_builder (builder : mutable_builder) =
  let pages = Hashtbl.fold Pages.add builder.pages Pages.empty in
  { builder.template with pages; occupied_count = builder.occupied_count }

let filter predicate (voxels : t) =
  let empty = { voxels with pages = Pages.empty; occupied_count = 0 } in
  let builder = builder_of_voxels empty in
  fold_codes (fun () code ->
    if predicate (decode voxels code) then builder_add_code builder code) () voxels;
  freeze_builder builder

module Builder = struct
  type voxel = t
  type t = mutable_builder

  let create ~origin ~dimensions ~voxel_size =
    builder_of_voxels (create ~origin ~dimensions ~voxel_size)

  let set cell builder =
    if not (valid builder.template cell) then
      Error "Voxel3.Builder.set: cell is outside voxel dimensions"
    else begin
      builder_add_code builder (code builder.template cell);
      Ok ()
    end

  let freeze builder : voxel = freeze_builder builder
end

let of_cells ~origin ~dimensions ~voxel_size cells =
  let builder = Builder.create ~origin ~dimensions ~voxel_size in
  let rec add = function
    | [] -> Ok (Builder.freeze builder)
    | cell :: rest ->
        Result.bind (Builder.set cell builder) (fun () -> add rest) in
  add cells

let init ~origin ~dimensions:((x_size, y_size, z_size) as dimensions)
    ~voxel_size ~occupied =
  let template = create ~origin ~dimensions ~voxel_size in
  if x_size > max_int / y_size
     || x_size * y_size > max_int / z_size
  then invalid_arg "Voxel3.init: dimensions exceed addressable storage";
  let total = x_size * y_size * z_size in
  let page_count = (total + page_bits - 1) / page_bits in
  let pages = Parallel.init_array ~grain:8 page_count (fun page ->
    let bytes = Bytes.make page_bytes '\000' in
    let first = page * page_bits in
    let last = min total (first + page_bits) in
    let count = ref 0 in
    for code = first to last - 1 do
      let cell = decode template code in
      if occupied cell then begin
        let offset = code - first in
        let byte = offset lsr 3 and mask = 1 lsl (offset land 7) in
        set_page_bit bytes byte mask;
        incr count
      end
    done;
    bytes, !count) in
  let occupied_count = ref 0 in
  let packed = ref Pages.empty in
  Array.iteri (fun page (bytes, count) ->
    if count > 0 then packed := Pages.add page bytes !packed;
    occupied_count := !occupied_count + count) pages;
  { template with pages = !packed; occupied_count = !occupied_count }

let bounds voxels =
  Bounds3.make ~min:voxels.origin
    ~max:(Vec3.add voxels.origin (Vec3.create
      (float_of_int voxels.x_size *. voxels.voxel_size)
      (float_of_int voxels.y_size *. voxels.voxel_size)
      (float_of_int voxels.z_size *. voxels.voxel_size)))

let world_to_cell point voxels =
  if not (Bounds3.contains (bounds voxels) point) then None
  else
    let local = Vec3.sub point voxels.origin in
    let clamp value size = min (size - 1) (int_of_float (Float.floor (value /. voxels.voxel_size))) in
    Some (clamp local.x voxels.x_size, clamp local.y voxels.y_size, clamp local.z voxels.z_size)

let cell_center (x, y, z) voxels =
  if not (valid voxels (x, y, z)) then invalid_arg "Voxel3.cell_center: cell is outside voxel dimensions";
  Vec3.add voxels.origin (Vec3.create
    ((float_of_int x +. 0.5) *. voxels.voxel_size)
    ((float_of_int y +. 0.5) *. voxels.voxel_size)
    ((float_of_int z +. 0.5) *. voxels.voxel_size))

let set_world point voxels = match world_to_cell point voxels with None -> Error "Voxel3.set_world: point is outside voxel bounds" | Some cell -> set cell voxels

let fill_bounds (selection : Bounds3.t) (voxels : t) =
  let builder = builder_of_voxels voxels in
  for z = 0 to voxels.z_size - 1 do
    for y = 0 to voxels.y_size - 1 do
      for x = 0 to voxels.x_size - 1 do
        let px = voxels.origin.x
            +. ((float_of_int x +. 0.5) *. voxels.voxel_size)
        and py = voxels.origin.y
            +. ((float_of_int y +. 0.5) *. voxels.voxel_size)
        and pz = voxels.origin.z
            +. ((float_of_int z +. 0.5) *. voxels.voxel_size) in
        if px >= selection.min.x && px <= selection.max.x
           && py >= selection.min.y && py <= selection.max.y
           && pz >= selection.min.z && pz <= selection.max.z
        then builder_add_code builder (code voxels (x, y, z))
      done
    done
  done;
  freeze_builder builder

let neighbors6 (x, y, z) = [x-1,y,z; x+1,y,z; x,y-1,z; x,y+1,z; x,y,z-1; x,y,z+1]

let neighbors26 (x, y, z) =
  let values = ref [] in
  for dz = -1 to 1 do for dy = -1 to 1 do for dx = -1 to 1 do
    if dx <> 0 || dy <> 0 || dz <> 0 then values := (x+dx, y+dy, z+dz) :: !values
  done done done;
  List.rev !values

let boundary voxels =
  fold (fun output ((x, y, z) as cell) ->
    if not (valid voxels (x - 1, y, z) && contains (x - 1, y, z) voxels
            && valid voxels (x + 1, y, z) && contains (x + 1, y, z) voxels
            && valid voxels (x, y - 1, z) && contains (x, y - 1, z) voxels
            && valid voxels (x, y + 1, z) && contains (x, y + 1, z) voxels
            && valid voxels (x, y, z - 1) && contains (x, y, z - 1) voxels
            && valid voxels (x, y, z + 1) && contains (x, y, z + 1) voxels)
    then cell :: output else output) [] voxels
  |> List.rev

let thicken ?(diagonal = false) ~layers voxels =
  if layers < 0 then invalid_arg "Voxel3.thicken: layers must be non-negative";
  let rec grow count current =
    if count = 0 then current
    else
      let builder = builder_of_voxels current in
      fold (fun () (x, y, z) ->
        if diagonal then
          for dz = -1 to 1 do
            for dy = -1 to 1 do
              for dx = -1 to 1 do
                let neighbor = x + dx, y + dy, z + dz in
                if valid voxels neighbor then
                  builder_add_code builder (code voxels neighbor)
              done
            done
          done
        else begin
          let add neighbor =
            if valid voxels neighbor then
              builder_add_code builder (code voxels neighbor) in
          add (x - 1, y, z); add (x + 1, y, z);
          add (x, y - 1, z); add (x, y + 1, z);
          add (x, y, z - 1); add (x, y, z + 1)
        end) () current;
      grow (count - 1) (freeze_builder builder)
  in
  grow layers voxels

let to_octree ?capacity voxels =
  let entries = cells voxels |> List.map (fun cell -> cell_center cell voxels, cell) in
  match Octree.of_list ?capacity (bounds voxels) entries with Ok tree -> tree | Error message -> failwith message

let face_basis = function
  | (-1, 0, 0) -> Vec3.unit_z, Vec3.unit_y
  | (1, 0, 0) -> Vec3.unit_y, Vec3.unit_z
  | (0, -1, 0) -> Vec3.unit_x, Vec3.unit_z
  | (0, 1, 0) -> Vec3.unit_z, Vec3.unit_x
  | (0, 0, -1) -> Vec3.unit_y, Vec3.unit_x
  | (0, 0, 1) -> Vec3.unit_x, Vec3.unit_y
  | _ -> assert false

let face_directions =
  [| -1, 0, 0; 1, 0, 0; 0, -1, 0;
     0, 1, 0; 0, 0, -1; 0, 0, 1 |]

let surface_mesh ?color voxels =
  if is_empty voxels then Error "Voxel3.surface_mesh: voxel set is empty"
  else begin
    let exposed_faces = fold_codes (fun total code ->
      let z = code mod voxels.z_size in
      let xy = code / voxels.z_size in
      let y = xy mod voxels.y_size and x = xy / voxels.y_size in
      let count = ref total in
      for direction_index = 0 to Array.length face_directions - 1 do
        let dx, dy, dz = face_directions.(direction_index) in
        if not (contains_xyz (x + dx) (y + dy) (z + dz) voxels) then
          incr count
      done;
      !count) 0 voxels in
    let vertex_count = exposed_faces * 6 in
    let vertices = Array.make vertex_count Vec3.zero
    and normals = Array.make vertex_count Vec3.zero
    and colors = Option.map (fun _ -> Array.make vertex_count Color.white) color in
    let output = ref 0 in
    let half = voxels.voxel_size *. 0.5 in
    fold_codes (fun () code ->
      let z = code mod voxels.z_size in
      let xy = code / voxels.z_size in
      let y = xy mod voxels.y_size and x = xy / voxels.y_size in
      let center_x = voxels.origin.x
          +. ((float_of_int x +. 0.5) *. voxels.voxel_size)
      and center_y = voxels.origin.y
          +. ((float_of_int y +. 0.5) *. voxels.voxel_size)
      and center_z = voxels.origin.z
          +. ((float_of_int z +. 0.5) *. voxels.voxel_size) in
      for direction_index = 0 to Array.length face_directions - 1 do
        let ((dx, dy, dz) as direction) = face_directions.(direction_index) in
        if not (contains_xyz (x + dx) (y + dy) (z + dz) voxels) then begin
          let normal = Vec3.create
              (float_of_int dx) (float_of_int dy) (float_of_int dz) in
          let u, v = face_basis direction in
          let face_x = center_x +. (float_of_int dx *. half)
          and face_y = center_y +. (float_of_int dy *. half)
          and face_z = center_z +. (float_of_int dz *. half) in
          let ux = u.x *. half and uy = u.y *. half and uz = u.z *. half
          and vx = v.x *. half and vy = v.y *. half and vz = v.z *. half in
          let p0 = Vec3.create (face_x -. ux -. vx)
              (face_y -. uy -. vy) (face_z -. uz -. vz)
          and p1 = Vec3.create (face_x +. ux -. vx)
              (face_y +. uy -. vy) (face_z +. uz -. vz)
          and p2 = Vec3.create (face_x +. ux +. vx)
              (face_y +. uy +. vy) (face_z +. uz +. vz)
          and p3 = Vec3.create (face_x -. ux +. vx)
              (face_y -. uy +. vy) (face_z -. uz +. vz) in
          let target = !output in
          vertices.(target) <- p0; vertices.(target + 1) <- p1;
          vertices.(target + 2) <- p2; vertices.(target + 3) <- p0;
          vertices.(target + 4) <- p2; vertices.(target + 5) <- p3;
          for offset = 0 to 5 do normals.(target + offset) <- normal done;
          (match color, colors with
           | Some choose, Some values ->
               let value = choose (x, y, z) in
               for offset = 0 to 5 do values.(target + offset) <- value done
           | _ -> ());
          output := target + 6
        end
      done) () voxels;
    assert (!output = vertex_count);
    Mesh.Private.create_owned ~mode:Mesh.Triangles ~normals ?colors vertices
  end

let isosurface ?smooth voxels =
  if is_empty voxels then Error "Voxel3.isosurface: voxel set is empty"
  else
    let field point =
      let px = point.(0) and py = point.(1) and pz = point.(2) in
      let maximum = (bounds voxels).max in
      if px < voxels.origin.x || py < voxels.origin.y || pz < voxels.origin.z
         || px > maximum.x || py > maximum.y || pz > maximum.z
      then 0.
      else
        let cell =
          min (voxels.x_size - 1)
            (int_of_float (Float.floor
               ((px -. voxels.origin.x) /. voxels.voxel_size))),
          min (voxels.y_size - 1)
            (int_of_float (Float.floor
               ((py -. voxels.origin.y) /. voxels.voxel_size))),
          min (voxels.z_size - 1)
            (int_of_float (Float.floor
               ((pz -. voxels.origin.z) /. voxels.voxel_size)))
        in
        if contains cell voxels then 1. else 0.
    in
    Iso3.extract_dense ?smooth ~resolution:(dimensions voxels)
      ~min:voxels.origin ~max:(bounds voxels).max ~iso:0.5
      ~field:(Iso3.Field.custom field) ()
