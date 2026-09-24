let () =
  let path=Filename.temp_file "strata-preview-" ".ml" in
  Fun.protect ~finally:(fun ()->Sys.remove path) (fun () ->
    let out=open_out_bin path in
    output_string out "module A = struct\n\tlet value = 7\nend\n";
    close_out out;
    let source=Symbol_preview.load ~root:"/" ~path None in
    if source.error<>None then failwith "source load";
    if Symbol_preview.excerpt source ~first:1 ~last:99<>
       [|2,"    let value = 7";3,"end"|] then failwith "source range/line numbers";
    if Symbol_preview.excerpt source ~first:99 ~last:100<>[||] then failwith "range beyond file";
    if Symbol_preview.load ~root:"/" ~path (Some source)!=source then failwith "hover file was reread";
    if Symbol_preview.density 1>=Symbol_preview.density 50 ||
       Symbol_preview.density 100000<>89 then failwith "span density scale";
    if Symbol_preview.shorten 5 "abcλxyz"<>"ab..." then failwith "UTF-8 truncation";
    if Symbol_preview.shorten 7 "abcλxyz"<>"abc..." then failwith "split UTF-8 code point");
  print_endline "symbol preview: source ranges, line numbers, file reuse, density and UTF-8"
