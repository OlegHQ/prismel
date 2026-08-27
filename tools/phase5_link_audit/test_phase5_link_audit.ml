let run tool deps links report_only=
  let tool=if Filename.is_relative tool&&Filename.dirname tool="."then"./"^tool else tool in
  let output=Filename.temp_file"phase5-link-"".json"in
  let command=Printf.sprintf"%s --deps-file %s --otool-file %s %s > %s"
    (Filename.quote tool)(Filename.quote deps)(Filename.quote links)
    (if report_only then"--report-only"else"")(Filename.quote output)in
  let status=Sys.command command and json=Yojson.Safe.from_file output in Sys.remove output;status,json
let ()=
  if Array.length Sys.argv<>6 then failwith"fixture arguments";
  let clean_status,clean=run Sys.argv.(1)Sys.argv.(2)Sys.argv.(3)false in
  if clean_status<>0||not Yojson.Safe.Util.(clean|>member"passed"|>to_bool)then failwith"clean fixture";
  let legacy_status,legacy=run Sys.argv.(1)Sys.argv.(4)Sys.argv.(5)false in
  if legacy_status=0||Yojson.Safe.Util.(legacy|>member"violations"|>to_list|>List.length)<>4 then failwith"legacy enforcement";
  let report_status,report=run Sys.argv.(1)Sys.argv.(4)Sys.argv.(5)true in
  if report_status<>0||Yojson.Safe.Util.(report|>member"passed"|>to_bool)then failwith"report-only";
  print_endline"Phase5 D2/D3 link audit fixtures: clean pass, legacy fail, report-only passed"
