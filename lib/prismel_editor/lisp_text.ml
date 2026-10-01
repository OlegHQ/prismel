(* The workspace Lisp as the text area's [Pxui.Ui.language]: an error-tolerant lexer colours
   comments, strings, numbers, keywords, [^:meta] and the head of every form, and brackets by
   depth (an unmatched one in the invalid colour); Enter indents as a Lisp editor does: a body
   form ([let*], [for], [defn], ...) two columns in from its paren, a call under its first
   argument, a vector under its first element.  ponytail: the text is lexed once per frame per
   need (colours, pairs, indent); the workspace texts are a few hundred lines. *)

type kind = Comment | Str | Num | Kw | Meta | Head | Sym | Open of int | Close of int | Unmatched
type token = { kind : kind; start : int; stop : int }

let separator = function
  | ' ' | '\t' | '\r' | '\n' | '(' | ')' | '[' | ']' | '{' | '}' | ';' | '"' -> true
  | _ -> false

let closer_of = function '(' -> ')' | '[' -> ']' | _ -> '}'

let number w =
  let n = String.length w in
  let i = ref (if n > 0 && w.[0] = '-' then 1 else 0) and digits = ref 0 in
  let digit () = while !i < n && w.[!i] >= '0' && w.[!i] <= '9' do incr i; incr digits done in
  digit ();
  if !i < n && w.[!i] = '.' then (incr i; digit ());
  !i = n && !digits > 0

(* the tokens in order, the matched (open, close) pairs, and the brackets still open at the end
   (innermost first) *)
let lex text =
  let n = String.length text in
  let tokens = ref [] and count = ref 0 and pairs = ref [] and stack = ref [] in
  let tok kind start stop = tokens := { kind; start; stop } :: !tokens; incr count in
  let head_next = ref false in
  let rec go i =
    if i >= n then ()
    else match text.[i] with
    | ' ' | '\t' | '\r' | '\n' -> go (i + 1)
    | ';' ->
        let j = match String.index_from_opt text i '\n' with Some j -> j | None -> n in
        tok Comment i j; go j
    | '"' ->
        let rec close j =
          if j >= n || text.[j] = '\n' then j
          else match text.[j] with '\\' -> close (j + 2) | '"' -> j + 1 | _ -> close (j + 1) in
        let j = min n (close (i + 1)) in
        tok Str i j; head_next := false; go j
    | ('(' | '[' | '{') as c ->
        stack := (c, i, !count) :: !stack;
        tok (Open (List.length !stack - 1)) i (i + 1);
        head_next := c = '(';
        go (i + 1)
    | (')' | ']' | '}') as c ->
        (match !stack with
         | (o, at, _) :: rest when closer_of o = c ->
             stack := rest; pairs := (at, i) :: !pairs; tok (Close (List.length rest)) i (i + 1)
         | _ -> tok Unmatched i (i + 1));
        head_next := false;
        go (i + 1)
    | _ ->
        let j = ref i in
        while !j < n && not (separator text.[!j]) do incr j done;
        let w = String.sub text i (!j - i) in
        let kind =
          if !head_next then Head
          else if w.[0] = ':' && String.length w > 1 then Kw
          else if w.[0] = '^' then Meta
          else if number w then Num
          else Sym in
        tok kind i !j; head_next := false; go !j in
  go 0;
  let tokens = Array.of_list (List.rev !tokens) in
  List.iter (fun (_, _, index) -> tokens.(index) <- { (tokens.(index)) with kind = Unmatched }) !stack;
  tokens, List.rev !pairs, List.map (fun (c, at, _) -> c, at) !stack

let colorize (theme : Pxui.Theme.t) text =
  let ports = Pxui.Theme.ports theme and muted = Pxui.Theme.muted theme in
  let rainbow = [| ports.vec3; ports.int; ports.fn; ports.record |] in
  let tokens, _, _ = lex text in
  Array.to_list tokens |> List.filter_map (fun t ->
    let color = match t.kind with
      | Comment | Meta -> Some muted
      | Str -> Some ports.text
      | Num -> Some ports.float
      | Kw -> Some ports.bool
      | Head -> Some theme.accent
      | Sym -> None
      | Open d | Close d -> Some rainbow.(d mod Array.length rainbow)
      | Unmatched -> Some Pxui.Theme.invalid in
    Option.map (fun c -> t.start, t.stop, c) color)

let brackets text = let _, pairs, _ = lex text in pairs

(* forms whose body is indented two in from the paren rather than under the first argument *)
let body_forms = [ "workspace"; "graph"; "defn"; "defmacro"; "let*"; "let"; "for"; "fold"; "scan";
                   "sum"; "if"; "when"; "fn"; "do"; "cond"; "case" ]

let indent text caret =
  let text = String.sub text 0 (max 0 (min caret (String.length text))) in
  let tokens, _, open_stack = lex text in
  let column at = at - (match String.rindex_from_opt text (at - 1) '\n' with Some i -> i + 1 | None -> 0) in
  let width = match open_stack with
    | [] -> 0
    | (c, at) :: _ when c <> '(' -> column at + 1
    | (_, at) :: _ ->
        let line_end = match String.index_from_opt text at '\n' with Some j -> j | None -> String.length text in
        let after from = List.find_opt (fun t -> t.start > from) (Array.to_list tokens) in
        (match after at with
         | Some ({ kind = Head; _ } as head) ->
             let name = String.sub text head.start (head.stop - head.start) in
             if List.mem name body_forms then column at + 2
             else (match after head.stop with
               | Some arg when arg.start < line_end -> column arg.start
               | _ -> column at + 1)
         | _ -> column at + 1) in
  String.make width ' '

let language theme : Pxui.Ui.language =
  { colorize = colorize theme; brackets; indent;
    pairs = [ '(', ')'; '[', ']'; '{', '}'; '"', '"' ] }
