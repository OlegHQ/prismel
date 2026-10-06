# One description per SOP: migration strategy

Date: 2026-10-06. Base: `audit-cleanup`, plus the pilot on branch `sop-one-declaration`.
Status: design. Nothing here is implemented beyond the pilot.

## 1. Goal

Every SOP node is described once. From that one description a PPX derives everything that
must agree:

- the Lisp form (`sop/<key>`, its keywords, defaults and ranges: `flow_manifest.sexp`),
- the editor (node menu entry, card rows, inspector fields),
- the OCaml function (`Procedural.Sop.<key>`),
- validation, the cache key, and the `Node.parameters` text.

OCaml and Lisp say the same thing: same parameter names, same defaults, same ranges, same
errors. `rdk` stays the lower level: it keeps its structured kernel API and knows nothing of
nodes. No node and no capability is removed. Mechanical edits are done by codemods.

## 2. Where we are (measured)

| Fact | Number | Source |
|---|---|---|
| Typed functions in `Procedural.Sop` | 165 | `sop.mli` |
| Already on one description (pilot) | 36 | `sop-one-declaration` |
| Still declared twice | 123 nodes | `sop_merge --dry-run` over every catalog module |
| Typed call sites in `lib/procedural` tests | 1,519 | grep `Sop.<f>` |
| Typed call sites in examples, sketches, `sketch_support`, `test/` | 134 | grep |
| Test references to `Node.parameters` text | 362 | grep |
| Defaults that differ between the two declarations | 10 parameters on 7 nodes | pilot report |

The pilot proved the mechanism without regression (`sop.mli` and the manifest unchanged, no
test edited, byte-identical cooks on one and four domains). It stopped at 36 because it was
not allowed to change either door. The remaining 123 are blocked for these reasons, as the
codemod reports them:

