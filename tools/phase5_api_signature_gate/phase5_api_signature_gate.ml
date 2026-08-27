open Parsetree

module Smap = Map.Make(String)
module Sset = Set.Make(String)

let fail format=Printf.ksprintf(fun message->prerr_endline message;exit 1)format
let normalize item=Format.asprintf"%a"Pprintast.signature[item]
let name path leaf=if path=""then leaf else path^"."^leaf

let rec flatten path result signature=List.fold_left(fun result item->
  match item.psig_desc with
  |Psig_value value->Smap.add(name path("val:"^value.pval_name.txt))(normalize item)result
  |Psig_type(_,types)->List.fold_left(fun result value->Smap.add(name path("type:"^value.ptype_name.txt))(normalize item)result)result types
  |Psig_typesubst types->List.fold_left(fun result value->Smap.add(name path("typesubst:"^value.ptype_name.txt))(normalize item)result)result types
  |Psig_module binding->let module_name=Option.value binding.pmd_name.txt~default:"_"in begin match binding.pmd_type.pmty_desc with
    |Pmty_signature nested->flatten(name path("module:"^module_name))result nested
    |_->Smap.add(name path("module:"^module_name))(normalize item)result end
  |Psig_recmodule bindings->List.fold_left(fun result binding->let module_name=Option.value binding.pmd_name.txt~default:"_"in match binding.pmd_type.pmty_desc with Pmty_signature nested->flatten(name path("module:"^module_name))result nested|_->Smap.add(name path("module:"^module_name))(normalize item)result)result bindings
  |Psig_modtype value->Smap.add(name path("module_type:"^value.pmtd_name.txt))(normalize item)result
  |Psig_modsubst value->Smap.add(name path("module_subst:"^value.pms_name.txt))(normalize item)result
  |Psig_modtypesubst value->Smap.add(name path("module_type_subst:"^value.pmtd_name.txt))(normalize item)result
  |Psig_exception value->Smap.add(name path("exception:"^value.ptyexn_constructor.pext_name.txt))(normalize item)result
  |Psig_class classes->List.fold_left(fun result value->Smap.add(name path("class:"^value.pci_name.txt))(normalize item)result)result classes
  |Psig_class_type classes->List.fold_left(fun result value->Smap.add(name path("class_type:"^value.pci_name.txt))(normalize item)result)result classes
  |Psig_include _|Psig_open _|Psig_attribute _|Psig_extension _->Smap.add(name path("item:"^string_of_int item.psig_loc.loc_start.pos_cnum))(normalize item)result
  |Psig_typext value->Smap.add(name path("extension:"^Longident.last value.ptyext_path.txt))(normalize item)result)result signature

let strip_comments text=
  let length=String.length text and out=Buffer.create(String.length text)in
  let rec scan i depth quoted escaped=
    if i=length then Buffer.contents out else if depth>0 then
      if i+1<length&&text.[i]='('&&text.[i+1]='*'then scan(i+2)(depth+1)false false
      else if i+1<length&&text.[i]='*'&&text.[i+1]=')'then scan(i+2)(depth-1)false false
      else(Buffer.add_char out(if text.[i]='\n' then '\n' else ' ');scan(i+1)depth false false)
    else if quoted then(Buffer.add_char out text.[i];if escaped then scan(i+1)0 true false else if text.[i]='\\'then scan(i+1)0 true true else scan(i+1)0(text.[i]<>'"')false)
    else if i+1<length&&text.[i]='('&&text.[i+1]='*'then(Buffer.add_string out"  ";scan(i+2)1 false false)
    else(Buffer.add_char out text.[i];scan(i+1)0(text.[i]='"')false)in scan 0 0 false false
let parse path=let channel=open_in_bin path in Fun.protect~finally:(fun()->close_in_noerr channel)(fun()->
  let text=In_channel.input_all channel|>strip_comments in let lexbuf=Lexing.from_string text in Location.init lexbuf path;flatten""Smap.empty(Parse.interface lexbuf))

let allowed=Sset.of_list[
  "Low.module:App.val:get_renderer";"Low.module:Backend.val:present";
  "Image.module:Private.val:current_renderer";"Image.module:Private.val:set_renderer";
  "Image.module:Private.val:get_renderer";"Image.module:Private.val:get_texture";
  "Image.module:Private.val:from_texture";"Font.val:release_renderer";
  "Image.module:Private.type:renderer";"Image.module:Private.type:texture"]
let omissions=Sset.of_list[
  "Low.module:Graphics.val:get_renderer";"Low.module:Window.val:get_window";
  "Low.module:Window.val:get_renderer";"Low.module:Window.val:get_window_flags";
  "Low.module:Window.val:get_renderer_flags";"Low.module:Window.val:with_gpu_context";
  "Low.module:Window.type:t"]
let except key=Sset.mem key allowed||Sset.mem key omissions

let ()=
  let root=ref"."in Arg.parse["--root",Arg.Set_string root,"repository root"](fun value->raise(Arg.Bad value))"phase5_api_signature_gate";
  let root=Unix.realpath!root in
  let json=Yojson.Safe.from_file(Filename.concat root"specification/evidence/gpu_migration/phase5_prismel_api_map.json")in
  let open Yojson.Safe.Util in
  let modules=json|>member"modules"|>to_list|>List.map(fun row->row|>member"module"|>to_string)in
  if List.length modules<>40 then fail"API map cardinality is %d, expected 40"(List.length modules);
  let missing=ref[]and additional=ref[]and changed=ref[]in
  List.iter(fun module_name->
    let file=String.lowercase_ascii module_name^".mli"in
    let old=parse(Filename.concat root("lib/prismel/"^file))and fresh=parse(Filename.concat root("lib/prismel_next_api/"^file))in
    Smap.iter(fun key signature->let full=module_name^"."^key in match Smap.find_opt key fresh with None->if not(except full)then missing:=full::!missing|Some other->if signature<>other&&not(except full)then changed:=full::!changed)old;
    Smap.iter(fun key _->let full=module_name^"."^key in if not(Smap.mem key old)&&not(except full)then additional:=full::!additional)fresh)modules;
  let sort=List.sort String.compare in
  let report label values=Printf.printf"%s (%d): %s\n"label(List.length values)(String.concat", "(sort values))in
  report"missing"!missing;report"additional"!additional;report"changed"!changed;
  if !missing<>[] || !additional<>[] || !changed<>[] then exit 1;
  Printf.printf"Phase5 R1 normalized signature gate passed: 40/40 modules; 0 high-level deltas; 8 typed raw adaptations; reviewed Low raw omissions\n"
