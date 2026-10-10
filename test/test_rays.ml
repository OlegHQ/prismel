open Test_support

(* The runtime's keys must reach the Input keys hosts match on. *)
let run () =
  List.iter (fun (key, expected) ->
    if Rays.Event.Private.key_of_runtime key <> expected then
      fail "a runtime key did not map to its Input key")
    Rays.Input.[ Runtime_input.Arrow_right, ArrowRight; Arrow_left, ArrowLeft;
            Arrow_down, ArrowDown; Arrow_up, ArrowUp; Enter, Enter;
            Escape, Escape; Control, Ctrl; Meta, Meta; Page_up, PageUp;
            Char 'a', KeyChar 'a'; Space, Space; F12, F12;
            Unknown 4242, Unknown 4242 ]
