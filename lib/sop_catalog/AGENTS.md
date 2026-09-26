# lib/sop_catalog rules

Define an inspectable editor SOP once in `sop_catalog`: keep its parameter
record, stable node key, runtime operation identity, display label, category
path, input arity, defaults, and rebuild closure together through
`[@@deriving sop_params, sop_node]`, then
mark the module `[@@sop.register]`. Write the node as
`let build = parameters_build (fun ~label parameters input0 ... -> Sop.op ...)`
and `let factory = parameters_factory build`; the generated build owns the
input-arity match, optional-slot presence, `Node.parameterize`, and the
schema-derived cache key, so never hand-write that boilerplate. Add a `create`
(and its `.mli` entry) only for a node with callers outside this library. The PPX-generated deterministic manifest is
the only node-menu registry. Do not add a parallel hand-written factory list,
mutable registration initializer, or menu-only parameter defaults. Catalog
tests must reject duplicate keys, instantiate every registered factory with
disconnected input placeholders, and prove that the resulting `Node.operation`
matches the descriptor identity. The workspace must obtain its
`Pxui_graph.catalog_entry` values only through
`Pxui_graph.catalog_of_factories`; tests must search the node menu by every
generated stable key and receive that exact factory request. Use
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
