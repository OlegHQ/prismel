(* Quoted-string ids are lowercase letters and underscores only, so the hex
   digits 0-9 of the digest become g-p; a collision appends letters. *)
let make digest text =
  let has d = let n = String.length d and m = String.length text in
    let rec at i = i + n <= m && (String.sub text i n = d || at (i + 1)) in at 0 in
  let letter c = if c >= '0' && c <= '9' then Char.chr (Char.code c - 48 + Char.code 'g') else c in
  let rec go d k = if has d then go (d ^ String.make 1 (Char.chr (Char.code 'a' + k mod 26))) (k + 1) else d in
  go ("lisp_" ^ String.map letter (String.sub digest 0 4)) 0
