(* The workspace Lisp as the text area's [Pxui.Ui.language]: an error-tolerant lexer colours
   comments, strings, numbers, keywords, [^:meta] and the head of every form, and brackets by
   depth (an unmatched one in the invalid colour); Enter indents as a Lisp editor does: a body
   form ([let*], [for], [defn], ...) two columns in from its paren, a call under its first
   argument, a vector under its first element.  Over the same tokens and a [vocab] of the
   catalog it completes the token at the caret (kinds, parameters, choices, forms, operators,
   bindings in scope, ranked), describes the token under the pointer and finds the number a
   drag changes.  ponytail: the text is lexed once per frame per need (colours, pairs, indent,
   completions); the workspace texts are a few hundred lines. *)

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


(* ---- what the editor knows about the language: completions, descriptions, numbers ---- *)

module Param = Editor_core.Param

(* One kind of the catalog as the text editor sees it: the qualified name a head writes, its
   context (the namespace), its label and category, the slots and the parameters. *)
type entry = {
  qualified : string;
  context : string;
  title : string;
  category : string list;
  slots : (string * bool) list;  (* name, required *)
  fields : Param.field_view list;
}

type vocab = { kinds : entry list; by_name : (string, entry) Hashtbl.t }

let vocab (descriptors : Flow_sop.Catalog.descriptor list) =
  let by_name = Hashtbl.create 256 in
  let kinds = List.filter_map (fun (d : Flow_sop.Catalog.descriptor) ->
    if Hashtbl.mem by_name d.qualified then None else begin
      let entry = { qualified = d.qualified;
        context = (match String.index_opt d.qualified '/' with
          | Some i -> String.sub d.qualified 0 i | None -> "sop");
        title = d.label; category = d.category;
        slots = List.map (fun (n, r) -> n, r = Procedural.Edit_graph.Required) d.slots;
        fields = d.fields } in
      Hashtbl.add by_name d.qualified entry; Some entry
    end) descriptors in
  { kinds; by_name }

let empty_vocab = vocab []

(* the special forms and their one-line docs (the grammar of specification/workspace) *)
let specials = [
  "workspace", "(workspace name graphs...) · the document: graphs, defns, macros";
  "graph", "(graph name :context sop [inputs] body) · a network; the body is a let* or an expression";
  "defn", "(defn name :context value [(p : type) ...] body) · a function called as (name args)";
  "defmacro", "(defmacro name [params] `template) · a syntax template; ~p fills a hole";
  "let*", "(let* [name expr ...] result) · sequential bindings: the graph's nodes";
  "for", "(for [i (range n)] body) · repeat over lists; geometry merges, numbers are summed";
  "fold", "(fold [acc init] [i xs] body) · feed the result back: acc is the previous value";
  "scan", "(scan [acc init] [i xs] body) · like fold, keeping every step as a list";
  "sum", "(sum [i xs] body) · add the body over the list";
  "if", "(if test then else) · a branch; both arms have the same type";
  "cond", "(cond test expr ... :else expr) · the first test that holds";
  "case", "(case expr literal expr ... :else expr) · match a literal";
  "fn", "(fn [a b] body) · an anonymous function for map, filter, reduce, sort-by";
  "ref", "(ref graph :input value ...) · another graph's result with input overrides";
  "values", "(values :a x :b y) · a record of named results";
  "list", "(list a b c) · a homogeneous list";
  "concat", "(concat xs ys) · join lists";
  "str", "(str a b) · text from parts";
  "get", "(get record :field) · read a field; also record.field";
  "assoc", "(assoc record :field value) · a record with a field changed";
  "map", "(map f xs) · apply f to each item";
  "filter", "(filter f xs) · the items f accepts";
  "reduce", "(reduce f init xs) · fold a function over a list";
  "sort-by", "(sort-by f xs) · sort by a key function";
  "quote", "(quote form) · the form itself, unevaluated";
  "quasiquote", "`form · a template; ~x fills, ~@xs splices";
  "unquote", "~x · fill a hole of a template";
  "unquote-splicing", "~@xs · splice a list into a template";
]

