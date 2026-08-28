include Scene_command.Debug_font

let draw ~target ~blend ~x ~y ~color text =
  let length = String.length text in
  if length > max_text_length then Error Text_too_long else begin
    let stop = ref length and index = ref 0 in
    while !index < !stop do
      if text.[!index] = '\000' then stop := !index else incr index
    done;
    for character = 0 to !stop - 1 do
      let origin_x = x + (character * width) in
      for row = 0 to height - 1 do
        let destination_y = y + row in
        if destination_y >= 0 && destination_y < Surface.height target then begin
          let bits = glyph_row text.[character] row in
          for column = 0 to width - 1 do
            let destination_x = origin_x + column in
            if bits land (0x80 lsr column) <> 0 && destination_x >= 0
               && destination_x < Surface.width target then
              Composite.pixel target ~blend ~x:destination_x ~y:destination_y color
          done
        end
      done
    done;
    Ok ()
  end
