(** The authored tree of the workspace language (`.rays` text): what
    [Lisp.print] prints and what [Macro] and [Workspace] read.  It keeps
    everything a person wrote: comments (notes), [^:flags] (meta), the
    spelling of numbers, and stable form ids.  It also reads the generated
    catalog manifest ({!Check.catalog_of_manifest}). *)

type id = int
(** Unique per form within one parse ([parse] numbers forms 0, 1, ... in
    reading order); [renumber] gives another tree a disjoint range. *)

type quote_kind = Plain | Quasi | Unquote | Splice
(** [']  [`]  [~]  [~@] *)

type t = {
  id : id;
  node : node;
  span : Diagnostic.span;  (** byte span in the parsed source; [0,0] when built by [make] *)
  notes : string list;  (** comment lines written before the form, without [;] *)
  meta : string list;  (** [^:bypass] flags, in written order *)
  tail : string list;  (** comment lines before the closing bracket of a container *)
}
and node =
  | Sym of string
  | Kw of string  (** without the colon *)
  | Num of string  (** as written, so [2.0] stays a float *)
  | Str of string  (** decoded *)
  | List of t list
  | Vec of t list  (** any length: a 3-vector is vec3 by type, not by syntax *)
  | Map of t list  (** [{}]: the children alternate key and value *)
  | Quote of quote_kind * t

val parse : string -> (t list, Diagnostic.t) result
(** Read every top-level form.  Errors carry code, span and position
    ([E_UNCLOSED], [E_UNEXPECTED], [E_DEPTH]).  A comment becomes a note on
    the next form (register N1); comments before a closing bracket become that
    container's [tail]. *)

val make : ?notes:string list -> ?meta:string list -> node -> t
(** A form with id 0 and an empty span, for macro expansion; [renumber] it. *)

val children : t -> t list
(** Direct sub-forms in reading order. *)

val renumber : int -> t -> t * int
(** [renumber first form] copies [form] numbering every form from [first] in
    reading order (spans, notes and meta kept); returns the next free id. *)
