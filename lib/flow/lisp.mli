(** The canonical printer of the workspace language.  A port of the study's
    [pp]: 84 columns, aligned [let*] bindings, keyword pairs one per line when
    a form breaks, notes and [^:flags] kept.  Printing is a fixed point:
    [print (parse (print x)) = print x]. *)

type spans = (Syntax.id * Diagnostic.span) list
(** Byte span of every printed form in the text, in reading order (a form's
    span includes its [^:] flags; notes are outside it). *)

val print : Syntax.t list -> string * spans
(** Top-level forms separated by a blank line; the text ends in a newline. *)

val float : float -> string
(** The one spelling of a float in workspace text: the shortest digits that read
    back as the same value, always with a [.] and never an exponent
    ([1e-14] is [0.00000000000001]).  Total: a non-finite value prints [0.0];
    reject it before writing where that matters. *)

val flat : Syntax.t -> string
(** One-line spelling of a form, for messages. *)
