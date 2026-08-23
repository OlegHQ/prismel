let fail format = Printf.ksprintf failwith format

let contains needle haystack =
  let n = String.length needle and h = String.length haystack in
  let rec loop offset =
    offset + n <= h && (String.sub haystack offset n = needle || loop (offset + 1))
  in
  loop 0

let () =
  if Array.length Sys.argv <> 2 then fail "usage: %s INVENTORY" Sys.argv.(0);
  let selection = Binding_value_record_plan.select (Yojson.Safe.from_file Sys.argv.(1)) in
  let output = Binding_value_record_codegen.generate selection in
  let again = Binding_value_record_codegen.generate selection in
  if output <> again then fail "value-record generation is nondeterministic";
  if List.length selection.records <> 27 || List.length selection.ids <> 135 then
    fail "value-record production batch cardinality drift";
  if not (contains "module MTLAccelerationStructureMotionInstanceDescriptor" output.ocaml_ml)
  then fail "missing acceleration-structure value record";
  if not (contains "motion_end_time : float" output.ocaml_ml) then
    fail "missing immutable typed field";
  if contains "Private" output.ocaml_ml then fail "private ownership-bearing record escaped";
  if not (contains "static_assert(sizeof(MTLMapIndirectArguments) > 0);" output.native_checks)
  then fail "missing sizeof ABI assertion";
  if not (contains "static_assert(alignof(MTLMapIndirectArguments) > 0);" output.native_checks)
  then fail "missing alignof ABI assertion";
  if not (contains "offsetof(MTLMapIndirectArguments, regionSizeWidth)" output.native_checks)
  then fail "missing offsetof ABI assertion";
  Printf.printf "Metal value records: 27 records + 108 fields = 135 fixed-layout IDs\n%!"
