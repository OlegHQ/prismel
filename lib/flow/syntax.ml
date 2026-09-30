type id = int
type quote_kind = Plain | Quasi | Unquote | Splice
type t = { id : id; node : node; span : Diagnostic.span; notes : string list;
  meta : string list; tail : string list }
and node = Sym of string | Kw of string | Num of string | Str of string
  | List of t list | Vec of t list | Map of t list | Quote of quote_kind * t

type kind =
  | Open of char | Close of char | Prefix of quote_kind | Meta_name of string
  | Comment of string | Word of node | End
type token = { kind : kind; span : Diagnostic.span }

let depth_limit = 120

let number text =
  let n = String.length text in
  let digit c = c >= '0' && c <= '9' in
  let i = ref (if n > 0 && text.[0] = '-' then 1 else 0) in
  let before = ref 0 and after = ref 0 in
  while !i < n && digit text.[!i] do incr before; incr i done;
  if !i < n && text.[!i] = '.' then begin
    incr i;
    while !i < n && digit text.[!i] do incr after; incr i done
  end;
  !i = n && !before + !after > 0

let fail source start finish code message = Error (Diagnostic.error
  ~span:{start; finish} ~position:(Diagnostic.position_of_offset source start)
  ~code message)

let separator = function
  | ' ' | '\t' | '\r' | '\n' | '(' | ')' | '[' | ']' | '{' | '}' | ';' | '"' -> true
  | _ -> false

let tokenize source =
  let n = String.length source in
  let word_end from =
    let j = ref from in
    while !j < n && not (separator source.[!j]) do incr j done; !j in
  let string_end start =
    let buf = Buffer.create 32 in
    let unclosed = fail source start n "E_UNCLOSED" "This string is never closed" in
    let rec go j =
      if j >= n then unclosed
      else match source.[j] with
      | '"' -> Ok (Buffer.contents buf, j + 1)
      | '\\' when j + 1 >= n -> unclosed
      | '\\' ->
          let add c = Buffer.add_char buf c; go (j + 2) in
          (match source.[j + 1] with
           | '"' -> add '"' | '\\' -> add '\\' | 'n' -> add '\n'
           | 't' -> add '\t' | 'r' -> add '\r'
           | _ -> fail source j (j + 2) "E_UNEXPECTED" "Unknown string escape")
      | c -> Buffer.add_char buf c; go (j + 1) in
    go (start + 1) in
  let rec read i acc =
    let tok kind finish =
      {kind; span = {Diagnostic.start = i; finish}} :: acc in
    if i >= n then Ok (List.rev (tok End n))
    else match source.[i] with
    | ' ' | '\t' | '\r' | '\n' -> read (i + 1) acc
    | ';' ->
        let j = ref i in
        while !j < n && source.[!j] <> '\n' do incr j done;
        let k = ref i in
        while !k < !j && source.[!k] = ';' do incr k done;
        if !k < !j && source.[!k] = ' ' then incr k;
        read !j (tok (Comment (String.trim (String.sub source !k (!j - !k)))) !j)
    | ('(' | '[' | '{') as c -> read (i + 1) (tok (Open c) (i + 1))
    | (')' | ']' | '}') as c -> read (i + 1) (tok (Close c) (i + 1))
    | '\'' -> read (i + 1) (tok (Prefix Plain) (i + 1))
    | '`' -> read (i + 1) (tok (Prefix Quasi) (i + 1))
    | '~' when i + 1 < n && source.[i + 1] = '@' -> read (i + 2) (tok (Prefix Splice) (i + 2))
    | '~' -> read (i + 1) (tok (Prefix Unquote) (i + 1))
    | '^' ->
        let j = word_end (i + 1) in
        if j > i + 2 && source.[i + 1] = ':'
        then read j (tok (Meta_name (String.sub source (i + 2) (j - i - 2))) j)
        else fail source i (max j (i + 1)) "E_UNEXPECTED"
          "^ is followed by a keyword, as in ^:bypass"
    | '"' ->
        (match string_end i with
         | Error _ as error -> error
         | Ok (text, j) -> read j (tok (Word (Str text)) j))
    | _ ->
        let j = word_end i in
        let w = String.sub source i (j - i) in
        let node =
          if String.length w > 1 && w.[0] = ':'
          then Kw (String.sub w 1 (String.length w - 1))
          else if number w then Num w else Sym w in
        read j (tok (Word node) j) in
  read 0 []

