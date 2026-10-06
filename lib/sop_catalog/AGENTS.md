# lib/sop_catalog rules

A SOP node is declared once. The declaration is its `parameters` record with
`[@@deriving sop_params, sop_node]`, which yields the inspector schema, the
Lisp manifest entry, the editor factory and, with `[@@sop.fn "name"]
[@@sop.args "..."]`, the typed `Procedural.Sop.name` constructor, next to the
cook that reads the record. Such a declaration lives in `lib/procedural`
(`sop_groups.ml`, `sop_topology.ml`, `sop_attributes.ml`, `sop_shapes.ml`;
`Sop_support` holds their helpers, `Procedural.Nodes` exports the factories,
`sop.ml` aliases the typed function) and is registered here as
`module X = Procedural.Nodes.X [@@sop.register]`. A node whose typed
constructor the record cannot express (a structured rdk argument the record
flattens, a `Select.t`, a closure, an optional whose absence means the kernel
default, a check that is not blank/finite/hard-range) keeps its typed
function hand-written in `sop.ml` and its record in the matching private
file here (`shapes.ml`, `topology.ml`, `attributes.ml`, or `groups.ml`) with
`let build = parameters_build (fun ~label parameters input0 ... -> Sop.op ...)`
and `let factory = parameters_factory build`; the generated build owns the
input-arity match, optional-slot presence, `Node.parameterize` and the
schema-derived cache key, so never hand-write that boilerplate, and
`shared.ml` holds the common helpers. `tools/sop_merge` converts a hand-written
pair into one declaration and prints why it cannot. Add a `create` (and its
`.mli` entry) only for a node with callers outside this library. The
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

For SOP-backed inspectors, declare typed templates beside each operator with
`Procedural.Parameter` (or `[@@deriving sop_params]`) and attach them to that
node. Use `Procedural.Custom.node/create/map` for custom parameterized nodes,
and `Pxui_shell.Inspector.fields` plus `Node.apply_parameters` for selected-node
editing. Do not recreate a sketch-wide shadow parameter record, copy
names/defaults/ranges into hand-built widgets, or make `procedural` import
PXUI.

Workflow for a new node: the `add-sop` skill.

Typed-function attributes (`[@@sop.fn]` nodes only): `[@@sop.args "?a ~b c ()"]`
lists the arguments of `Sop.name` in order, each a field, a `sop.vec3` group
(one `Vec3.t`), an input slot or a trailing `()`; `~x=field` names an
argument differently from its field. A `?x` takes the editor default unless
`[@sop.arg_default e]` overrides it (a listed drift between the editor and
the typed API). `[@sop.nonblank "m"]` on a text and `[@sop.validate "m"]` on
a number (finite and within the hard range) raise `Invalid_argument "Sop.name:
m"` from the typed constructor only; the editor clamps. `[@sop.present
"use_x"]` / `[@sop.absent "context_seed"]` set a toggle field from a `?x`'s
presence. `Node.parameters` of such a node is `Parameter.cook_text` of its
values (`name=value;...`).

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
