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
