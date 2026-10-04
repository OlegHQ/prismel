let check got want = if got <> want then (Printf.eprintf "got %s, want %s\n" got want; exit 1)

let () =
  let digest = "0123abcd" in
  check (Delimiter.make digest "no clash") "lisp_ghij";
  check (Delimiter.make digest "text lisp_ghij text") "lisp_ghija";
  check (Delimiter.make digest "lisp_ghij lisp_ghija") "lisp_ghijab";
  check (Delimiter.make "f9a0" "") "lisp_fpag"
