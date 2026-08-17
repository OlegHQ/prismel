(** Typed, renderer-independent parameter templates for procedural operators.

    Templates describe immutable record fields. Soft bounds define UI drag
    ranges; optional hard bounds are enforced for every write. Current values
    remain in the user's immutable record and never live in global state. *)

type impact = Cook | View | Export

type effects = {
  cook : bool;
  view : bool;
  export : bool;
}

val no_effects : effects
val add_impact : impact -> effects -> effects
val union_effects : effects -> effects -> effects
val has_effects : effects -> bool

type int_range = {
  soft_min : int;
  soft_max : int;
  hard_min : int option;
  hard_max : int option;
}

type float_range = {
  soft_min : float;
  soft_max : float;
  hard_min : float option;
  hard_max : float option;
}

type 'a choice = {
  options : (string * 'a) array;
  equal : 'a -> 'a -> bool;
}

type 'a encoding = {
  encode : 'a -> string;
  decode : string -> ('a, string) result;
  equal : 'a -> 'a -> bool;
}

type _ kind =
  | Toggle : bool kind
  | Integer : int_range -> int kind
  | Floating : float_range -> float kind
  | Text : string kind
  | Choice : 'a choice -> 'a kind
  | Encoded : 'a encoding -> 'a kind

type 'record field = Field : {
  name : string;
  label : string;
  description : string option;
  folder : string list;
  impact : impact;
  kind : 'value kind;
  default : 'value;
  get : 'record -> 'value;
  set : 'value -> 'record -> 'record;
} -> 'record field

type 'record schema

type value =
  | Bool_value of bool
  | Int_value of int
  | Float_value of float
  | Text_value of string
  | Choice_value of string

(** Renderer-independent, type-erased metadata for one concrete parameter
    instance. Choice values are represented by their public labels. *)
type kind_view =
  | Toggle_view
  | Integer_view of int_range
  | Floating_view of float_range
  | Text_view
  | Choice_view of string array

type field_view = {
  name : string;
  label : string;
  description : string option;
  folder : string list;
  impact : impact;
  kind : kind_view;
  default : value;
  current : value;
}

val integer :
  ?hard_min:int -> ?hard_max:int -> min:int -> max:int -> unit -> int kind

val floating :
  ?hard_min:float -> ?hard_max:float ->
  min:float -> max:float -> unit -> float kind

val choice : equal:('a -> 'a -> bool) -> (string * 'a) list -> 'a kind

val encoded :
  equal:('a -> 'a -> bool) ->
  encode:('a -> string) ->
  decode:(string -> ('a, string) result) ->
  'a kind
(** Expose a structured immutable value through a deterministic textual
    representation. This is the typed fallback for rule lists and nested
    values until a renderer adapter provides dedicated multiparm rows. The
    encoded form is also the cache-key representation. *)

val field :
  name:string ->
  ?label:string ->
  ?description:string ->
  ?folder:string list ->
  ?impact:impact ->
  kind:'value kind ->
  default:'value ->
  get:('record -> 'value) ->
  set:('value -> 'record -> 'record) ->
  unit ->
  'record field

val schema :
  name:string -> default:'record -> 'record field list -> 'record schema

val name : 'record schema -> string
val default : 'record schema -> 'record
val fields : 'record schema -> 'record field list
val mem : 'record schema -> string -> bool

(** Materialize type-erased inspector metadata for the supplied immutable
    record. This is the narrow boundary consumed by UI adapters. *)
val view : 'record schema -> 'record -> field_view list

(** Deterministic, unambiguous cache-key encoding of one concrete record.
    Custom SOP builders use this so PPX-exposed cook parameters and session
    cache identity cannot drift apart. *)
val key : 'record schema -> 'record -> string

(** Apply a named untyped UI value through its typed field template. [None]
    means the name was not part of this schema. Hard bounds normalize values;
    soft bounds do not. The returned impact is [None] when the effective value
    was unchanged. *)
val apply :
  'record schema ->
  'record ->
  name:string ->
  value ->
  (('record * impact option) option, string) result

(** Apply a batch in order and accumulate its cook/view/export effects. *)
val apply_all :
  'record schema ->
  'record ->
  (string * value) list ->
  ('record * effects, string) result

(** Validate and normalize every field in a record. *)
val normalize : 'record schema -> 'record -> ('record, string) result
