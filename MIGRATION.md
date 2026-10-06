# One description per SOP: migration strategy

Date: 2026-10-06. Base: `audit-cleanup` plus the pilot branch `sop-one-declaration`.
Status: decided, not started. Only the pilot is implemented.

## Goal

A SOP node is described once, by its parameter record. The existing PPX derives the Lisp
form, the editor fields, the OCaml function `Procedural.Sop.<key>`, validation and the cache
key from it, so OCaml and Lisp cannot disagree. `rdk` is the lower level and does not change.
No node and no capability is removed. Mechanical edits go through codemods.

## Where we are (measured)

- 165 typed functions, 159 of them with a node; 36 nodes are on one description (pilot, no regression: `sop.mli` and the
  manifest unchanged, no test edited, byte-identical cooks on one and four domains).
- 123 nodes are still declared twice. `sop_merge --dry-run` over each gives the reason:

| | Why the two declarations do not merge today | Nodes |
|---|---|---|
| A, C | OCaml takes a structured value where Lisp has flat fields; the catalog `build` converts | 62 |
| B, H | The typed function returns its input or builds several nodes; or a small shape difference (no record: Merge, Null, Switch) | 29 |
| D, E | "Not given" means the kernel decides (`?normals` on Box, `?seed` on Mountain, an optional text) | 15 |
| F, I | A hand check the record does not state; a test that pins NaN accepted at construction | 11 |
| G | OCaml has a parameter the editor lacks (`selection` on Clip, Peak, Bend, Normal; two more) | 6 |

- 10 defaults differ between the two declarations (Box connectivity is triangles in OCaml,
  quads in Lisp; list in the pilot report).

One cause sits under every row: the OCaml door and the Lisp door have different shapes.

## Target

The record is the signature. Per node, two things are written by hand: the record and the
cook (record → `rdk` call). The conversion from flat fields to structured kernel values that
the catalog `build` does today stays in the cook, once.

```ocaml
(* Lisp:  (sop/group_invert in :owner "Points" :pattern "top*") *)
Sop.group_invert ~owner:(Owner Group_points) ~pattern:"top*" input
```

Four rules:

1. **Flat.** Each field is an optional labelled argument with the record's default; a vec3
   group is one `Vec3.t`; inputs are positional. Structured values are for callers of `rdk`.
2. **One default**, the Lisp one.
3. **"Kernel decides" is a choice**, not an absent argument: an `"Auto"` entry in the
   field's existing choice list (Group Invert already does this with `Any`). Lisp gains it.
4. **Nothing OCaml-only.** A typed parameter the editor lacks becomes a field. Lisp gains it.

## Steps

Each step leaves the tree green and is worth having without the next one.

| | Step | How | Nodes |
|---|---|---|---|
| 1 | Merge the pilot. Run `sop_merge` on B and H. | Existing tool; they need no decision. | 36 + 29 |
| 2 | Settle the 10 drifts. | Codemod: write the old OCaml default explicitly at each call site that omits it (tests then cannot change), then delete `[@sop.arg_default]`. | — |
| 3 | D, E: add the `"Auto"` choice. F: move the check into `[@sop.validate]`, which the pilot already has. I: update the three tests to refusal at construction, listed in the commit. Then `sop_merge`. | Hand edit of the record, tool for the merge. | 26 |
| 4 | G: add the six fields, each with a cook test. | Hand; `Shared.optional_element_group` already encodes a selection. | 6 |
| 5 | A, C: flatten, one family per commit. | Change the signature, build, and let the compiler list the call sites that pass a structured value. Rewrite those with `codemod rename` plus a per-node table of constructor → field spelling; what the table cannot say is fixed by hand and listed. Then `sop_merge`. | 62 |
| 6 | Delete what is dead. | `codemod prune` and `drop-unused` (never `--cut-tests`); remove the emptied catalog files, `tools/sop_merge`, and the pilot's `[@sop.fn]`, `[@sop.args]`, `[@sop.arg_default]`. | — |

Steps 1 to 4 need no change to any existing OCaml caller except the explicit defaults of
step 2, and bring 97 of 159 nodes to one description. Step 5 is the only large one: 1,650
typed call sites exist, but only those passing a structured value to one of 62 functions
change. Take the count from the compiler before starting it.

## No regression

The pilot's `test_sop_nodes` already does this for 36 nodes; extend it to every node as it
is merged, nothing new is needed:

- cook through the typed function and through the factory with the same values, one and four
  domains, compare bytes (this is also the "OCaml agrees with Lisp" check);
- equal values hit the session cache, each changed field misses it.

Plus, per commit: `flow_manifest.sexp` shows additions only; every checked-in `.rays` passes
`rays-lisp check`; no existing test is deleted, and test edits are the codemod's spelling
changes only; `bench_rdk_ops` and `bench_workspace_lower` show no change at the end of each step.

## Decisions (owner, 2026-10-06)

Lisp is the first-class surface; OCaml is second-class, for tests and integrations
(`AGENTS.md`, Direction). So:

1. The OCaml signatures become flat, the Lisp shape (step 5 goes ahead).
2. The Lisp default wins all 10 drifts.
3. Invalid values are refused when a node is constructed, as the Lisp checker and the editor
   already do; the three tests that pin the old OCaml behaviour change. This one follows from
   the rule above and was not stated separately: say so if the cook-time diagnostic should stay.

## Skipped on purpose

- New PPX features (`option` fields, derived range checks): the `"Auto"` choice and the
  existing `[@sop.validate]` cover the same nodes. Add when a node needs a value no choice
  list can hold.
- A separate OCaml-versus-Lisp agreement test and a "no hand-written node" gate test: the
  byte comparison covers the first; the second is one `grep` in review once step 6 is done.
- Generating `sop.mli`: the compiler already checks it against the derived functions.
- An automatic inverter of the `build` mappings for step 5: the compiler finds the sites and
  a rename table rewrites them.
- Line-count promises: the pilot removed about 1,400 lines of node code for 36 nodes; the
  rest is not measured.
