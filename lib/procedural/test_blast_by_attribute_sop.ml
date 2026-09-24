open Pdk
open Procedural

let fail message = raise (Failure message)
let check condition message = if not condition then fail message
let get = function Ok value -> value | Error _ -> fail "unexpected error"
let context domains = Context.create ~domains ~grain:257 ~seed:103L () |> get

let contains text pattern =
  let rec search offset = offset + String.length pattern <= String.length text
      && (String.sub text offset (String.length pattern) = pattern
          || search (offset + 1)) in
  pattern = "" || search 0

let source () =
  let geometry = Ops.grid ~columns:260 ~rows:160 ~size:12. () |> function
    | Ok value -> value
    | Error error -> fail (Error.to_string error) in
  let point_count = Geometry.point_count geometry
  and primitive_count = Geometry.primitive_count geometry in
  let density = Attribute.create_owned ~owner:Attribute.Point ~name:"density"
      (Attribute.Float (Array.init point_count (fun point ->
        float_of_int (point mod 1_009) /. 1_008.))) |> Result.get_ok
  and class_ = Attribute.create_owned ~owner:Attribute.Primitive ~name:"class"
      (Attribute.Int (Array.init primitive_count (fun primitive ->
        (primitive * 17) mod 1_009))) |> Result.get_ok
  and base = Group.init ~grain:257 ~owner:Group.Primitive ~name:"base"
      primitive_count (fun primitive -> primitive mod 5 <> 0) in
  geometry |> Geometry.with_attribute density |> Result.get_ok
  |> Geometry.with_attribute class_ |> Result.get_ok
  |> Geometry.with_group base |> Result.get_ok

let cook domains graph =
  let session = Session.create ~max_entries:8 ~max_payload_bytes:180_000_000
      |> get in
  let result = Session.cook session ~context:(context domains) graph in
  Session.close session;
  match result with
  | Ok output -> output.geometry
  | Error error -> fail (Diagnostic.error_to_string error)

let group_bits owner name geometry =
  match Geometry.find_group ~owner name geometry with
  | None -> fail ("missing group " ^ name)
  | Some group ->
      Array.init (Group.length group) (fun element -> Group.mem element group)

let () =
  let graph = Sop.snapshot (source ())
      |> Sop.blast_by_attribute ~group:"base" ~invert:true
           ~owner:Pdk.Ops.Blast_primitives ~attribute:"class"
           ~mode:(Pdk.Ops.Blast_range { minimum = 250.; maximum = 750. })
           ~output:(Pdk.Ops.Blast_group "picked") in
  let parameters = Node.parameters graph in
  check (contains parameters "owner=primitives"
      && contains parameters "attribute=class"
      && contains parameters "mode=range"
      && contains parameters "output=group:picked"
      && contains parameters "group=base"
      && contains parameters "invert=true")
    "Blast by Attribute SOP cache identity";
  let one = cook 1 graph and four = cook 4 graph in
  check (group_bits Group.Primitive "picked" one
      = group_bits Group.Primitive "picked" four)
    "Blast by Attribute SOP one/four-domain group exactness";
  let deleted = Sop.snapshot (source ())
      |> Sop.blast_by_attribute ~remove_unused_points:true
           ~owner:Pdk.Ops.Blast_primitives ~attribute:"class"
           ~mode:(Pdk.Ops.Blast_below 400.) ~output:Pdk.Ops.Blast_delete in
  let one = cook 1 deleted and four = cook 4 deleted in
  check (Geometry.point_count one = Geometry.point_count four
      && Geometry.vertex_count one = Geometry.vertex_count four
      && Geometry.primitive_count one = Geometry.primitive_count four)
    "Blast by Attribute SOP one/four-domain deletion cardinality";
  let missing = Sop.snapshot (source ())
      |> Sop.blast_by_attribute ~group:"missing"
           ~owner:Pdk.Ops.Blast_primitives ~attribute:"class"
           ~mode:(Pdk.Ops.Blast_below 400.) ~output:Pdk.Ops.Blast_delete in
  let session = Session.create ~max_entries:4 ~max_payload_bytes:90_000_000
      |> get in
  (match Session.cook session ~context:(context 1) missing with
   | Error error -> check (error.code = "missing_group")
       "Blast by Attribute SOP missing-group diagnostic"
   | Ok _ -> fail "Blast by Attribute SOP accepted missing base group");
  let missing_attribute = Sop.snapshot (source ())
      |> Sop.blast_by_attribute ~owner:Pdk.Ops.Blast_points
           ~attribute:"missing" ~mode:(Pdk.Ops.Blast_below 0.)
           ~output:Pdk.Ops.Blast_delete in
  (match Session.cook session ~context:(context 1) missing_attribute with
   | Error error -> check (error.code = "invalid_blast")
       "Blast by Attribute SOP missing-attribute diagnostic"
   | Ok _ -> fail "Blast by Attribute SOP accepted missing attribute");
  Session.close session;
  print_endline "blast by attribute SOP tests passed"
