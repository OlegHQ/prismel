# Compiled Lisp, editor projections, and sound boundaries

## How should functions and macros remain reusable and understandable?

### Takeaway
Use lexically scoped functions as the ordinary reuse mechanism and hygienic macros for syntax abstraction. Preserve authored forms and expansion origins so graph users can inspect a macro without having to edit generated code.

### Cited Findings
- Racket pattern macros preserve lexical scope: introduced names do not capture names supplied at the call site, and local names do not capture references introduced by the macro. This addresses both directions of accidental capture. [Racket pattern macros](https://docs.racket-lang.org/guide/pattern-macros.html)
- Racket syntax objects contain source locations and lexical binding information in addition to ordinary list/symbol data; identifier equality can compare bindings rather than printed spelling. [Racket syntax objects](https://docs.racket-lang.org/guide/stx-obj.html)

### Inferences
- Proposed small core: literals, references, `let`, `if`, typed functions, calls, records, bounded collections, and registered constructors. SOP, scene, settings, and editor declarations share this core, but return distinct types. Avoid four independent expression interpreters.
- A function returning a number can be used for a SOP radius, an object's transform, or a panel width when the units match. A function returning `Panel` cannot feed a `Geometry` input. Cross-context reuse means compatible types and explicit context arguments, not permitting every operation everywhere.
- Separate three operations visibly: a group changes presentation only; a local compound introduces a scoped subgraph; extraction creates a reusable function definition and replaces the selection with a call. Extraction must expose every free dependency as an argument, maintain outgoing connections, and preview the resulting signature before commit.
- A call is shown as one node or one list row, with typed inputs and output. Enter opens its definition with a breadcrumb; returning preserves the caller's selection. Editing a definition affects all uses; editing an argument affects that call only. Show a use count and offer “Make independent copy.”
- A macro call has a distinct badge and a read-only expansion view. Diagnostics should name both the authored call and relevant expanded form. Start with declarative pattern/template macros; arbitrary OCaml callbacks must remain trusted extensions, not document code.
- Binding identity and editor identity are separate concepts: lexical binding IDs establish reference meaning; persistent form IDs maintain selection, layout, diagnostics, and undo. Printed labels serve neither role.

### Gaps
- Neither Racket source proves a graph/text projection can invert arbitrary macro expansion. Proposed solution is to retain authored syntax and treat expansion as a derived view; never claim expansion is invertible.
- Recursion, higher-order functions, polymorphism, and first-class syntax should be explicit scope decisions. They are useful possibilities, but not prerequisites for the user's proposed composition workflows.

## How can graph, list, and text represent one editable program?

### Takeaway
Use a canonical authored document with stable identity and derive all views from it. Model unfinished edits explicitly; allow draft text to be invalid without destroying the last applied program.

### Cited Findings
- Hazel defines incomplete programs using typed holes, including holes around erroneous or conflicted terms; it can typecheck and run incomplete programs with incomplete results. Its project describes research on keyboard structure editing and live GUI literals. [Hazel project](https://hazel.org/)
- Racket's syntax objects demonstrate keeping origin and binding metadata with syntax rather than trying to reconstruct that information from text later. [Racket syntax objects](https://docs.racket-lang.org/guide/stx-obj.html)

### Inferences
- Store authored syntax, stable form IDs, binding IDs, comments, and view metadata. Typed IR, compiled plan, graph geometry, and list rows are derived. Preserve explicit `let` sharing: turning a shared graph value into duplicated expressions can change cost and identity even when values match.
- Define roundtrip guarantees precisely: parse/print preserves semantic structure; changing graph/list/text preserves IDs for unchanged forms; comments survive local edits; layout persists independently. Byte-identical text is not the appropriate default promise after structural edits.
- Text changes first update a draft. Apply parses, resolves names, expands macros, checks types/context/effects, validates topology, compiles, and atomically swaps the whole document generation. A failed apply leaves the draft visible and keeps the previous applied generation with a clear “Preview uses last applied version” label.
- A structural hole is a first-class draft form with an expected type, such as “Geometry required.” Display the same obligation as a missing port, list field, or text marker. Do not silently convert malformed free text to a structurally valid program that changes its meaning.
- Durable IDs should be serialized as document metadata rather than inferred only from source offsets. Text reconciliation can preserve IDs for unambiguous unchanged forms; ambiguous rewrites get new IDs. Copy creates new IDs; move and rename retain IDs. Import validates uniqueness and references.
- Every gesture should emit one transaction through existing history: a slider drag, rewiring, extracting a function, applying a text buffer, or changing panel layout. Tag asynchronous results with the source revision; discard stale results rather than applying them to newer text.
- Proposed diagnostic UX: clicking one error reveals the same form in whichever view is active, with its expected type, actual type, and a concrete repair. Context switches should retain the corresponding selection.

### Gaps
- Hazel's typed-hole results do not establish that all Prismel resource operations can safely execute around holes. A conservative first implementation may apply only complete validated documents while still supporting holes during editing.
- Stable identity reconciliation, comment preservation, and transactional layout replacement require specific regression tests. These are design proposals, not guarantees supplied by the cited systems.

## What must compilation and runtime enforce?

### Takeaway
Share the language frontend between an OCaml PPX and the interactive editor, then produce typed execution plans through separate deployment paths. Keep pure descriptions separate from resource ownership and mutation.

### Cited Findings
- OCaml PPXs rewrite the parsed syntax tree during compilation. Extension nodes must be replaced before normal compilation continues; generated OCaml values can then benefit from OCaml type checking. The documentation also notes arbitrary preprocessors are standalone programs and can perform arbitrary actions. [OCaml metaprogramming](https://ocaml.org/docs/metaprogramming)
- Slint properties have declared types and input/output visibility; a property's binding associates an expression with that typed property. [Slint properties](https://docs.slint.dev/latest/docs/slint/reference/language/properties/)
- Slint bindings track dependencies and are evaluated lazily. Its compiler rejects mutation and impure calls in pure binding contexts. Imperative assignment normally removes an existing binding, which illustrates why the interaction between direct editing and expression drives must be deliberate. [Slint evaluation and purity](https://docs.slint.dev/latest/docs/slint/reference/language/evaluation-and-purity/)

### Inferences
- Compilation pipeline proposal: source plus metadata → lossless syntax → hygienic expansion → name resolution → type/context/effect checks → typed IR → executable plan. PPX emits OCaml constructors/code from this frontend; live editing compiles the same IR to a bounded evaluator or plan using registered operations. “Compiled” must name this distinction; a PPX alone does not hot-compile edited documents.
- Define result types for `Geometry`, `Scene`, `Settings`, `Panel`, and `Workspace`. Editor constructors create descriptions interpreted by the existing PXUI host; they do not allocate an independent UI engine. Window and GPU ownership remains at the host boundary.
- Pure functions take explicit values. Time, document data, selection, viewport dimensions, and resources enter through typed context capabilities or explicit parameters. A saved static setting cannot depend on current selection or time unless its schema explicitly allows that dynamic value. Function signatures expose requirements, so a caller cannot hide an unavailable capability.
- Use a small effect distinction first: pure description/value computation versus typed commands executed at the host boundary. Event handlers return intents; the reducer validates and commits them outside UI construction. Arbitrary I/O, mutation, and resource acquisition are unavailable inside pure parameter expressions and macros.
- Each parameter has an explicit mode: literal, expression, or connection. Dragging a driven field should offer to edit its upstream value or replace the drive, rather than silently breaking it. A connected field displays its source and supports “Go to source.”
- Validate unknown operators and keywords, duplicates, arity, units, reference scope, return types, topology cycles, duplicate durable IDs, forbidden capabilities, and macro recursion during compilation. Check numeric finiteness, allocation sizes, asset availability, backend capability, and resource failure at runtime using typed errors.
- Bound macro expansion depth and output forms; bound evaluation steps, recursion depth, collection sizes, and geometry allocation. Cancellation and revision tagging prevent stale expensive work replacing new work. Caps must be configurable and reported in errors; numeric defaults require profiling, not guessing.
- Apply editor definitions transactionally: validate new layout, resolve required panels, prepare resources, then swap at a frame boundary. Failure retains the working editor. Always provide a host-owned recovery command that opens the workspace source or restores the previous layout, because user-authored layout must not remove the sole means to repair itself.
- Implementation acceptance checks: capture-avoidance macro example; invalid cross-context call; same shared function used in at least two result contexts; invalid text retaining current preview; stale compile result ignored; graph/list/text edit retaining form identity; function extraction preserving references; expansion/evaluation limit diagnostic; failing workspace apply retaining working controls.

### Gaps
- These sources provide patterns, not a proof of Prismel language soundness. Soundness requires defined syntax, static judgments, evaluation behavior, and a testable semantics for each registered primitive.
- No source establishes suitable limits or performance for Prismel. Compile latency, graph scale, memory, and resource cancellation must be measured in its implementation.
- Native code generation for every live edit versus compilation to a checked plan remains a product/engineering decision. The proposal should recommend the shared frontend and bounded plan first while keeping ahead-of-time OCaml compilation available.
