# Workspace

Status: **implemented** (W0-W12, PR #1; the record of what landed, the deviations and the
remaining gaps is [progress.md](progress.md) and `specification/flow-migration.md` "Workspace").
The study in `prototype/` stays a behavioural reference. What follows was the proposal:
the evolution of Rays Flow into a *workspace*: authored Lisp is the
document, networks are derived from it, and the editor supports both direct
manipulation and text editing, each rewriting the other.

Read these in order:

1. [plan.md](plan.md): the migration plan of record. Milestones W0–W12 (with W2b for live `t` and W11 for `.rays` sketches), each with the
   parts it reuses, what it builds, what it skips, its files, tests and a
   done-when gate. Start here to implement.
2. [iteration.md](iteration.md): the design, covering loops, zones, the
   iteration selector, scopes, functions, data and macros.
3. [ambiguities.md](ambiguities.md): 52 resolved design questions, including the time rules (T1–T4).
4. [case-studies.md](case-studies.md): 12 3D sketches as `.rays` files, including the time-driven Orrery.
5. [prototype/](prototype/): the behavioral study. Open
   `prototype/index.html` in a browser. Rebuild it with `node build.cjs`
   and check it with `node check.cjs`. It is a reference, never product
   code.
