# Boolean stability and differential gate

This protocol is the release gate for Boolean robustness claims. Passing unit,
visual, and generated regressions is necessary but does not establish parity
with another production modeler. In particular, “not worse than Houdini” means
the measured outcome below on the same checked corpus, machine, operation, and
policy. It never means identical triangulation or an inference from Prismel's
own verifier.

## Reproducible local campaign

`tools/boolean_stress.exe` constructs four deterministic adversarial families:
nearly coplanar divided boxes, rotated dense ellipsoids, a torus/star-prism
intersection, and a multi-component drill bank. Quick, standard, and full
density levels use the same recipes. Every product checks finite coordinates,
closed two-manifold incidence, or even incidence for XOR/Shatter's intentional
paired walls; exact Shatter group partition; signed-volume Boolean identities;
and byte-for-byte packed position/topology equality between one-domain and
repeated multi-domain runs. CSV includes output cardinality, median wall time,
current-domain allocation, and volume.

```sh
opam exec --switch=. -- dune exec tools/boolean_stress.exe -- \
  --level quick --domains 4 --repeats 2 --grain 128 > prismel-quick.csv

/usr/bin/time -v timeout 30m \
  opam exec --switch=. -- dune exec tools/boolean_stress.exe -- \
  --level full --domains 4 --repeats 5 --grain 256 > prismel-full.csv
```

Use one process per third-party asset so an external timeout or crash identifies
one stable case. The OBJ reader accepts polygon faces and preserves their point
and primitive order:

```sh
timeout 10m opam exec --switch=. -- dune exec tools/boolean_stress.exe -- \
  --case turbine_housing_slot \
  --left-obj corpus/turbine_housing.obj \
  --right-obj corpus/slot_cutter.obj \
  --domains 4 --repeats 3 --operation difference
```

Add `--resolve-left-self-intersections` or
`--resolve-right-self-intersections` only when that treatment is part of the
case manifest; it changes the modeled input contract and must match the oracle.

A release corpus should cover, with license/source/hash metadata beside each
pair: production CAD-like hard surfaces, scanned/organic triangulations,
high-genus and disconnected solids, thin walls and high-aspect triangles,
coplanar and near-coplanar contacts at several scales, dense mixed polygon
valences, and repeated CSG chains. Assets that cannot be redistributed stay in
the local corpus; a minimized synthetic reproducer belongs in the repository.
Peak RSS and process exit/timeout status come from the outer runner rather than
an in-process estimate.

## Licensed Houdini oracle

`--export-dir` writes the exact generated left/right OBJ pairs. The optional
Houdini adapter must be run using the installed `hython`; importing `hou`
checks out a Houdini license. It creates an installed Boolean 2.0 SOP, selects
parameters by their displayed menu labels, cooks the same solid inputs, records
the installed Houdini version, warnings, topology incidence, volume, and cook
time, and exports the result for inspection.

The comparator requires Union, Intersection, A-minus-B, and Shatter rows for
every case by default. Missing or duplicate rows, malformed/non-finite metrics,
and non-passing oracle rows fail the gate (an oracle failure is reported as
inconclusive, never as a Prismel pass). Use `--required-operations` only for a
deliberately narrower campaign; Prismel-only reverse subtraction and XOR rows
are ignored by the cross-engine comparison.

```sh
mkdir -p _boolean_oracle/inputs _boolean_oracle/houdini
opam exec --switch=. -- dune exec tools/boolean_stress.exe -- \
  --level full --domains 4 --repeats 5 \
  --export-dir _boolean_oracle/inputs > _boolean_oracle/prismel.csv
hython tools/houdini_boolean_oracle.py \
  _boolean_oracle/inputs _boolean_oracle/houdini
python3 tools/compare_boolean_stability.py \
  _boolean_oracle/prismel.csv _boolean_oracle/houdini/houdini.csv
```

The common semantic comparison is Union, Intersection, A-minus-B, and Shatter.
Prismel fails the comparative gate if it crashes, times out, emits invalid
topology, or fails a case that the Houdini run passes; if both pass, absolute
signed volumes must agree within the declared relative tolerance. Cook-time
ratios are always reported. A performance threshold is a separate explicit
`--max-slowdown` policy because hardware, Houdini build, allocator setup, and
license environment materially affect it. XOR and Prismel-specific treatment
policies remain native regressions unless an oracle exposes the same contract.

The adapter follows SideFX's documented
[Boolean 2.0](https://www.sidefx.com/docs/houdini/nodes/sop/boolean.html),
[Hython licensing](https://www.sidefx.com/docs/houdini/hom/commandline), and
[geometry file I/O](https://www.sidefx.com/docs/houdini/hom/hou/Geometry.html)
boundaries. SideFX itself notes that repeated, extremely detailed procedural
Booleans can introduce microscopic self-intersections. Repeated CSG therefore
belongs in the shared corpus and is not treated as a failure unique to either
engine without running both.

## Publication rule

A result report records Prismel commit, OCaml/compiler profile, domain count,
machine/OS, Houdini version, exact corpus hashes and licenses, command lines,
timeouts, peak RSS, per-case diagnostics, and all minimized failures. “Not
worse” may be stated only for that recorded corpus and thresholds. Missing
Houdini, a license failure, an adapter/schema mismatch, or a Houdini-failing
case is inconclusive—not a Prismel pass.

## Current campaign status

On 2026-08-05 the generated quick and standard campaigns both passed all 24
product rows with exact one-/four-domain equality. Standard includes the
deliberately self-intersecting seven-torus drill bank under explicit
right-input resolution. Its exact constructions create bit-identical rounded
vertices, zero-area slivers, and ULP-scale non-adjacent contacts; mandatory
repair now coalesces, deletes, or contracts them only under the certificates
described in [boolean.md](boolean.md), with complete ancestry composition and
final rounded-surface verification. Standard four-domain medians for that bank
are 0.377 s Union, 1.112 s Intersection, 1.180 s Difference, 0.342 s reverse
subtraction, 1.260 s XOR, and 2.357 s Shatter. The measured complete campaign peaked at
119,000 KiB RSS. The licensed Houdini and third-party real-model runs are still
unavailable, so the comparative “not worse” gate remains explicitly
inconclusive rather than passed.
