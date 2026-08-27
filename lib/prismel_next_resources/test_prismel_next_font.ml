open Prismel_next_resources
let get=function Ok x->x|Error e->failwith(Format.asprintf"%a"pp_error e)
let ()=
  let font=get(Font.open_system~size:14.)in
  get(Font.set_style font[Font.Bold;Italic]);get(Font.set_outline font 0);
  get(Font.set_hinting font Font.Light_hinting);get(Font.set_kerning font true);
  let metrics=get(Font.glyph_metrics font(Char.code 'A'))in if metrics.advance<=0 then failwith"glyph metrics";
  if get(Font.render font~density:1~color:(255,255,255,255)"")<>None then failwith"empty text";
  (match Font.render font~density:1~color:(255,255,255,255)"\xc0\x80"with Error{kind=Invalid_argument;_}->()|_->failwith"UTF-8");
  let explicit=Option.get(get(Font.cached_text font~density:2~color:(255,0,0,255)"explicit"))in
  let width,height=get(Text.size explicit)in if width<=0||height<=0 then failwith"explicit text";
  for index=0 to 299 do ignore(get(Font.render_cached font~renderer:7~density:(if index land 1=0 then 1 else 2)~color:(255,255,255,255)(string_of_int index)))done;
  if Font.cache_entries font~renderer:7<>256 then failwith"font LRU bound";
  for _=1 to 100_000 do ignore(get(Font.render_cached font~renderer:7~density:2~color:(255,255,255,255)"299"))done;
  get(Font.release_renderer font~renderer:7);if Font.cache_entries font~renderer:7<>0 then failwith"renderer release";
  if Text.destroyed explicit then failwith"LRU shortened explicit lifetime";
  get(Text.destroy explicit);get(Font.destroy font);
  (match Font.render font~density:1~color:(0,0,0,0)"dead"with Error{kind=Destroyed;_}->()|_->failwith"stale font");
  print_endline"prismel_next_resources Font: UTF8 density LRU256 explicit 100k passed"
