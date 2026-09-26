open Runtime_resources
let get=function Ok x->x|Error e->failwith(Format.asprintf"%a"pp_error e)
let run () =
  let font=get(Font.open_system~size:14.)in
  get(Font.set_style font[Font.Bold;Italic]);get(Font.set_outline font 0);
  get(Font.set_hinting font Font.Light_hinting);get(Font.set_kerning font true);
  let metrics=get(Font.glyph_metrics font(Char.code 'A'))in if metrics.advance<=0 then failwith"glyph metrics";
  if get(Font.render font~density:1~color:(255,255,255,255)"")<>None then failwith"empty text";
  (match Font.render font~density:1~color:(255,255,255,255)"\xc0\x80"with Error{kind=Invalid_argument;_}->()|_->failwith"UTF-8");
  let explicit=Option.get(get(Font.cached_text font~density:2~color:(255,0,0,255)"explicit"))in
  let width,height=get(Text.size explicit)in if width<=0||height<=0 then failwith"explicit text";
  let transferred=Option.get(get(Font.render font~density:1~color:(255,255,255,255)"transfer"))in
  let expected=get(Text.pixels transferred)in
  let image=get(Text.Private.into_image transferred)in
  if not(Text.destroyed transferred)||get(Image.pixels image)<>expected then
    failwith"text-to-image ownership transfer changed pixels";
  Bytes.fill expected 0(Bytes.length expected)'\000';
  if get(Image.pixels image)=expected then
    failwith"public text pixels still alias the transferred image";
  get(Text.destroy transferred);get(Image.destroy image);
  get(Font.set_outline font 1);
  get(Font.destroy font);
  if Text.destroyed explicit || get(Text.size explicit)<>(width,height) then
    failwith"font mutation or teardown shortened text lifetime";
  get(Text.destroy explicit);
  (match Font.render font~density:1~color:(0,0,0,0)"dead"with Error{kind=Destroyed;_}->()|_->failwith"stale font");
  print_endline"runtime_resources Font: UTF8 density owned text lifetime passed"
