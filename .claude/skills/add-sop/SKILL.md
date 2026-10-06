---
name: add-sop
description: Register a new editor SOP node in rays's sop_catalog through the PPX. Use when a rdk or procedural operation needs a node in the sketch environment's node menu and inspector.
---

# Add a SOP node

1. Read `lib/sop_catalog/AGENTS.md`. The op must already exist in `rdk`
   (`add-rdk-op`). A node is declared once: the record below yields the
   schema, the manifest entry, the factory and the typed `Sop.<op>`.
2. In the matching `lib/procedural/sop_<family>.ml` (`groups`, `topology`,
   `attributes`, `shapes`), add one module. Its `parameters` record carries
   `[@@deriving sop_params, sop_node]` with `[@@sop.node_key "..."]`
   (stable, never reused), `[@@sop.node_label]`, `[@@sop.node_category
   "Group/Sub"]`, `[@@sop.node_inputs n]`, `[@@sop.fn "<op>"]` and
   `[@@sop.args "..."]` (the typed arguments in order: `?x` optional, `~x`
   labelled, `x` positional, a `sop.vec3` group as one `Vec3.t`, input slots,
   a trailing `()` for a generator). Fields declare `[@sop.default]`,
   `[@sop.label]`, and where needed `[@sop.min]`, `[@sop.max]`,
   `[@sop.hard_min]`, `[@sop.folder]`, `[@sop.kind]` for choices,
   `[@sop.nonblank "m"]` / `[@sop.validate "m"]` for what the typed
   constructor rejects, `[@sop.present "use_x"]` for a toggle a `?x` sets.
   Use `[@@sop.node_optional]` for optional input slots and
   `[@@sop.node_operation]` only when the menu key must differ from the
   runtime operation. Example, a one-input group node:

   ```ocaml
   module Group_unshared = struct
     type parameters = {
       owner : Rdk.Group_ops.owner [@sop.default Rdk.Group_ops.Group_edges]
         [@sop.label "Group type"] [@sop.kind group_owner_parameter];
       name : string [@sop.default "unshared"] [@sop.label "Group name"]
         [@sop.nonblank "empty output group name"];
       merge : Rdk.Group_ops.boolean_operation
         [@sop.default Rdk.Group_ops.Group_replace] [@sop.label "Operation"]
         [@sop.kind group_merge_parameter];
     } [@@sop.node_key "group_unshared"] [@@sop.node_label "Group Unshared"]
       [@@sop.node_category "Group/Create"] [@@sop.node_inputs 1]
       [@@sop.fn "group_unshared"] [@@sop.args "?merge ~owner ~name in0"]
       [@@deriving sop_params, sop_node]
     let build = parameters_build (fun ~label parameters input ->
       Node.Private.make ~label ~operation:"group_unshared" ~version:1 ~parameters:""
         ~cook_mode:(Node.Duplicate_input 0) ~dependencies:Context.Dependencies.static
         ~inputs:[|input|] (fun ~node_id:_ context inputs ->
           match Rdk.Group_ops.group_unshared ~cancel:(Context.cancel_token context)
               ~grain:(Context.grain context) ~merge:parameters.merge
               ~owner:parameters.owner ~name:parameters.name inputs.(0) with
           | Ok geometry -> cooked geometry
           | Error error -> structured_rdk_error error))
     let factory = parameters_factory build
     let fn = parameters_fn build
   end
   ```
3. Write the cook as above: `let build = parameters_build (fun ~label
   parameters input0 ... -> Node.Private.make ... )` with one argument per
   input slot (a `Node.t option` for an optional slot), `~parameters:""`
   (the schema is the cache identity), then `let factory =
   parameters_factory build` and `let fn = parameters_fn build`. Add
   `val <op> : ...` to `lib/procedural/sop.mli`, `let <op> =
   Sop_<family>.<Module>.fn` to `sop.ml`, `module <Module> =
   Sop_<family>.<Module>` to `nodes.ml` with `module <Module> : sig val
   factory : Edit_graph.factory end` in `nodes.mli`, and `module <Module> =
   Procedural.Nodes.<Module> [@@sop.register]` to
   `lib/sop_catalog/sop_catalog.ml`. A node the record cannot express (see
   `lib/sop_catalog/AGENTS.md`) keeps a hand-written `Sop.<op>` and a record
   in `lib/sop_catalog/<family>.ml` whose build forwards to it. Add a
   `create` to `sop_catalog.mli` only when code outside the library needs one.
4. Run `dune build @test/test_sop_catalog @lib/sop_catalog/runtest
   @lib/procedural/test_sop_nodes`: the catalog test rejects duplicate keys,
   instantiates every factory with placeholder inputs, and finds each key
   from the node menu; `test_sop_nodes` cooks a declared node through
   `Sop.<op>` and through its factory at one and four domains and compares
   the geometry, so add its case there. The PPX fixture lives in
   `test/sop_params_fixture.ml`. Review the generated `flow_manifest.sexp`
   diff and accept intended metadata changes with `dune promote`; `.rays`
   sketches are checked against this snapshot at build time.
5. If the node should appear in the gallery or an example, add it there;
   then `@all` and `git diff --check`.

Naming for Rays Flow (`specification/flow.md` §3.3, §11.4): the key is
the node's Lisp symbol verbatim (`sop/<key>`) and field names are its
keywords, so use `[a-z][a-z0-9_]*` and never rename a shipped key. Mark
default card rows with `[@sop.primary]`, group each `_x/_y/_z` float triple
with `[@sop.vec3 "<prefix>"]`, and name multi-input slots with
`[@@sop.node_slots "a, b"]`.