let constants = [
  "t", "time in seconds · a binding reading t recooks every frame";
  "pi", "3.14159...";
  "true", "boolean true"; "false", "boolean false";
  "nil", "empty geometry · an unconnected slot";
]

let special_keywords = [
  ":context", "the graph's context: sop, value, scene, world, settings or editor";
  ":skip", ":skip [i ...] · iteration tuples a for or scene/merge leaves out";
  ":else", "the branch when no test holds";
  ":keys", "{:keys [a b]} · destructure a record's fields";
  ":bypass", "^:bypass (call ...) · the call passes its first input through";
]

let contexts = [ "sop"; "value"; "scene"; "world"; "settings"; "editor"; "material" ]

let ws_context = function
  | "scene" -> Flow.Workspace.Scene | "world" -> Flow.Workspace.World
  | "settings" -> Flow.Workspace.Settings | "editor" -> Flow.Workspace.Editor
  | "material" -> Flow.Workspace.Material
  | "value" -> Flow.Workspace.Value | _ -> Flow.Workspace.Sop

(* the built-in operators a graph of each context may call: the value ones everywhere, the
   context's own on top (ponytail: the context lists are spelled here; [op_signature] drops a
   name the checker does not know) *)
let ops_of context =
  let own = match context with
    | "sop" -> [ "sop/curve"; "sop/point_list"; "sop/piece_list" ]
    | "scene" -> [ "scene/merge" ]
    | "world" -> [ "world/none" ]
    | "material" -> [ "material/standard" ]
    | "editor" -> [ "ui/workspace"; "ui/viewport"; "ui/graph"; "ui/inspector"; "ui/outline"; "ui/list";
                    "ui/lisp"; "ui/timeline"; "ui/split"; "ui/split-at"; "ui/tile"; "ui/floating"; "ui/switch" ]
    | _ -> [] in
  List.filter_map (fun name ->
    Option.map (fun s -> name, s) (Flow.Workspace.op_signature (ws_context context) name))
    (own @ Flow.Workspace.value_ops)

let ty_name = Flow.Ty.to_string

let op_doc name (s : Flow.Workspace.op_signature) =
  let pos = List.map (fun (n, t) -> n ^ ":" ^ ty_name t) s.pos in
  let opt = List.map (fun (n, t) -> "[" ^ n ^ ":" ^ ty_name t ^ "]") s.opt in
  let rest = match s.rest with Some (n, t) -> [ n ^ ":" ^ ty_name t ^ "..." ] | None -> [] in
  let kw = List.map (fun (n, t) -> ":" ^ n ^ " " ^ ty_name t) s.kw in
  "(" ^ String.concat " " (name :: pos @ opt @ rest @ kw) ^ ") · built-in operator"

let kind_doc (k : entry) =
  let slots = match k.slots with
    | [] -> "" | s -> " · inputs " ^ String.concat ", " (List.map fst s) in
  let params = match List.length k.fields with
    | 0 -> "" | n -> Printf.sprintf " · %d parameter%s" n (if n = 1 then "" else "s") in
  k.title ^ (if k.category = [] then "" else " · " ^ String.concat " / " k.category) ^ slots ^ params

let value_text = function
  | Param.Bool_value b -> string_of_bool b
  | Param.Int_value i -> string_of_int i
  | Param.Float_value f -> Printf.sprintf "%g" f
  | Param.Text_value s | Param.Choice_value s -> "\"" ^ s ^ "\""

let kind_text (f : Param.field_view) = match f.kind with
  | Param.Toggle_view -> "bool"
  | Param.Integer_view r -> Printf.sprintf "int %d..%d" r.soft_min r.soft_max
  | Param.Floating_view r -> Printf.sprintf "float %g..%g" r.soft_min r.soft_max
  | Param.Text_view -> "text"
  | Param.Choice_view options -> "one of " ^ String.concat ", " (Array.to_list options)

