module Which_key = struct
  open Editor.Keymap

  let panel ui keymap ~focus ~focus_name =
    let module Ui = Pxui.Ui in
    let theme = Ui.theme ui in
    let row binding =
      let key = match binding.trigger with
        | Leader key -> String.make 1 key
        | Chord (Prismel.Input.KeyChar key, modifiers) ->
            (if List.mem Prismel.Input.Meta modifiers then "⌘"
             else if List.mem Prismel.Input.Ctrl modifiers then "Ctrl-" else "")
            ^ String.make 1 key
        | Chord (Prismel.Input.Delete, _) -> "Del"
        | Chord (Prismel.Input.Backspace, _) -> "⌫"
        | Chord (Prismel.Input.Home, _) -> "Home"
        | Chord _ -> "Key" in
      let box = Ui.box ui ~w:Ui.Grow ~h:(Ui.Px (float_of_int (Ui.row_height ui)))
          ("leader-" ^ key) in
      Ui.draw ui box (fun paint (x, y, _, h) ->
        let y = y +. Float.max 5. ((h -. float_of_int (Ui.font_size ui) -. 3.) /. 2.) in
        Ui.Paint.text paint ~at:(x +. 8., y) ~color:theme.accent key;
        Ui.Paint.text paint ~at:(x +. 68., y) ~color:theme.foreground binding.label) in
    let section title scope =
      match List.filter (fun binding -> binding.scope = scope) keymap with
      | [] -> ()
      | bindings -> Ui.label ui title; List.iter row bindings in
    ignore (Ui.modal ui ~width:300. "leader" (fun () ->
      section "Leader · global" None;
      section focus_name (Some focus)))
end

module Status_bar = struct
  let draw ui ~bounds:(x, y, width, height) ~text ~fps =
    if height > 0 then begin
      let module Ui = Pxui.Ui in
      let box = Ui.box ui ~w:(Ui.Px (float_of_int width))
          ~h:(Ui.Px (float_of_int height))
          ~at:(float_of_int x, float_of_int y) "workspace-status" in
      let fps = match fps with
        | Some fps -> Printf.sprintf " · %d fps" fps | None -> "" in
      let theme = Ui.theme ui in
      Ui.draw ui box (fun paint _ ->
        Ui.Paint.fill paint ~x:(float_of_int x) ~y:(float_of_int y)
          ~w:(float_of_int width) ~h:(float_of_int height) theme.foreground;
        let at = float_of_int (x + 10), float_of_int (y + 8) in
        Ui.Paint.text paint ~at ~size:11 ~color:theme.input text;
        Ui.Paint.text paint
          ~at:(fst at +. Ui.Paint.text_width paint ~size:11 text, snd at)
          ~size:11 ~color:theme.input fps)
    end
end
