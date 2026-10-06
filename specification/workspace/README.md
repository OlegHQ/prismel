# Workspace

Status: **implemented**. Authored Lisp is the document, networks are derived from it, and
the editor supports both direct manipulation and text editing, each rewriting the other.
The study in `prototype/` stays a behavioural reference.

Read these in order:

1. [iteration.md](iteration.md): the language and its drawing. Loops, zones, the
   iteration selector, scopes, functions, data and macros; §2 and §7 are normative for the
   language, §6 names the modules that implement each part.
2. [ambiguities.md](ambiguities.md): the rule register, every design question a reader could
   answer two ways and the rule chosen, including the time rules (T1–T4).
3. [materials.md](materials.md): the `material` context.
4. [case-studies.md](case-studies.md): 12 3D sketches as `.rays` files, including the
   time-driven Orrery. `sketches/ws_*` are the checked-in workspace sketches.
5. [prototype/](prototype/): the behavioral study. Open
   `prototype/index.html` in a browser. Rebuild it with `node build.cjs`
   and check it with `node check.cjs`. It is a reference, never product
   code.

[`../flow.md`](../flow.md) has the document model, the reader and printer, the graph pane,
its keys, carry, the layout forms and lowering.
