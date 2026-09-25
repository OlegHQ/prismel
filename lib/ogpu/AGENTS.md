# lib/ogpu rules

OGPU is Prismel's GPU API: modelled on Metal's object model with immediate-mode
encoders, full capability, and backend-agnostic (plan decision 2). Metal
(`ogpu_metal`) is the only backend today; a Vulkan backend must be addable
without changing callers.

- `ogpu_core` depends on no other library in the repo. Virtual `ogpu` aliases
  the core and depends only on it. Backend types never appear in its interface.
- Every non-baseline feature is checked through `Caps` and otherwise returns a
  typed `Unsupported` error. Never a silent no-op, never a lowest common
  denominator cut.
- `test/dependency_gate.ml` enforces the native dependency direction and
  lists the runtime and test exceptions until G4 removes them.
- Every feature has conformance tests on every backend: exact behavior when
  `Caps.has` it, the typed `Unsupported` otherwise; include lifetime and
  no-handle-leak checks.
- MSL is the canonical shader language. Shader interfaces are checked against
  reflection at pipeline creation.
- Target shape (plan G): dune virtual library with `ogpu_metal`/`ogpu_mock`
  implementations, one backend per executable, conformance suite over the
  mock and Metal.
