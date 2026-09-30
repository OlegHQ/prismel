# Workspace proposal

A plan for evolving Prismel Flow into a *workspace*: authored Lisp is the
document, networks are derived from it, and the editor supports both direct
manipulation and text editing, each rewriting the other.

Read these in order:

1. [plan.md](plan.md): the migration plan of record. Milestones W0–W12, each with the
   parts it reuses, what it builds, what it skips, its files, tests and a
   done-when gate. Start here to implement.
2. [iteration.md](iteration.md): the design, covering loops, zones, the
   iteration selector, scopes, functions, data and macros.
3. [ambiguities.md](ambiguities.md): 48 resolved design questions.
4. [case-studies.md](case-studies.md): 11 3D sketches written in workspace Lisp.
5. [prototype/](prototype/): the behavioral study. Open
   `prototype/index.html` in a browser. Rebuild it with `node build.cjs`
   and check it with `node check.cjs`. It is a reference, never product
   code.
