# lib/sop_catalog rules

A SOP node is declared once. Its `parameters` record with
`[@@deriving sop_params, sop_node]` yields the inspector schema, Lisp manifest
entry, editor factory and typed constructor, next to the cook that reads it.
The constructor uses the node key for its identity, optional fields in record
order (one `Vec3.t` per vector group), then positional input slots; a generator
ends in `()`. Defaults come only from the record. Do not add a separate function
name, argument list, typed default override or argument-presence toggle.
Declarations live in `lib/procedural` (`sop_groups.ml`, `sop_topology.ml`,
`sop_attributes.ml`, `sop_shapes.ml`; `Sop_support` holds shared helpers).
`Procedural.Nodes` exports their factories, `sop.ml` aliases their typed
functions, and this library registers them as
`module X = Procedural.Nodes.X [@@sop.register]`.
A parameter-free node uses `type parameters = unit` with the same derivation;
do not invent a field. Structured kernel arguments are assembled in the cook.
Add a `create` (and its `.mli` entry) only for callers outside the library. The
PPX-generated deterministic manifest is the only node-menu registry. Do not add a parallel hand-written factory list,
mutable registration initializer, or menu-only parameter defaults. Catalog
tests must reject duplicate keys, instantiate every registered factory with
disconnected input placeholders, and prove that the resulting `Node.operation`
matches the descriptor identity. The editor must obtain its node-menu entries
(`Pxui_graph.Node_menu.entry`) only through
`Pxui_graph.Node_menu.entries_of_factories`; tests must search the node menu by every
generated stable key. Use
`[@@sop.node_operation "..."]` only when
the menu key intentionally differs from the runtime operation; otherwise it
defaults to the key.

Model SOP ports as required/optional signatures rather than forcing every node
into a fixed required arity. Use `[@@sop.node_optional "..."]` for optional
zero-based slots. An absent optional slot must compile as an omitted operator
argument; connecting or disconnecting it must preserve the logical node ID,
parameter values, graph position, and deterministic input order.
Use `[@@sop.node_rest n]` for a final repeated slot. Its typed and cook
arguments are `Node.t list`; the factory filters disconnected additional
slots in order. A required Rest list is nonempty and follows required inputs.
Include its index in `[@@sop.node_optional "..."]` for Optional_rest, whose
list may be empty and whose prefix may contain fixed optional slots. Those
fixed slots retain their positions when additional inputs are disconnected.

For input-dependent presentation, use `parameters_build ~schema:(fun parameters
node -> ...)` to derive the schema from the operator's actual `Node.inputs`.
The builder evaluates the operator once and refreshes the schema after parameter
edits or rewiring. Reuse the declared fields and defaults; an `Index_choice`'s
labels remain integer values for cache keys and drives. Ordinary nodes omit this
callback.

For SOP-backed inspectors, declare typed templates beside each operator with
`Procedural.Parameter` (or `[@@deriving sop_params]`) and attach them to that
node. Use `Procedural.Custom.node/create/map` for custom parameterized nodes,
and `Pxui_shell.Inspector.fields` plus `Node.apply_parameters` for selected-node
editing. Do not recreate a sketch-wide shadow parameter record, copy
names/defaults/ranges into hand-built widgets, or make `procedural` import
PXUI.

Workflow for a new node: the `add-sop` skill.

Typed boundary checks: `[@sop.nonblank "m"]` on a text and
`[@sop.validate "m"]` on a number (finite and within the hard range) raise
`Invalid_argument "Sop.<key>: m"` from the typed constructor; the editor clamps
its numeric fields. `Node.parameters` uses `Parameter.cook_text` of the values.
Use `[@@sop.validate fun parameters -> ...]` on the record for a pure check
that involves several fields or encoded values. It runs before operator
construction for typed calls and factory rebuilds; inspector writes return
constructor validation failures as errors while keeping the existing node.

## Rays Flow (`specification/flow.md`)

Stable node keys become Lisp symbols verbatim (`sop/uv_sphere`) and field
names become keywords (`:size_x`), so keys match `[a-z][a-z0-9_]*` and are
never renamed without an alias. The PPX supports:
`[@sop.primary]` (sets `Param.field.primary`), `[@sop.vec3 "center"]` on three float fields (one vec3
parameter), and `[@@sop.node_slots "a, b"]`
(slot names; a slot name may not equal a field or group name). Use the
common prefix for a vector group, or `<prefix>_vector` if a field already
uses that prefix (Ray uses `direction_vector`). Every factory with multiple
inputs names its slots in their existing order; without the attribute slots are
`in0`, `in1`, .... Generated factories carry field metadata for the node menu's
search, and the inspector uses the same schema for pins and vector rows.
Value operators (`+`, `range`, `value/rand`, ...) are built into `lib/flow`, never here.
`lib/sop_catalog/flow_manifest.sexp` is generated from the registered factories
and the scene, World and settings kinds of `Editor_document.Contexts`. Its runtest rule diffs the live catalog; accept an
intended metadata change with `dune promote`, as for the API manifest.
`lib/flow`'s tests read this snapshot (`Flow.Check.catalog_of_manifest`); `rays-lisp` checks a
`.rays` sketch against the live catalog at build time, and the generated binary compares the
catalog digest it was built with.
