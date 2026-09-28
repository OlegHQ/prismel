type position = Diagnostic.position
type atom = Symbol of string | Keyword of string | Number of string | String of string
type t = { node : node; span : Diagnostic.span; position : position }
and node = Atom of atom | List of t list | Vector of t list | Meta of string * t

type kind = Open of char | Close of char | Meta_name of string | Word of atom | End
type token = { kind : kind; span : Diagnostic.span; position : position }

let position_of_offset source offset : position =
  let line = ref 1 and col = ref 1 in
  for i = 0 to min (String.length source) offset - 1 do
    if source.[i] = '\n' then (incr line; col := 1) else incr col
  done;
  {line = !line; col = !col}

let number text =
  let length = String.length text in
  let digit = function '0' .. '9' -> true | _ -> false in
  let i = ref (if length > 0 && text.[0] = '-' then 1 else 0) in
  let before = ref 0 and after = ref 0 in
  while !i < length && digit text.[!i] do incr before; incr i done;
  if !i < length && text.[!i] = '.' then begin
    incr i;
    while !i < length && digit text.[!i] do incr after; incr i done
  end;
  !i = length && !before + !after > 0

let tokenize source =
  let length = String.length source in
  let offset = ref 0 and line = ref 1 and col = ref 1 in
  let position () : position = {line = !line; col = !col} in
  let advance () =
    if source.[!offset] = '\n' then (incr line; col := 1) else incr col;
    incr offset in
  let token kind start position =
    {kind; span = {Diagnostic.start; finish = !offset}; position} in
  let error start code message = Error (Diagnostic.error
    ~span:{start; finish = !offset}
    ~position:(position_of_offset source start)
    ~code message) in
  let separator = function
    | ' ' | '\t' | '\r' | '\n' | '(' | ')' | '[' | ']' | ';' | '"' -> true
    | _ -> false in
  let rec read reversed =
    if !offset = length then Ok (Array.of_list (List.rev
      (token End !offset (position ()) :: reversed)))
    else match source.[!offset] with
    | ' ' | '\t' | '\r' | '\n' -> advance (); read reversed
    | ';' ->
        while !offset < length && source.[!offset] <> '\n' do advance () done;
        read reversed
    | ('(' | '[') as mark ->
        let start = !offset and position = position () in
        advance (); read (token (Open mark) start position :: reversed)
    | (')' | ']') as mark ->
        let start = !offset and position = position () in
        advance (); read (token (Close mark) start position :: reversed)
    | '"' ->
        let start = !offset and position = position () in
        let buffer = Buffer.create 32 in
        advance ();
        let rec quoted () =
          if !offset = length then error start "E_UNCLOSED"
            "This string is never closed"
          else match source.[!offset] with
          | '"' ->
              advance ();
              read (token (Word (String (Buffer.contents buffer)))
                start position :: reversed)
          | '\\' ->
              let escape = !offset in
              advance ();
              if !offset = length then error start "E_UNCLOSED"
                "This string is never closed"
              else (match source.[!offset] with
                | '"' -> Buffer.add_char buffer '"'; advance (); quoted ()
                | '\\' -> Buffer.add_char buffer '\\'; advance (); quoted ()
                | 'n' -> Buffer.add_char buffer '\n'; advance (); quoted ()
                | _ -> error escape "E_UNEXPECTED" "Unknown string escape")
          | character -> Buffer.add_char buffer character;
              advance (); quoted () in
        quoted ()
    | _ ->
        let start = !offset and position = position () in
        while !offset < length && not (separator source.[!offset]) do
          advance ()
        done;
        let word = String.sub source start (!offset - start) in
        let kind =
          if String.starts_with ~prefix:"^:" word then
            Meta_name (String.sub word 2 (String.length word - 2))
          else if String.starts_with ~prefix:":" word then
            Word (Keyword (String.sub word 1 (String.length word - 1)))
          else if number word then Word (Number word)
          else Word (Symbol word) in
        read (token kind start position :: reversed) in
  read []

let parse source =
  let ( let* ) = Result.bind in
  let* tokens = tokenize source in
  let index = ref 0 in
  let peek () = tokens.(!index) in
  let take () = let token = peek () in
    (match token.kind with End -> () | _ -> incr index); token in
  let diagnostic token code message = Error
    (Diagnostic.error ~span:token.span ~position:token.position
      ~code message) in
  let rec form () =
    let token = take () in
    match token.kind with
    | Word atom -> Ok {node = Atom atom; span = token.span;
        position = token.position}
    | Open opening -> group token opening []
    | Meta_name name ->
        (match (peek ()).kind with
         | End -> diagnostic token "E_UNEXPECTED" "Metadata needs a form after it"
         | _ ->
             let* inner = form () in
             Ok {node = Meta (name, inner);
               span = {start = token.span.start; finish = inner.span.finish};
               position = token.position})
    | Close mark -> diagnostic token "E_UNEXPECTED"
        (Printf.sprintf "Unexpected %C" mark)
    | End -> diagnostic token "E_UNEXPECTED" "Expected a form"
  and group opening mark reversed =
    let closing = if mark = '(' then ')' else ']' in
    let token = peek () in
    match token.kind with
    | Close actual when actual = closing ->
        ignore (take ());
        let node = if mark = '(' then List (List.rev reversed)
          else Vector (List.rev reversed) in
        Ok {node; span = {start = opening.span.start;
          finish = token.span.finish}; position = opening.position}
    | Close actual -> diagnostic token "E_UNEXPECTED"
        (Printf.sprintf "Expected %C to close the %C on line %d, found %C"
          closing mark opening.position.line actual)
    | End -> diagnostic opening "E_UNCLOSED"
        (Printf.sprintf "This %C is never closed" mark)
    | _ ->
        let* item = form () in
        group opening mark (item :: reversed) in
  let rec all reversed = match (peek ()).kind with
    | End -> Ok (List.rev reversed)
    | _ -> let* item = form () in all (item :: reversed) in
  try all [] with Stack_overflow -> Error (Diagnostic.error
    ~position:Diagnostic.{line = 1; col = 1} ~code:"E_DEPTH"
    "S-expression nesting exceeds the stack capacity")
