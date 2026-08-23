# Resource100 conformance hookup

Add `test_resource100_conformance_native.mm` to the existing native Metal test
rule with ARC, blocks, Foundation and Metal frameworks. Exit 77 means no Metal
device and should be treated as a capability skip.

Add `test_metal_resource100_safe` as a `lib/metal` test linked with `metal` and
run it on the initial domain. The safe fixture covers invalid counts,
use-after-destroy, nullable sample buffers, mutation snapshots, capability-gated
view-pool creation, and 10,000 descriptor create/destroy cycles. The native
fixture covers real M1 descriptor round trips, registry-ID identity, nullable
remote views, exact remote/view/root metadata, resource-state completion, view
pool error/nullability, and 10,000 autorelease-bounded lifecycles.
