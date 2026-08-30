type stats = {
  command_capacity : int;
  command_length : int;
  high_water : int;
  growths : int;
}

type t = {
  id : int64;
  version : int64;
  ir : Render_ir.t;
  source_bytes : int;
}
type segment = t

module Builder = struct
  type published = { id : int64; version : int64; value : t }

  type t = {
    mutable opcodes : bytes;
    mutable values : float array;
    mutable colors : int32 array;
    mutable texts : string array;
    mutable length : int;
    mutable high_water : int;
    mutable growths : int;
    mutable published : published option;
  }

  let minimum_capacity = 16

  let create ?(capacity = minimum_capacity) () =
    let capacity = max minimum_capacity capacity in
    { opcodes = Bytes.make capacity '\000';
      values = Array.make (capacity * 6) 0.;
      colors = Array.make capacity Int32.zero;
      texts = Array.make capacity "";
      length = 0; high_water = 0; growths = 0; published = None }

  let reset value =
    Array.fill value.texts 0 value.length "";
    value.length <- 0;
    value.published <- None

  let ensure value =
    if value.length = Bytes.length value.opcodes then begin
      let old_capacity = value.length in
      let capacity = old_capacity * 2 in
      let opcodes = Bytes.make capacity '\000' in
      Bytes.blit value.opcodes 0 opcodes 0 old_capacity;
      value.opcodes <- opcodes;
      let values = Array.make (capacity * 6) 0. in
      Array.blit value.values 0 values 0 (old_capacity * 6);
      value.values <- values;
      let colors = Array.make capacity Int32.zero in
      Array.blit value.colors 0 colors 0 old_capacity;
      value.colors <- colors;
      let texts = Array.make capacity "" in
      Array.blit value.texts 0 texts 0 old_capacity;
      value.texts <- texts;
      value.growths <- value.growths + 1
    end

  let append value opcode ~x ~y ~width ~height ~color ~text =
    ensure value;
    let index = value.length and offset = value.length * 6 in
    Bytes.unsafe_set value.opcodes index (Char.chr opcode);
    Array.unsafe_set value.values offset x;
    Array.unsafe_set value.values (offset + 1) y;
    Array.unsafe_set value.values (offset + 2) width;
    Array.unsafe_set value.values (offset + 3) height;
    Array.unsafe_set value.colors index color;
    Array.unsafe_set value.texts index text;
    value.length <- index + 1;
    value.high_water <- max value.high_water value.length;
    value.published <- None

  let finite4 x y width height =
    Float.is_finite x && Float.is_finite y && Float.is_finite width
    && Float.is_finite height

  let solid_rect value ~x ~y ~width ~height ~color =
    if not (finite4 x y width height) || width < 0. || height < 0. then
      invalid_arg "Display_list.solid_rect: invalid extent";
    append value 0 ~x ~y ~width ~height ~color ~text:""

  let push_clip value ~x ~y ~width ~height =
    if not (finite4 x y width height) || width < 0. || height < 0. then
      invalid_arg "Display_list.push_clip: invalid extent";
    append value 1 ~x ~y ~width ~height ~color:Int32.zero ~text:""

  let pop_clip value =
    append value 2 ~x:0. ~y:0. ~width:0. ~height:0.
      ~color:Int32.zero ~text:""

  let debug_text value ~x ~y ~color text =
    if not (Float.is_finite x && Float.is_finite y)
       || String.length text > 65_536 then
      invalid_arg "Display_list.debug_text: invalid text";
    append value 3 ~x ~y ~width:0. ~height:0. ~color ~text

  let command value index =
    let offset = index * 6 in
    let x = Array.unsafe_get value.values offset
    and y = Array.unsafe_get value.values (offset + 1)
    and width = Array.unsafe_get value.values (offset + 2)
    and height = Array.unsafe_get value.values (offset + 3) in
    match Char.code (Bytes.unsafe_get value.opcodes index) with
    | 0 ->
        Render_ir.Geometry
          { vertices = [|x; y; x +. width; y; x +. width; y +. height;
                         x; y +. height|];
            indices = [|0; 1; 2; 0; 2; 3|];
            color = Array.unsafe_get value.colors index }
    | 1 -> Render_ir.Push_clip { x; y; width; height }
    | 2 -> Render_ir.Pop_clip
    | 3 -> Render_ir.Debug_text
        { x; y; color = Array.unsafe_get value.colors index;
          text = Array.unsafe_get value.texts index }
    | _ -> assert false

  let publish value ~id ~version =
    if id <= 0L then invalid_arg "Display_list.publish: ID must be positive";
    if version < 0L then
      invalid_arg "Display_list.publish: version must be non-negative";
    match value.published with
    | Some published when published.id = id && published.version = version ->
        Ok published.value
    | _ ->
        let commands = Array.init value.length (command value) in
        match Render_ir.Private.create_owned commands with
        | Error error -> Error error
        | Ok ir ->
            let source_bytes = Bytes.length value.opcodes
              + (Array.length value.values * (Sys.word_size / 8))
              + (Array.length value.colors * 4) in
            let segment = { id; version; ir; source_bytes } in
            value.published <- Some { id; version; value = segment };
            Ok segment

  let stats value =
    { command_capacity = Bytes.length value.opcodes;
      command_length = value.length; high_water = value.high_water;
      growths = value.growths }
end

let id value = value.id
let version value = value.version
let source_bytes value = value.source_bytes
let render_ir value = value.ir
