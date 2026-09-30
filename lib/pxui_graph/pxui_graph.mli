(** The graph pane of a workspace document and its node menu.  The pane presents one
    {!Flow_sop.Projection.scope}; it returns typed requests and never edits. *)

(** The workspace pane: zones, rails, iteration selectors, chips and typed sockets. *)
module Scope = Scope_pane

(** The categorised menu of the kinds a graph can add. *)
module Node_menu = Node_menu
