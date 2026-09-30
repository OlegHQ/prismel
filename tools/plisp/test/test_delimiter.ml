let check got want = if got <> want then (Printf.eprintf "got %s, want %s\n" got want; exit 1)

let () =
  let digest = "0123abcd" in
  check (Delimiter.make digest "no clash") "plisp_ghij";
  check (Delimiter.make digest "text plisp_ghij text") "plisp_ghija";
  check (Delimiter.make digest "plisp_ghij plisp_ghija") "plisp_ghijab";
  check (Delimiter.make "f9a0" "") "plisp_fpag"
