# lib/ogpu rules

OGPU is Prismel's GPU API: modelled on Metal's object model with immediate-mode
encoders, full capability, and backend-agnostic (plan decision 2). Metal
(`ogpu_metal`) is the only backend today; a Vulkan backend must be addable
without changing callers.

- `ogpu` depends on no other library in the repo. Backend types never appear
  in its interface.
- Every non-baseline feature is checked through `Caps` and otherwise returns a
  typed `Unsupported` error. Never a silent no-op, never a lowest common
  denominator cut.
- No `Metal.` or `Ogpu_metal.` above the backends; `test/dependency_gate.ml`
  enforces this. `Ogpu_metal.Interop` (when it exists) is the only escape
  hatch to Metal handles, used inside `lib/ogpu_metal` and its tests.
- Every feature has conformance tests on every backend: exact behavior when
  `Caps.has` it, the typed `Unsupported` otherwise; include lifetime and
  no-handle-leak checks.
- MSL is the canonical shader language. Shader interfaces are checked against
  reflection at pipeline creation.
- Target shape (plan G): dune virtual library with `ogpu_metal`/`ogpu_mock`
  implementations, one backend per executable, conformance suite over the
  mock and Metal.
