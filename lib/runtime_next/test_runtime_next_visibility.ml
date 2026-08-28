let get=function Ok value->value|Error error->failwith(Ogpu.Error.to_string error)
let ()=match Runtime_next.create~width:32~height:24 with
|Error _->print_endline"runtime_next visibility: skipped (no window/Metal device)"
|Ok runtime->Fun.protect~finally:(fun()->ignore(Runtime_next.destroy runtime))(fun()->
    if get(Runtime_next.visible runtime)then failwith"native window was not initially hidden";
    get(Runtime_next.show runtime);
    if not(get(Runtime_next.visible runtime))then failwith"show did not set visible flag";
    get(Runtime_next.hide runtime);
    if get(Runtime_next.visible runtime)then failwith"hide did not clear visible flag";
    print_endline"runtime_next visibility: hidden/show/hide flags passed")