let field_doc (f : Param.field_view) =
  f.label ^ (if f.folder = [] then "" else " · " ^ String.concat " / " f.folder)
  ^ " · " ^ kind_text f ^ " · default " ^ value_text f.default
  ^ (match f.description with Some d -> " · " ^ d | None -> "")

(* the keyword arguments a kind takes, as (name, type, doc, primary): a vec3 group once, before
   its components *)
let keywords_of (k : entry) =
  let seen = Hashtbl.create 16 in
  List.filter_map (fun (f : Param.field_view) -> match f.vec3 with
    | Some (group, _) when Hashtbl.mem seen group -> None
    | Some (group, _) ->
        Hashtbl.add seen group ();
        (* the group is named by its first component's label without the axis *)
        let title = if String.length f.label > 2 && f.label.[String.length f.label - 2] = ' '
          then String.sub f.label 0 (String.length f.label - 2) else f.label in
        Some (group, "vec3", title ^ (if f.folder = [] then "" else " · " ^ String.concat " / " f.folder)
          ^ " · [x y z]" ^ (match f.description with Some d -> " · " ^ d | None -> ""), f.primary)
    | None -> Some (f.name, kind_text f, field_doc f, f.primary)) k.fields
  @ List.filter_map (fun (f : Param.field_view) -> match f.vec3 with
    | Some _ -> Some (f.name, kind_text f, field_doc f, false) | None -> None) k.fields

(* ---- reading the text around a byte (over the lexer's tokens) ---- *)

let word text (t : token) = String.sub text t.start (t.stop - t.start)

let index_at tokens at =
  let n = Array.length tokens in
  let rec seek i = if i >= n then -1 else if tokens.(i).start = at then i else seek (i + 1) in
  seek 0

(* the top-level items of the bracket opened by token [i]: the index of each item's first
   token, up to the matching close or the end of the text *)
let items tokens i =
  let n = Array.length tokens in
  let rec go j d acc =
    if j >= n then List.rev acc
    else match tokens.(j).kind with
      | Open _ -> go (j + 1) (d + 1) (if d = 0 then j :: acc else acc)
      | Close _ -> if d = 0 then List.rev acc else go (j + 1) (d - 1) acc
      | _ -> go (j + 1) d (if d = 0 then j :: acc else acc) in
  go (i + 1) 0 []

(* the byte after item [j] (its matching close for a bracket) *)
let item_stop tokens j =
  let n = Array.length tokens in
  match tokens.(j).kind with
  | Open d ->
      let rec seek k = if k >= n then tokens.(n - 1).stop
        else match tokens.(k).kind with Close d' when d' = d -> tokens.(k).stop | _ -> seek (k + 1) in
      seek (j + 1)
  | _ -> tokens.(j).stop

(* the head of the call a token sits in: back over balanced brackets to the nearest head *)
let head_before text tokens i =
  let rec back k depth =
    if k < 0 then None else match tokens.(k).kind with
      | Close _ -> back (k - 1) (depth + 1)
      | Open _ -> if depth > 0 then back (k - 1) (depth - 1) else None
      | Head when depth = 0 -> Some (word text tokens.(k))
      | _ -> back (k - 1) depth in
  back (i - 1) 0

let binders = [ "let*"; "for"; "fold"; "scan"; "sum"; "fn" ]

(* the names bound before [limit] by let*, loops, fn and graph inputs, each with a snippet of
   what it is; the defn names; the graph names (ponytail: a lexical scan, not scoping: every
   name bound earlier in the text is offered) *)
let bound text tokens limit =
  let n = Array.length tokens in
  let names = ref [] and defns = ref [] and graphs = ref [] in
  let snippet j =
    let stop = min (item_stop tokens j) (tokens.(j).start + 48) in
    String.map (function '\n' -> ' ' | c -> c) (String.sub text tokens.(j).start (stop - tokens.(j).start)) in
  for i = 0 to n - 1 do
    if tokens.(i).start < limit then
      match tokens.(i).kind with
      | Head when i + 1 < n && tokens.(i + 1).kind = Sym
                && (let h = word text tokens.(i) in h = "defn" || h = "defmacro") ->
          defns := word text tokens.(i + 1) :: !defns
      | Head when i + 1 < n && tokens.(i + 1).kind = Sym && word text tokens.(i) = "graph" ->
          graphs := word text tokens.(i + 1) :: !graphs
      | (Open _ | Unmatched) when text.[tokens.(i).start] = '[' ->
          (match head_before text tokens i with
           | Some h when List.mem h binders ->
               let its = Array.of_list (items tokens i) in
               let all = h = "fn" in
               Array.iteri (fun pos j ->
                 if tokens.(j).kind = Sym && tokens.(j).start < limit && (all || pos mod 2 = 0) then
                   names := (word text tokens.(j),
                     if all || pos + 1 >= Array.length its then "parameter of " ^ h
                     else h ^ " binding · " ^ snippet its.(pos + 1)) :: !names) its
           | Some ("graph" | "defn") ->
               (* [(name : type default) ...] *)
               List.iter (fun j -> match tokens.(j).kind with
                 | (Open _ | Unmatched) when j + 1 < n && tokens.(j + 1).kind = Head ->
                     names := (word text tokens.(j + 1), "input · " ^ snippet j) :: !names
                 | _ -> ()) (items tokens i)
           | _ -> ())
      | _ -> ()
  done;
  List.rev !names, List.rev !defns, List.rev !graphs

(* the value after keyword [kw] among the items of bracket [i] *)
let kw_value text tokens i kw =
  let rec seek = function
    | j :: k :: rest ->
        if tokens.(j).kind = Kw && word text tokens.(j) = kw
        then (if tokens.(k).kind = Sym then Some (word text tokens.(k)) else None)
        else seek (k :: rest)
    | _ -> None in
  seek (items tokens i)

(* the context of the outermost graph or defn around the caret ([open_stack] innermost first);
   sop otherwise *)
let context_of text tokens open_stack =
  List.fold_left (fun found (_, at) -> match found with
    | Some _ -> found
    | None ->
        let i = index_at tokens at in
        if i >= 0 && i + 1 < Array.length tokens && tokens.(i + 1).kind = Head
           && (let h = word text tokens.(i + 1) in h = "graph" || h = "defn")
        then Some (Option.value ~default:"sop" (kw_value text tokens i ":context"))
        else None) None (List.rev open_stack)
  |> Option.value ~default:"sop"

let usage text tokens name =
  Array.fold_left (fun n t -> if t.kind = Head && word text t = name then n + 1 else n) 0 tokens

(* how well [name] matches the typed [prefix]: 3 a prefix, 2 a prefix of a word after _ or /,
   1 a subsequence, 0 none *)
let quality prefix name =
  let p = String.lowercase_ascii prefix and n = String.lowercase_ascii name in
  if p = "" || String.starts_with ~prefix:p n then 3
  else if List.exists (String.starts_with ~prefix:p)
      (String.split_on_char '_' n @ String.split_on_char '/' n) then 2
  else if Pxui.Ui.fuzzy_match ~query:p n then 1 else 0

type candidate = { name : string; insert : string; detail : string; doc : string; group : int; uses : int }

(* best match first, then the group (kinds before forms before operators; primary parameters
   first), then the names the text already uses, then the alphabet; at most 48 *)
let rank prefix candidates =
  List.filter_map (fun c -> match quality prefix c.name with 0 -> None | q -> Some (q, c)) candidates
  |> List.stable_sort (fun (qa, a) (qb, b) ->
    if qa <> qb then compare qb qa
    else if a.group <> b.group then compare a.group b.group
    else if a.uses <> b.uses then compare b.uses a.uses
    else compare a.name b.name)
  |> List.filteri (fun i _ -> i < 48)
  |> List.map snd

let complete vocab text caret =
  let caret = max 0 (min caret (String.length text)) in
  (* the token being typed ends at the caret: the text before it says what it is *)
  let before, _, open_stack = lex (String.sub text 0 caret) in
  let nb = Array.length before in
  let last = if nb = 0 then None else Some before.(nb - 1) in
  let current = match last with
    | Some t when t.stop = caret
        && (match t.kind with Sym | Kw | Head | Meta | Num | Str -> true | _ -> false) -> Some t
    | _ -> None in
  let head_position = match current, last with
    | Some { kind = Head; _ }, _ -> true
    | None, Some { kind = Unmatched | Open _; stop; _ } when stop = caret && text.[stop - 1] = '(' -> true
    | _ -> false in
  if current = None && not head_position then [] else begin
    (* the whole text, so the brackets around the caret are matched *)
    let tokens, _, _ = lex text in
    let prefix = match current with
      | Some ({ kind = Str; _ } as t) -> String.sub text (t.start + 1) (caret - t.start - 1)  (* past the quote *)
      | Some t -> word text t
      | None -> "" in
    let replace = match current with
      | Some ({ kind = Str; _ } as t) when caret < String.length text && text.[caret] = '"' -> t.start, caret + 1
      | Some t -> t.start, caret
      | None -> caret, caret in
    let context = context_of text tokens open_stack in
    let enclosing = match open_stack with
      | (_, at) :: _ -> let i = index_at tokens at in if i >= 0 then Some i else None
      | [] -> None in
    let enclosing_head = match enclosing with
      | Some i when i + 1 < Array.length tokens && tokens.(i + 1).kind = Head -> Some (word text tokens.(i + 1))
      | _ -> None in
    let prior = match enclosing with
      | Some i -> List.filter (fun j -> tokens.(j).stop <= fst replace) (items tokens i)
      | None -> [] in
    let present = List.filter_map (fun j -> if tokens.(j).kind = Kw then Some (word text tokens.(j)) else None) prior in
    let after_kw = match List.rev prior with
      | j :: _ when tokens.(j).kind = Kw -> Some (word text tokens.(j)) | _ -> None in
    let kind_of name = match Hashtbl.find_opt vocab.by_name name with
      | Some k -> Some k
      | None -> Hashtbl.find_opt vocab.by_name (context ^ "/" ^ name) in
    let kind = Option.bind enclosing_head kind_of in
    let mk ?(group = 5) ?(uses = 0) ?insert name detail doc =
      { name; insert = Option.value ~default:name insert; detail; doc; group; uses } in
    (* the choices of the keyword before the caret *)
    let choices = match after_kw, kind with
      | Some kw, Some k ->
          let kw = String.sub kw 1 (String.length kw - 1) in
          (match List.find_opt (fun (f : Param.field_view) -> f.name = kw) k.fields with
           | Some { kind = Param.Choice_view options; label; _ } ->
               List.map (fun o -> mk ~group:0 ~insert:("\"" ^ o ^ "\"") o "choice" (label ^ " = " ^ o))
                 (Array.to_list options)
           | _ -> [])
      | _ -> [] in
    (* a new name in a binder's vector is the writer's to choose *)
    let naming = match open_stack, enclosing with
      | ('[', _) :: _, Some i ->
          (match head_before text tokens i with
           | Some h when List.mem h binders -> h = "fn" || List.length prior mod 2 = 0
           | _ -> false)
      | _ -> false in
    let candidates = match current with
      | _ when naming -> []
      | Some { kind = Meta; _ } -> [ mk "^:bypass" "meta" (List.assoc ":bypass" special_keywords) ]
      (* a keyword: the kind's parameters and slots, an operator's keywords, a form's keywords *)
      | Some { kind = Kw; _ } ->
          let of_kind = match kind with
            | Some k ->
                List.filter_map (fun (name, ty, doc, primary) ->
                  if List.mem (":" ^ name) present then None
                  else Some (mk ~group:(if primary then 0 else 1) (":" ^ name) ty doc)) (keywords_of k)
                @ List.map (fun (s, required) -> mk ~group:2 (":" ^ s) "input"
                    (s ^ " · " ^ (if required then "required" else "optional") ^ " input of " ^ k.qualified)) k.slots
            | None -> [] in
          let of_op = match enclosing_head with
            | Some h -> (match Flow.Workspace.op_signature (ws_context context) h with
                | Some s -> List.map (fun (k, t) -> mk ~group:0 (":" ^ k) (ty_name t) (op_doc h s)) s.kw
                | None -> [])
            | None -> [] in
          let of_form = match enclosing_head with
            | Some ("graph" | "defn" | "defmacro") -> [ ":context" ]
            | Some ("for" | "scene/merge") -> [ ":skip" ]
            | Some ("cond" | "case") -> [ ":else" ]
            | _ -> [] in
          of_kind @ of_op @ List.map (fun k -> mk ~group:3 k "form" (List.assoc k special_keywords)) of_form
      | Some { kind = Str; _ } -> choices
      | Some { kind = Num; _ } -> []
      (* the head of a call: this context's kinds, the defns, the special forms, the operators *)
      | _ when head_position ->
          let _, defns, _ = bound text tokens caret in
          List.map (fun d -> mk ~group:0 ~uses:(usage text tokens d) d "defn" (d ^ " · a function of this workspace")) defns
          @ List.filter_map (fun (k : entry) ->
              if k.context = context then
                Some (mk ~group:0 ~uses:(usage text tokens k.qualified) k.qualified
                  (String.concat " / " k.category) (k.qualified ^ " · " ^ kind_doc k))
              else None) vocab.kinds
          @ List.map (fun (s, doc) -> mk ~group:1 ~uses:(usage text tokens s) s "form" doc) specials
          @ List.map (fun (o, s) -> mk ~group:2 ~uses:(usage text tokens o) o "operator" (op_doc o s)) (ops_of context)
      (* an argument: a context after :context, a graph after ref, a choice after its keyword,
         else the bindings in scope, the constants and the defns *)
      | Some { kind = Sym; _ } ->
          (match after_kw, enclosing_head with
           | Some ":context", _ -> List.map (fun c -> mk ~group:0 c "context" (c ^ " graph")) contexts
           | _, Some "ref" when List.length prior <= 1 ->
               let _, _, graphs = bound text tokens caret in
               List.map (fun g -> mk ~group:0 g "graph" ("(ref " ^ g ^ ")")) graphs
           | _ when choices <> [] -> choices
           | _ ->
               let bindings, defns, _ = bound text tokens caret in
               let seen = Hashtbl.create 16 in
               List.filter_map (fun (name, doc) ->
                 if Hashtbl.mem seen name then None
                 else (Hashtbl.add seen name (); Some (mk ~group:0 name "binding" doc))) (List.rev bindings)
               @ List.map (fun (c, doc) -> mk ~group:1 c "constant" doc) constants
               @ List.map (fun d -> mk ~group:2 d "defn" (d ^ " · a function value")) defns)
      | _ -> [] in
    List.map (fun c -> { Pxui.Ui.replace; insert = c.insert; label = c.name; detail = c.detail; doc = c.doc })
      (rank prefix candidates)
  end

(* the token at [byte] and what it is *)
let describe vocab text byte =
  let tokens, _, _ = lex text in
  let n = Array.length tokens in
  let rec find i = if i >= n then None
    else if tokens.(i).start <= byte && byte < tokens.(i).stop then Some i else find (i + 1) in
  match find 0 with
  | None -> None
  | Some i ->
      let t = tokens.(i) in
      let w = word text t in
      let enclosing_head = head_before text tokens i in
      let _, _, open_stack = lex (String.sub text 0 t.start) in
      let context = context_of text tokens open_stack in
      let kind_of name = match Hashtbl.find_opt vocab.by_name name with
        | Some k -> Some k | None -> Hashtbl.find_opt vocab.by_name (context ^ "/" ^ name) in
      let signature = Flow.Workspace.op_signature (ws_context context) in
      let bare = if String.length w > 1 then String.sub w 1 (String.length w - 1) else "" in
      let doc = match t.kind with
        | Head ->
            (match List.assoc_opt w specials, kind_of w, signature w with
             | Some doc, _, _ -> Some doc
             | None, Some k, _ -> Some (k.qualified ^ " · " ^ kind_doc k)
             | None, None, Some s -> Some (op_doc w s)
             | None, None, None ->
                 let _, defns, _ = bound text tokens t.start in
                 if List.mem w defns then Some (w ^ " · a function of this workspace") else None)
        | Kw ->
            (match Option.bind enclosing_head kind_of, Option.bind enclosing_head signature with
             | Some k, _ ->
                 (match List.find_opt (fun (name, _, _, _) -> name = bare) (keywords_of k) with
                  | Some (_, _, doc, _) -> Some doc
                  | None -> if List.mem_assoc bare k.slots then Some (bare ^ " · input of " ^ k.qualified)
                      else List.assoc_opt w special_keywords)
             | None, Some s when List.mem_assoc bare s.kw -> Some (w ^ " · " ^ ty_name (List.assoc bare s.kw))
             | _ -> List.assoc_opt w special_keywords)
        | Sym ->
            (match List.assoc_opt w constants with
             | Some doc -> Some doc
             | None ->
                 let bindings, defns, graphs = bound text tokens t.start in
                 (match List.assoc_opt w (List.rev bindings) with
                  | Some doc -> Some (w ^ " · " ^ doc)
                  | None -> if List.mem w defns then Some (w ^ " · a function of this workspace")
                      else if List.mem w graphs then Some (w ^ " · a graph of this workspace")
                      else None))
        | Num -> Some (w ^ " · drag sideways to change it, Shift for coarse steps")
        | Meta -> List.assoc_opt bare special_keywords
        | Str ->
            (match Option.bind enclosing_head kind_of with
             | Some k ->
                 let v = String.trim (String.map (function '"' -> ' ' | c -> c) w) in
                 (match List.find_opt (fun (f : Param.field_view) -> match f.kind with
                     | Param.Choice_view options -> Array.exists (( = ) v) options | _ -> false) k.fields with
                  | Some f -> Some (v ^ " · a choice of :" ^ f.name ^ " (" ^ f.label ^ ")")
                  | None -> None)
             | None -> None)
        | Comment | Open _ | Close _ | Unmatched -> None in
      Option.map (fun doc -> t.start, t.stop, doc) doc

let number_at text byte =
  let tokens, _, _ = lex text in
  Array.to_list tokens |> List.find_map (fun t ->
    if t.kind = Num && t.start <= byte && byte < t.stop then Some (t.start, t.stop) else None)


(* Parinfer's indent mode: the closing brackets at the end of each line (its paren trail) are
   inferred from the indentation of the code lines that follow, so a form holds exactly the
   lines indented past its opener, and a closer that matches nothing is dropped.  Strings and
   comments are left alone; on the caret's line the trail starts no earlier than the caret, so
   typing before a closer is never undone.  [parinfer text caret] returns the text and where
   [caret] lands in it.  ponytail: the text is scanned once per edited frame. *)
let parinfer_text text caret =
  let n = String.length text in
  let is_closer c = c = ')' || c = ']' || c = '}' in
  let is_space c = c = ' ' || c = '\t' || c = '\r' in
  (* the lines: (start, stop) byte ranges without the break *)
  let lines =
    let rec go start acc =
      let stop = match String.index_from_opt text start '\n' with Some j -> j | None -> n in
      let acc = (start, stop) :: acc in
      if stop >= n then List.rev acc else go (stop + 1) acc in
    Array.of_list (go 0 []) in
  let count = Array.length lines in
  let code_end = Array.make count 0 in  (* where a line's inferred closers go *)
  let trail = Array.make count "" in  (* the closers inferred for each line *)
  let removed = ref [] in  (* bytes dropped: the old trails and the closers matching nothing *)
  let stack = ref [] in  (* the open brackets: closer and column, innermost first *)
  let last_code = ref (-1) in  (* the last line holding code *)
  let append line closer = trail.(line) <- trail.(line) ^ String.make 1 closer in
  Array.iteri (fun index (start, stop) ->
    (* which bytes are code: not in a string, not in the comment *)
    let code = Array.make (stop - start) true in
    let in_string = ref false and comment = ref stop and i = ref start in
    while !i < !comment do
      let c = text.[!i] in
      if !in_string then begin
        code.(!i - start) <- false;
        if c = '\\' && !i + 1 < stop then (code.(!i + 1 - start) <- false; incr i)
        else if c = '"' then in_string := false
      end else if c = '"' then (in_string := true; code.(!i - start) <- false)
      else if c = ';' then comment := !i;
      incr i
    done;
    let is_code i = i < !comment && code.(i - start) in
    (* the paren trail: the closers ending the code, with the blanks among them *)
    let te = ref !comment in
    while !te > start && is_code (!te - 1) && is_space text.[!te - 1] do decr te done;
    let ts = ref !te in
    while !ts > start && is_code (!ts - 1) && (is_closer text.[!ts - 1] || is_space text.[!ts - 1]) do decr ts done;
    code_end.(index) <- !ts;
    (* on the caret's line the trail starts no earlier than the caret *)
    let ts = if caret > !ts && caret < !te then caret else !ts in
    let trail_here = ref false in
    for i = ts to !te - 1 do if is_closer text.[i] then trail_here := true done;
    let ts, te = if !trail_here then ts, !te else !te, !te in
    if !trail_here && ts > code_end.(index) then code_end.(index) <- ts;
    (* a line whose first code byte lies before the trail is a code line: its indentation
       closes every bracket opened at that column or further right *)
    let first = ref start in
    while !first < ts && is_space text.[!first] do incr first done;
    let is_code_line = !first < ts && !first < !comment in
    if is_code_line then begin
      let x = !first - start in
      let rec pop () = match !stack with
        | (closer, column) :: rest when column >= x ->
            stack := rest; if !last_code >= 0 then append !last_code closer; pop ()
        | _ -> () in
      pop ()
    end;
    for i = start to ts - 1 do
      if is_code i then begin
        let c = text.[i] in
        if c = '(' || c = '[' || c = '{' then stack := (closer_of c, i - start) :: !stack
        else if is_closer c then begin
          match !stack with
          | (closer, _) :: rest when closer = c -> stack := rest
          | _ -> removed := i :: !removed
        end
      end
    done;
    for i = ts to te - 1 do removed := i :: !removed done;
    if is_code_line then last_code := index) lines;
  List.iter (fun (closer, _) -> if !last_code >= 0 then append !last_code closer) !stack;
  (* the text again: the kept bytes, each line's closers at its code end *)
  let removed = List.sort_uniq compare !removed in
  let out = Buffer.create (n + 8) in
  let shift = ref 0 in  (* bytes inserted before the caret, minus bytes removed before it *)
  let skip = ref removed in
  Array.iteri (fun index (start, stop) ->
    for i = start to stop do
      if i = code_end.(index) && trail.(index) <> "" then begin
        Buffer.add_string out trail.(index);
        if i < caret then shift := !shift + String.length trail.(index)
      end;
      if i < stop || (i = n && stop = n && i < n) then begin
        match !skip with
        | r :: rest when r = i -> skip := rest; if i < caret then decr shift
        | _ -> Buffer.add_char out text.[i]
      end else if i = stop && i < n then Buffer.add_char out '\n'
    done) lines;
  Buffer.contents out, caret + !shift

let language ?(vocab = empty_vocab) ?(parinfer = false) theme : Pxui.Ui.language =
  let infer = parinfer in
  { colorize = colorize theme; brackets; indent;
    pairs = [ '(', ')'; '[', ']'; '{', '}'; '"', '"' ];
    complete = complete vocab; describe = describe vocab; number_at;
    rewrite = (if infer then Some parinfer_text else None) }
