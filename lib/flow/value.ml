type ('f, 'r) t =
  | Int of int
  | Float of float
  | Bool of bool
  | Text of string
  | Vec3 of float * float * float
  | List of ('f, 'r) t array
  | Float_array of float array
  | Vec3_array of float array
  | Record of (string * ('f, 'r) t) list
  | Deferred of Ty.t * int
  | No_geo
  | Struct of string * Ty.t * (string * ('f, 'r) t) list
  | Fn of 'f
  | Residual of 'r


exception Fail of string * string * Diagnostic.span option

let fail code msg = raise (Fail (code, msg, None))
let failf code fmt = Printf.ksprintf (fail code) fmt

(* ---- hash: bit-exact port of the study's [hash] (iteration.md 2.2) ---- *)

let to_uint32 x =
  if not (Float.is_finite x) then 0
  else
    let m = Float.rem (Float.trunc x) 4294967296. in
    int_of_float (if m < 0. then m +. 4294967296. else m)

let imul a b = a * b land 0xFFFFFFFF

let hash xs =
  let h = ref 0x9e3779b9 in
  List.iter (fun x ->
    let k = to_uint32 (Float.floor (x *. 1000003.)) in
    h := imul (!h lxor k) 0x85ebca6b;
    h := !h lxor (!h lsr 13);
    h := imul !h 0xc2b2ae35;
    h := !h lxor (!h lsr 16)) xs;
  float_of_int (!h mod 1_000_000) /. 1_000_000.

(* ---- numbers ---- *)

(* ponytail: [Int] is an OCaml int but int arithmetic runs on doubles and comes back through
   [to_int], so results beyond 2^62 are an E_NONFINITE error where the study would go inexact. *)
let round x = Float.floor (x +. 0.5)
let to_int name x =
  if Float.is_finite x && Float.abs x < 4e18 then int_of_float x
  else failf "E_NONFINITE" "%s produced a nonfinite value." name
let fin name r =
  if Float.is_finite r then r else failf "E_NONFINITE" "%s produced a nonfinite value." name
let num = function
  | Int n -> float_of_int n | Float f -> f | Bool b -> if b then 1. else 0.
  | _ -> fail "E_TYPE" "Expected a number."
let truthy = function
  | Bool b -> b | Int n -> n <> 0 | Float f -> f <> 0.
  | _ -> fail "E_TYPE" "Expected a bool."
let int_of v = to_int "int" (round (num v))

(* JS [(+x).toFixed(4)] then [String]: up to 4 decimals, trailing zeros removed;
   an exact tie rounds away from zero, as [toFixed] does (printf would round to even). *)
let fmt4 x =
  if Float.is_nan x then "NaN"
  else if not (Float.is_finite x) then (if x > 0. then "Infinity" else "-Infinity")
  else begin
    let ax = Float.abs x in
    let s40 = Printf.sprintf "%.40f" ax in
    let dot = String.index s40 '.' in
    let tail = String.sub s40 (dot + 1) 40 in
    let tie = tail.[4] = '5' && String.for_all (( = ) '0') (String.sub tail 5 35) in
    let s = Printf.sprintf "%.4f" (if tie then ax +. 1e-6 else ax) in
    let n = ref (String.length s) in
    while s.[!n - 1] = '0' do decr n done;
    if s.[!n - 1] = '.' then decr n;
    let s = String.sub s 0 !n in
    if x < 0. && s <> "0" then "-" ^ s else s
  end

let rec ty_of = function
  | Int _ -> Ty.Int | Float _ -> Ty.Float | Bool _ -> Ty.Bool | Text _ -> Ty.Text
  | Vec3 _ -> Ty.Vec3
  | List xs -> Ty.List (elem_ty xs)
  | Float_array _ -> Ty.Array Ty.Float
  | Vec3_array _ -> Ty.Array Ty.Vec3
  | Record fs -> Ty.Record (List.map (fun (n, v) -> (n, ty_of v)) fs)
  | Deferred (ty, _) -> ty
  | No_geo -> Ty.geometry
  | Struct (_, ty, _) -> ty
  | Fn _ -> Ty.Fn
  | Residual _ -> Ty.Any
and elem_ty xs =
  Array.fold_left (fun t x -> match Ty.join t (ty_of x) with Some j -> j | None -> t) Ty.Any xs

(* [need]: convert a value to a wanted static type (a residual is left for its own evaluation) *)
let rec coerce_to want v =
  match want, v with
  | Ty.Any, _ | _, Residual _ -> v
  | Ty.Int, Float f -> Int (to_int "int" (round f))
  | Ty.Int, Bool b -> Int (if b then 1 else 0)
  | Ty.Float, Int n -> Float (float_of_int n)
  | Ty.Float, Bool b -> Float (if b then 1. else 0.)
  | Ty.Bool, (Int _ | Float _) -> Bool (truthy v)
  | Ty.Vec3, (Int _ | Float _) -> let f = num v in Vec3 (f, f, f)
  | Ty.List e, List xs -> List (Array.map (coerce_to e) xs)
  | Ty.Record wf, Record fs ->
      Record (List.map (fun (n, x) -> match List.assoc_opt n wf with
        | Some w -> (n, coerce_to w x) | None -> (n, x)) fs)
  | _ -> v

let rec show_with conc v =
  match conc v with
  | Int n -> string_of_int n
  | Float f -> fmt4 f
  | Bool b -> if b then "true" else "false"
  | Text s -> s
  | Vec3 (x, y, z) -> "[" ^ String.concat " " [ fmt4 x; fmt4 y; fmt4 z ] ^ "]"
  | List xs -> "[" ^ String.concat " " (List.map (show_with conc) (Array.to_list xs)) ^ "]"
  | Float_array xs -> Printf.sprintf "%d × float" (Array.length xs)
  | Vec3_array xs -> Printf.sprintf "%d × vec3" (Array.length xs / 3)
  | Record fs ->
      "{" ^ String.concat " " (List.map (fun (k, x) -> ":" ^ k ^ " " ^ show_with conc x) fs) ^ "}"
  | Residual _ -> "?"
  | v -> Ty.to_string (ty_of v)

let rec key_of ~residual = function
  | Int n -> "i" ^ string_of_int n
  | Float f -> Printf.sprintf "f%h" f
  | Bool b -> if b then "T" else "F"
  | Text s -> Printf.sprintf "s%d:%s" (String.length s) s
  | Vec3 (a, b, c) -> Printf.sprintf "v%h,%h,%h" a b c
  | List xs -> "[" ^ String.concat "," (List.map (key_of ~residual) (Array.to_list xs)) ^ "]"
  | Float_array xs -> "A" ^ Marshal.to_string xs []
  | Vec3_array xs -> "V" ^ Marshal.to_string xs []
  | Record fs -> "{" ^ String.concat "," (List.map (fun (n, v) -> n ^ "=" ^ key_of ~residual v) fs) ^ "}"
  | Deferred ((Ty.Named "geometry"), n) -> "g" ^ string_of_int n
  | Deferred ((Ty.Named "image"), n) -> "image:" ^ string_of_int n
  | Deferred (ty, n) -> "node:" ^ Ty.to_string ty ^ ":" ^ string_of_int n
  | No_geo -> "G"
  | Struct (n, _, fs) -> "S" ^ n ^ key_of ~residual (Record fs)
  | Fn _ -> "fn"
  | Residual r -> "r" ^ string_of_int (residual r)

let comps = function Vec3 (x, y, z) -> (x, y, z) | v -> let s = num v in (s, s, s)
let is_vec = function Vec3 _ -> true | _ -> false

let arith name f a b =
  if is_vec a || is_vec b then begin
    let ax, ay, az = comps a and bx, by, bz = comps b in
    Vec3 (fin name (f ax bx), fin name (f ay by), fin name (f az bz))
  end else begin
    let r = fin name (f (num a) (num b)) in
    match a, b with
    | Int _, Int _ when name <> "/" && name <> "pow" -> Int (to_int name (round r))
    | _ -> Float r
  end

let list_arg = function
  | List xs -> xs
  | Deferred ((Ty.Named "geometry"), _) -> fail "E_TYPE" "A loop over geometry yields its merged geometry, not a list; give it to sop/merge."
  | _ -> fail "E_TYPE" "Expected a list."

let array_length = function
  | Float_array xs -> Array.length xs
  | Vec3_array xs when Array.length xs mod 3 = 0 -> Array.length xs / 3
  | Vec3_array _ -> fail "E_ARRAY_TYPE" "Packed vec3 storage has three coordinates per element."
  | _ -> fail "E_ARRAY_TYPE" "Expected a packed array."
let array_get xs index =
  if index < 0 || index >= array_length xs then fail "E_ARRAY_RANGE" "Array index is outside its length.";
  match xs with
  | Float_array xs -> Float xs.(index)
  | Vec3_array xs -> let i = index * 3 in Vec3 (xs.(i), xs.(i + 1), xs.(i + 2))
  | _ -> assert false
let array_init ty count f =
  if ty <> Ty.Float && ty <> Ty.Vec3 && ty <> Ty.Any then
    fail "E_ARRAY_TYPE" "Packed arrays contain float or vec3 values.";
  let width = if ty = Ty.Vec3 then 3 else 1 in
  if count < 0 || count > Sys.max_floatarray_length / width then
    fail "E_ARRAY_RANGE" "Array length is outside native storage bounds.";
  let data = Array.make (count * width) 0. in
  for i = 0 to count - 1 do
    let v = f i in
    if width = 1 then data.(i) <- fin "array" (num v) else
      let x, y, z = comps v in
      data.(3 * i) <- fin "array" x; data.(3 * i + 1) <- fin "array" y; data.(3 * i + 2) <- fin "array" z
  done;
  if width = 3 then Vec3_array data else Float_array data
let rec validate = function
  | Float f -> ignore (fin "input" f)
  | Vec3 (x, y, z) -> List.iter (fun x -> ignore (fin "input" x)) [x; y; z]
  | Float_array xs | Vec3_array xs as v ->
      ignore (array_length v); Array.iter (fun x -> ignore (fin "array input" x)) xs
  | List xs -> Array.iter validate xs
  | Record fs | Struct (_, _, fs) -> List.iter (fun (_, v) -> validate v) fs
  | _ -> ()