| # | Why the two declarations cannot be merged as they are | Nodes |
|---|---|---|
| A | The catalog `build` computes typed arguments from fields before calling `Sop.f` (for example a choice `Any \| Owner o` becomes `?owner`) | 36 |
| C | A typed argument is one structured value (a filter, a range, a matrix, a colour, a projection) that the record spreads over several fields | 26 |
| B | The typed function is not one `Node.Private.make`: it returns its input when the edit is the identity, or builds several nodes (Transform, the `Set_*` family, Boolean) | 17 |
| H | Small shape differences: no parameters record (Merge, Null, Switch, Compact Points), a positional argument that is not an input, a vec3 default written another way | 12 |
| D | An optional typed argument whose absence means "the kernel decides" (`?normals` on Box, UV Sphere, Torus, Tube; `?seed` on Mountain, Point Jitter, Attribute Noise Quaternion; `?width` on Grid; `?epsilon` on Clean) | 9 |
| F | A hand check the record cannot state yet (a range that differs from the field's hard range, a pattern validated per item) | 8 |
| E | An optional text whose editor default is not the empty string | 6 |
| G | The typed function has a parameter the editor does not offer (`selection` on Clip, Peak, Bend, Normal; `target_attributes` on Copy to Points; `generated_group` on Point Generate) | 6 |
| I | Mergeable, but a test pins old behaviour (Crease and Poly Path accept NaN at construction; Swap Attributes asserts a hand key spelling) | 3 |

Every row is the same underlying fact: **the OCaml door and the Lisp door have different
shapes.** A, C and D are where OCaml is richer in form; G is where OCaml is richer in function;
I and the ten default drifts are where they simply disagree. One description is possible only
after the two doors are given one shape.

## 3. Target

### 3.1 The layers

| Layer | Owns | Changes |
|---|---|---|
| `rdk` | Structured kernel operations (`Group_ops.range ~filter ~connectivity …`), their errors, parallel exactness | none |
| `procedural` node descriptions (`sop_<family>.ml`) | One record per node, its attributes, and the cook: record → `rdk` call | all 165 nodes live here |
| `Procedural.Sop` | Generated typed constructors, one per node | hand-written bodies, keys and checks deleted |
| `sop_catalog` | The registration list and the generated manifest | the four node files are gone |
| Lisp, editor | Read the manifest and the factories | none |

### 3.2 The description

The shape is the pilot's (see `Group_unshared` on the branch). Group Invert, one of the
category A nodes, would read as follows; the cook is abbreviated and its helper names are
illustrative:

```ocaml
module Group_invert = struct
  type parameters = {
    owner : owner [@sop.default Any] [@sop.label "Group type"] [@sop.kind owner_parameter];
    pattern : string [@sop.default "*"] [@sop.label "Group pattern"];
    new_name : string option [@sop.label "New name pattern"];
    conflict : Rdk.Group_ops.rename_conflict [@sop.default Rename_overwrite] [@sop.label "Conflict"];
  } [@@sop.node_key "group_invert"] [@@sop.node_label "Group Invert"]
    [@@sop.node_category "Group/Edit"] [@@sop.node_inputs 1]
    [@@deriving sop_params, sop_node]

  let build = parameters_build (fun ~label p input ->
    let owner = match p.owner with Any -> None | Owner o -> Some o in   (* flat -> rdk, once *)
    node ~label ~operation:"group_invert" ~inputs:[| input |] (fun context inputs ->
      Rdk.Group_ops.invert ?owner ~pattern:p.pattern ?new_name:p.new_name ~conflict:p.conflict inputs.(0)))
end
```

What the PPX derives from it, with nothing else written by hand:

- `Sop.group_invert : ?label:string -> ?owner:owner -> ?pattern:string -> ?new_name:string -> ?conflict:… -> Node.t -> Node.t`.
  **Every field is an optional labelled argument with the record's default**; a
  `[@sop.vec3]` group is one `Vec3.t` argument; an `option` field is an argument with no
  default; inputs are positional in slot order. This is the Lisp call
  `(sop/group_invert in :owner "Any" :pattern "*")` spelled in OCaml.
- The schema, the manifest entry, the factory (as today).
- Validation from the ranges: the typed function raises `Invalid_argument "Sop.group_invert: …"`,
  the editor clamps or refuses the field, the Lisp checker reports `E_HARD_RANGE`. One range, three reporters.
- The cache key (`Parameter.cook_key`) and `Node.parameters` (`Parameter.cook_text`).

The only hand-written code per node is the record and the cook. The flat-to-structured
mapping that today sits in the catalog `build` stays, in the cook, exactly once.

### 3.3 The rules that make OCaml and Lisp agree

| Rule | Consequence |
|---|---|
| **R1. The record is the signature.** The typed function takes the record's fields, not structured `rdk` values. | Categories A and C disappear: there is one shape. Code that wants a structured value calls `rdk`, the lower level, or `Procedural.Custom`. |
| **R2. One default.** `[@sop.arg_default]` (the pilot's drift marker) is deleted. | The ten drifts are settled once (§5, step 1). |
| **R3. "Not given" is a value.** A parameter the kernel may decide is an `option` field: absent in Lisp, unset in the inspector, `?x` without a default in OCaml. | Category D and E. Lisp gains the ability to leave `:normals` to the kernel, which only OCaml had. |
| **R4. Nothing OCaml-only.** A typed parameter the editor lacks becomes a field. | Category G: Lisp and the editor gain `selection`, `target_attributes`, `generated_group`. |
| **R5. One validation time.** Values are checked when the node is constructed, by the schema, for both doors. | Category F and I: NaN is refused at construction, not at cook. |
| **R6. A build may return any node.** Identity short-cuts and multi-node expansions are ordinary `build` bodies. | Category B needs no new mechanism: the pilot's generated function already calls `build`. |

R1 is the decision that matters. It changes the spelling of 85 typed signatures and of the
call sites that use them. It removes no capability, on one condition that the migration
checks per node: **the record must be able to say everything the structured argument could.**
Where it cannot, the record is extended first (R4), and only then is the signature changed.

### 3.4 What is simplified

| Today | After | Estimate |
|---|---|---|
| 169 `*_key` helpers and about 900 `"name=" ^` lines in `sop.ml` | derived key | −1,100 lines |
| 244 `invalid_arg` checks repeating ranges | derived from `[@sop.min/max/hard_*]` | −500 |
| 123 typed function headers with their own defaults | derived signature | −1,500 |
| `lib/sop_catalog/{shapes,topology,attributes,groups}.ml` forwarding builds | merged into the cook | −1,500 |
| `sop.mli` (2,374 lines of signatures) | kept as the documented API, checked against the derivation by a test | 0 |
| `tools/sop_merge` (721 lines), `[@sop.fn]`, `[@sop.args]`, `[@sop.arg_default]`, `[@sop.present]`, `[@sop.absent]` | deleted at the end: with R1 the signature needs no annotation | −900 |

The estimates extrapolate from the pilot (36 nodes removed about 1,400 lines of node code)
and are not measured. Expect a net reduction of 4–6k lines once the temporary tooling is gone.

## 4. No regression: the gates

Each commit passes all of these. A node that cannot pass stays as it is and is listed.

| Gate | How it is checked |
|---|---|
| The Lisp surface only grows | `flow_manifest.sexp` diff shows additions only (new optional fields from R3/R4); no key, field, default or range of an existing field changes. Every checked-in `.rays` still passes `rays-lisp check`. |
| Geometry is identical | For every node: cook through the typed function and through the factory with the same values, one and four domains, compare bytes (the pilot's `test_sop_nodes`, extended to all nodes). |
| OCaml agrees with Lisp | New generated test, for every node and every field: the node from `(sop/x :field v)` and from `Sop.x ~field:v` have the same cook key; with no arguments both have the manifest's defaults. |
| No test is deleted or weakened | Existing tests change only by the call-site codemod (§5, step 3); its diff is spelling only. `codemod --cut-tests` is never used. The parallel exactness suite runs unchanged in what it asserts. |
| Cache behaviour | Equal values hit the session cache, each changed field misses it (pilot test, all nodes). |
| Performance | `bench_rdk_ops` (`polywire_long_spine`, one domain) and `bench_workspace_lower` before and after each family; no measurable change, numbers in the commit. |
| Boundaries | `test/dependency_gate.ml` unchanged: `procedural` reaches no UI library, `rdk` does not reach `procedural`. |

## 5. Steps

Each step is one or a few commits, each green on
`dune build @lib/procedural/runtest @lib/sop_catalog/runtest @lib/rdk/runtest @test_sop_catalog`,
with the full `tools/check.exe --ship` at the end of every step.

| Step | What | How | Unblocks |
|---|---|---|---|
| 0 | Merge `sop-one-declaration` | It contains `audit-cleanup`; re-promote the API manifest. | the mechanism, 36 nodes |
| 1 | **Settle the ten default drifts (R2).** | Codemod `sop_explicit`: at every OCaml call site that omits a drifted argument, write the old typed default explicitly. Run tests (nothing changes). Then delete `[@sop.arg_default]`: the typed default becomes the Lisp default. | one default everywhere |
| 2 | **PPX: `option` fields (R3), derived checks (R5).** | Hand work in `ppx_rays` and `Parameter`: an `option` field has no default, prints as absent, and shows as an unset inspector row; `[@sop.validate]` covers per-item pattern checks and ranges narrower than the hard range. Tests in `ppx/ppx_rays/test_sop_metadata.ml`. | D, E, F (23 nodes) |
| 3 | **Flat signatures (R1), one family at a time.** | Codemod `sop_flatten`, per node: (a) derive the typed signature from the record; (b) rewrite every call site from the structured spelling to the flat one. The rewrite table comes from the node's own forward mapping: a `Parameter.choice` list is a label ↔ value table, and a `match p.field with C x -> …` in the build inverts mechanically for constructor patterns. A site it cannot rewrite (a computed structured value) is printed and left failing to compile, to be fixed by hand. Order: groups, topology, attributes, shapes. | A, C (62 nodes) |
| 4 | **Add the OCaml-only parameters as fields (R4).** | Hand work per node (six nodes): the field, its encoding (a selection is a group name plus its element kind, which `Shared.optional_element_group` already builds for the nodes that offer one), a cook test. Manifest diff: additions only. | G (6 nodes) |
| 5 | **Merge the rest.** | `sop_merge` on B and H; the three nodes of category I after their tests are updated to construction-time refusal (R5), each change listed in the commit. | B, H, I (32 nodes) |
| 6 | **Delete what is dead.** | `codemod prune lib/procedural lib/sop_catalog` (without `--cut-tests`), then `drop-unused` to a fixpoint for the key helpers. Delete the four emptied catalog files, `Shared` helpers that moved, `tools/sop_merge`, and the pilot's signature attributes. | the simplification in §3.4 |
| 7 | **Lock it.** | A gate test: every value in `sop.ml` is an alias of a generated function, and `Node.Private.make` with a non-empty `~parameters` appears nowhere in `lib/procedural`. Update `lib/sop_catalog/AGENTS.md`, `.claude/skills/add-sop/SKILL.md`, `specification/procedural.md`. | it stays one description |

Step 3 is the large one: about 1,650 call sites, most of them plain values
(`~name:"edges"`, `~tolerance:1e-6`) that do not change at all. The ones that change are
those passing a structured value for the 62 nodes of A and C. The codemod's dry run gives the
exact count per node before anything is edited; run it first and review the list of sites it
cannot rewrite.

## 6. Decisions for the owner

| # | Decision | Recommendation |
|---|---|---|
| 1 | **R1: may the typed OCaml signatures become flat (the Lisp shape)?** This is the one change existing OCaml callers see. | Yes. It is what makes "one description" possible; the structured form remains available one level down in `rdk`. |
| 2 | Which default wins for each of the ten drifts (table in the pilot report: Box connectivity, the two boundary tolerances, Name from Groups overlap, Group Copy/Transfer conflict, Dissolve's two, Clean's four) | The Lisp/editor default: `.rays` files in use depend on it, and step 1 pins every OCaml caller to its old value first. |
| 3 | R5: NaN and other invalid values are refused when a node is constructed, for both doors (today the typed door sometimes defers to the cook) | Yes: it is the earlier, typed error, and the editor already behaves this way. |
| 4 | Keep `sop.mli` hand-written (documentation, checked by a test) or generate it | Keep and check. The root rule is that every public module has an `.mli`. |

## 7. Risks

| Risk | Mitigation |
|---|---|
| A record cannot express what a structured argument could, so R1 would cut a capability | Per node, before its signature changes: the codemod lists typed argument shapes with no flat spelling; those get fields first (step 4). No node is flattened with an open item. |
| The call-site rewrite changes a value | It rewrites spelling only, and the byte-comparison gate runs the rewritten tests against the same expected geometry. |
| A test asserts a hand key spelling in `Node.parameters` | `cook_text` keeps the dominant spelling. For the rest the codemod rewrites the expected substring from an old-name → field-name table and prints each one. |
| The work stalls half-way and leaves two styles for longer | Every step is useful alone and leaves the tree green. Steps 1, 2 and 4 improve agreement even if step 3 is never done. |
| `procedural` now needs the PPX at build time | Already true on the pilot branch; the gate passes, the PPX reaches only `flow` and `param`. |

## 8. What this does not do

- It does not change `rdk`, the cook results, or any node's meaning.
- It does not touch the scene, World, editor-layout or value operators: they have one door
  and one declaration already.
- It does not make `sop_catalog` disappear: registration order and the manifest stay there.
