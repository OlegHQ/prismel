---
name: add-sop
description: Register a new editor SOP node in prismel's sop_catalog through the PPX. Use when a pdk or procedural operation needs a node in the sketch environment's node menu and inspector.
---

# Add a SOP node

1. Read `lib/sop_catalog/AGENTS.md`. The op must already exist in `pdk`
   (`add-pdk-op`) with a `Procedural.Sop` wrapper; the catalog only binds
   parameters to it.
2. In `lib/sop_catalog/sop_catalog.ml`, add one module ending in
   `end [@@sop.register]`. Its `parameters` record carries
   `[@@deriving sop_params, sop_node]` with `[@@sop.node_key "..."]`
   (stable, never reused), `[@@sop.node_label]`, `[@@sop.node_category
   "Group/Sub"]`, and `[@@sop.node_inputs n]`. Fields declare
   `[@sop.default]`, `[@sop.label]`, and where needed `[@sop.min]`,
   `[@sop.max]`, `[@sop.hard_min]`, `[@sop.folder]`, or `[@sop.kind]` for
   choices. Use `[@@sop.node_optional]` for optional input slots and
   `[@@sop.node_operation]` only when the menu key must differ from the
   runtime operation. Copy a neighbouring module such as `Platonic`.
3. Write `let build = parameters_build (fun ~label parameters input0 ... ->
   Sop.<op> ~label ... input0)` with one argument per input slot (a
   `Node.t option` for an optional slot), then
   `let factory = parameters_factory build`. The generated build checks the
   input shape, attaches the schema, rebuilds after edits, and derives the
   cache key from every cook field. No hand-written factory list, cache key,
   input match, or menu defaults. Add a `create` to `sop_catalog.mli` only when
   code outside the library needs one.
4. Run `dune build @test/test_sop_catalog`: it rejects duplicate keys,
   instantiates every factory with placeholder inputs, and finds each key
   from the node menu. Add a case there only if the node needs behaviour
   beyond registration; the PPX fixture lives in `test/sop_params_fixture.ml`.
5. If the node should appear in the gallery or an example, add it there;
   then `@all` and `git diff --check`.
