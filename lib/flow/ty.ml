type t =
  | Geometry | Float | Int | Bool | Vec3 | Text | Color
  | List of t | Record of (string * t) list | Fn | Any
  | Scene | World | Settings | Panel | Editor

let names = [ "geometry", Geometry; "float", Float; "int", Int; "bool", Bool;
  "vec3", Vec3; "text", Text; "color", Color; "fn", Fn; "any", Any;
  "scene", Scene; "world", World; "settings", Settings; "panel", Panel;
  "editor", Editor ]

let rec to_string = function
  | List e -> "list:" ^ to_string e
  | Record fs -> "rec{" ^ String.concat ","
      (List.map (fun (n, t) -> n ^ ":" ^ to_string t) fs) ^ "}"
  | t -> fst (List.find (fun (_, u) -> u = t) names)

let of_string s =
  let n = String.length s in
  let starts i p = i + String.length p <= n && String.sub s i (String.length p) = p in
  let ( let* ) = Option.bind in
  (* each parser returns the type and the next index *)
  let rec ty i =
    if starts i "list:" then
      let* e, j = ty (i + 5) in Some (List e, j)
    else if starts i "rec{" then fields (i + 4) []
    else
      let j = ref i in
      while !j < n && s.[!j] <> ',' && s.[!j] <> '}' do incr j done;
      let* t = List.assoc_opt (String.sub s i (!j - i)) names in
      Some (t, !j)
  and fields i acc =
    if i < n && s.[i] = '}' then Some (Record (List.rev acc), i + 1)
    else
      let* c = String.index_from_opt s i ':' in
      let* t, j = ty (c + 1) in
      let field = (String.sub s i (c - i), t) in
      fields (if j < n && s.[j] = ',' then j + 1 else j) (field :: acc) in
  match ty 0 with Some (t, j) when j = n -> Some t | _ -> None

let field_name = function
  | "" -> false
  | name -> (match name.[0] with 'a' .. 'z' -> true | _ -> false)
    && String.for_all (function 'a' .. 'z' | '0' .. '9' | '_' | '-' -> true | _ -> false) name

let rec of_syntax (x : Syntax.t) = match x.node with
  | Sym name ->
      (match List.assoc_opt name names with
       | Some (Any | Color) | None -> None
       | some -> some)
  | Map items ->
      let rec go seen = function
        | [] -> Some []
        | {Syntax.node = Kw name; _} :: value :: rest
          when field_name name && not (List.mem name seen) ->
            Option.bind (of_syntax value) (fun t ->
              Option.map (fun fs -> (name, t) :: fs) (go (name :: seen) rest))
        | _ -> None in
      Option.map (fun fs -> Record fs) (go [] items)
  | List [{node = Sym "list"; _}; inner] -> Option.map (fun t -> List t) (of_syntax inner)
  | _ -> None

let elem = function List e -> Some e | _ -> None

let rec has_fn = function
  | Fn -> true
  | List e -> has_fn e
  | Record fs -> List.exists (fun (_, t) -> has_fn t) fs
  | _ -> false

let num = function Int | Float -> true | _ -> false

let rec fits have want =
  have = Any || want = Any || have = want
  || (num have && (num want || want = Bool))
  || (have = Bool && num want)
  || (want = Color && (have = Text || have = Vec3))
  || (want = Vec3 && num have)
  || (match have, want with
      | List h, List w -> fits h w
      | Record hs, Record ws ->
          List.for_all (fun (n, w) -> match List.assoc_opt n hs with
            | Some h -> fits h w | None -> false) ws
      | _ -> false)

let rec coerce have want =
  if want = Any || have = Any || have = want then have
  else match have, want with
    | List h, List w -> List (coerce h w)
    | Record hs, Record ws ->
        Record (List.map (fun (n, h) -> match List.assoc_opt n ws with
          | Some w -> (n, coerce h w) | None -> (n, h)) hs)
    | _ when (num have || have = Bool)
        && (num want || want = Bool || (want = Vec3 && have <> Bool)) -> want
    | _ -> have

let rec join a b =
  if a = b then Some a
  else if a = Any then Some b
  else if b = Any then Some a
  else match a, b with
    | (Int | Float), (Int | Float) -> Some Float
    | List x, List y -> Option.map (fun t -> List t) (join x y)
    | Record xs, Record ys
      when List.length xs = List.length ys
        && List.for_all (fun (n, _) -> List.mem_assoc n ys) xs ->
        let fields = List.map (fun (n, x) ->
          (n, join x (List.assoc n ys))) xs in
        if List.for_all (fun (_, t) -> t <> None) fields
        then Some (Record (List.map (fun (n, t) -> (n, Option.get t)) fields))
        else None
    | _ -> None

let unify a b = match join a b with
  | Some _ as joined -> joined
  | None -> if fits a b && fits b a then Some a else None
