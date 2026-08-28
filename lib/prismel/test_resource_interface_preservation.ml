open Prismel_next_api
let require condition message=if not condition then failwith message
let read path=In_channel.with_open_bin path In_channel.input_all
let symbols text=let re=Str.regexp"val[ \n\t]+\\([a-zA-Z_][a-zA-Z0-9_]*\\)"in let rec loop at acc=try ignore(Str.search_forward re text at);loop(Str.match_end())(Str.matched_group 1 text::acc)with Not_found->List.sort_uniq String.compare acc in loop 0[]
let ()=
  let legacy=Array.to_list(Array.sub Sys.argv 1 4)and next=Array.to_list(Array.sub Sys.argv 5 4)in
  List.iter2(fun old_path new_path->let old_symbols=symbols(read old_path)and new_symbols=symbols(read new_path)in List.iter(fun name->require(List.mem name new_symbols)(Printf.sprintf"%s missing from %s"name new_path))old_symbols)legacy next;
  require(Result.is_ok(Audio.init()))"audio init";
  let sample=Result.get_ok(Audio.Sample.synth~waveform:Sine~frequency:440.~duration:0.01())in
  let channel=Result.get_ok(Audio.Sample.play sample)in require(Audio.Sample.is_playing channel)"sample playing";Audio.Sample.stop channel;require(not(Audio.Sample.is_playing channel))"sample stopped";Audio.Sample.destroy sample;Audio.shutdown();
  let image=Image.create~width:2~height:3()in require(Image.get_size image=(2,3))"image dimensions";let identity=Image.Private.identity image in let replacement=Image.create~width:1~height:1~color:Color.red()in Image.Private.replace image replacement;require(Image.get_size image=(1,1)&&Image.Private.identity image=identity)"stable replacement";Image.destroy image;
  print_endline"resource-interface-preservation: ok"
