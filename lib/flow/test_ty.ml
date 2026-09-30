open Flow
open Ty

let ty source = match Syntax.parse source with
  | Ok [form] -> of_syntax form
  | _ -> failwith source

let () =
  (* annotations *)
  assert (ty "float" = Some Float && ty "fn" = Some Fn && ty "geometry" = Some Geometry);
  assert (ty "(list int)" = Some (List Int));
  assert (ty "(list (list vec3))" = Some (List (List Vec3)));
  assert (ty "{:shape geometry :y float}" = Some (Record ["shape", Geometry; "y", Float]));
  assert (ty "{}" = Some (Record []));
  List.iter (fun source -> assert (ty source = None))
    ["any"; "color"; "flot"; "(list)"; "(list int int)"; "{:a}"; "{:a int :a int}";
     "{:A int}"; "{a int}"; "(vec int)"; "3"];
  (* the study's string spelling round-trips *)
  let t = Record ["a", List (Record ["b", Int; "c", List Float]); "d", Text] in
  assert (to_string t = "rec{a:list:rec{b:int,c:list:float},d:text}");
  List.iter (fun t -> assert (of_string (to_string t) = Some t))
    [Geometry; Float; Int; Bool; Vec3; Text; Color; Fn; Any; Scene; World; Settings;
     Panel; Editor; List Int; t; Record []];
  List.iter (fun s -> assert (of_string s = None)) ["nope"; "list:"; "rec{a:int"; "int,"]

let () =
  assert (has_fn Fn && has_fn (List Fn) && has_fn (Record ["f", Fn])
    && not (has_fn (List Int)) && not (has_fn Any));
  (* fits *)
  assert (fits Int Float && fits Float Int && fits Int Bool && fits Bool Float);
  assert (fits Int Vec3 && not (fits Bool Vec3) && not (fits Vec3 Float));
  assert (fits Text Color && fits Vec3 Color && not (fits Float Color));
  assert (fits Any Geometry && fits Geometry Any && not (fits Geometry Float));
  assert (fits (List Int) (List Float) && not (fits (List Geometry) (List Float)));
  assert (fits (List Any) (List Int));
  assert (fits (Record ["a", Int; "b", Text]) (Record ["a", Float]));
  assert (not (fits (Record ["a", Int]) (Record ["a", Int; "b", Int])));
  assert (not (fits (List Int) Int) && not (fits Int (List Int)));
  (* coerce *)
  assert (coerce Int Float = Float && coerce Float Int = Int && coerce Float Bool = Bool);
  assert (coerce Int Vec3 = Vec3 && coerce Bool Vec3 = Bool);
  assert (coerce (List Int) (List Float) = List Float);
  assert (coerce (Record ["a", Int; "b", Text]) (Record ["a", Float])
    = Record ["a", Float; "b", Text]);
  assert (coerce Text Any = Text && coerce Any Float = Any && coerce Geometry Float = Geometry);
  (* join and unify *)
  assert (join Int Int = Some Int && join Int Float = Some Float);
  assert (join Any Text = Some Text && join Vec3 Any = Some Vec3);
  assert (join Text Geometry = None && join Int Bool = None);
  assert (join (List Int) (List Float) = Some (List Float));
  assert (join (Record ["a", Int; "b", Text]) (Record ["b", Text; "a", Float])
    = Some (Record ["a", Float; "b", Text]));
  assert (join (Record ["a", Int]) (Record ["b", Int]) = None);
  assert (join (Record ["a", Int]) (Record ["a", Text]) = None);
  assert (unify Int Bool = Some Int && unify Geometry Text = None);
  assert (elem (List Int) = Some Int && elem Int = None)