let parse source =
  let ( let* ) = Result.bind in
  let* tokens = tokenize source in
  let tokens = Array.of_list tokens in
  let at = ref 0 and next_id = ref 0 in
  let peek () = tokens.(!at) in
  let take () = let token = peek () in
    (match token.kind with End -> () | _ -> incr at); token in
  let fresh () = let id = !next_id in incr next_id; id in
  let error (token : token) code message =
    fail source token.span.start token.span.finish code message in
  let rec comments () =
    match (peek ()).kind with
    | Comment text -> ignore (take ()); text :: comments ()
    | _ -> [] in
  let skip_comments () = ignore (comments ()) in
  let close_of = function '(' -> ')' | '[' -> ']' | _ -> '}' in
  let rec form notes depth =
    let token = take () in
    if depth > depth_limit then error token "E_DEPTH"
      (Printf.sprintf "S-expression nesting exceeds %d forms" depth_limit)
    else
      let atom node = Ok {id = fresh (); node; span = token.span; notes;
        meta = []; tail = []} in
      match token.kind with
      | Word node -> atom node
      | Open c -> let id = fresh () in group token c id notes depth []
      | Prefix kind ->
          let id = fresh () in
          skip_comments (); (* nothing to attach a note to between ' and its form *)
          let* inner = form [] (depth + 1) in
          Ok {id; node = Quote (kind, inner); notes; meta = []; tail = [];
            span = {start = token.span.start; finish = inner.span.finish}}
      | Meta_name name ->
          skip_comments ();
          (match (peek ()).kind with
           | End | Close _ -> error token "E_UNEXPECTED" "Metadata needs a form after it"
           | _ ->
               let* inner = form notes (depth + 1) in
               Ok {inner with meta = name :: inner.meta;
                 span = {start = token.span.start; finish = inner.span.finish}})
      | Close c -> error token "E_UNEXPECTED" (Printf.sprintf "Unexpected %C" c)
      | Comment _ | End -> error token "E_UNEXPECTED" "Expected a form"
  and group opening c id notes depth reversed =
    let leading = comments () in
    let token = peek () in
    let finish tail =
      let items = List.rev reversed in
      let node = match c with '(' -> List items | '[' -> Vec items | _ -> Map items in
      Ok {id; node; notes; meta = []; tail;
        span = {start = opening.span.start; finish = token.span.finish}} in
    match token.kind with
    | Close actual when actual = close_of c -> ignore (take ()); finish leading
    | Close actual -> error token "E_UNEXPECTED"
        (Printf.sprintf "Expected %C to close the %C on line %d, found %C"
          (close_of c) c (Diagnostic.position_of_offset source opening.span.start).line actual)
    | End -> error opening "E_UNCLOSED" (Printf.sprintf "This %C is never closed" c)
    | _ ->
        let* item = form leading (depth + 1) in
        group opening c id notes depth (item :: reversed) in
  let rec all reversed =
    let leading = comments () in
    match (peek ()).kind with
    | End ->
        (* ponytail: comments after the last form become the tail of that form
           when it is a container, and are otherwise dropped. *)
        (match reversed, leading with
         | last :: rest, _ :: _ when (match last.node with
             | List _ | Vec _ | Map _ -> true | _ -> false) ->
             Ok (List.rev ({last with tail = last.tail @ leading} :: rest))
         | _ -> Ok (List.rev reversed))
    | _ -> let* item = form leading 0 in all (item :: reversed) in
  try all [] with Stack_overflow -> Error (Diagnostic.error
    ~position:Diagnostic.{line = 1; col = 1} ~code:"E_DEPTH"
    "S-expression nesting exceeds the stack capacity")

let make ?(notes = []) ?(meta = []) node =
  {id = 0; node; span = {start = 0; finish = 0}; notes; meta; tail = []}

let children x = match x.node with
  | Sym _ | Kw _ | Num _ | Str _ -> []
  | List xs | Vec xs | Map xs -> xs
  | Quote (_, y) -> [y]

let renumber first x =
  let next = ref first in
  let rec go x =
    let id = !next in incr next;
    let node = match x.node with
      | (Sym _ | Kw _ | Num _ | Str _) as leaf -> leaf
      | List xs -> List (List.map go xs)
      | Vec xs -> Vec (List.map go xs)
      | Map xs -> Map (List.map go xs)
      | Quote (k, y) -> Quote (k, go y) in
    {x with id; node} in
  let x = go x in (x, !next)
