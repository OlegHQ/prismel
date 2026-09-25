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
3. `build ~label ~inputs parameters` makes one `Sop.<op>` call and pipes it
   through `Node.parameterize ~schema:parameters_schema ~values:parameters
   ~rebuild:build`; `factory = parameters_factory build`. No hand-written
   factory list, cache key, or menu defaults: the PPX derives them.
4. Run `dune build @test/test_sop_catalog`: it rejects duplicate keys,
   instantiates every factory with placeholder inputs, and finds each key
   from the node menu. Add a case there only if the node needs behaviour
   beyond registration; the PPX fixture lives in `test/sop_params_fixture.ml`.
5. If the node should appear in the gallery or an example, add it there;
   then `@all` and `git diff --check`.
