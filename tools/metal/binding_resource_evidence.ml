type gate = { name : string; applies_to : int }
let manifest_digest = Binding_resource_manifest.digest
let gates =
  [ {name="inventory-id-signature-availability";applies_to=100}
  ; {name="direct-selector-static-compilation";applies_to=92}
  ; {name="safe-range-alignment-overflow-rejection";applies_to=8}
  ; {name="same-device-and-capability-rejection";applies_to=8}
  ; {name="constructor-failure-no-handle-delta";applies_to=8}
  ; {name="parent-child-and-completion-ownership";applies_to=8}
  ; {name="M1-create-use-destroy-exactness";applies_to=100}
  ; {name="M1-10000-iteration-autorelease-stress";applies_to=100}
  ; {name="availability-and-unsupported-path";applies_to=100}
  ; {name="sanitizer-and-frozen-output-drift";applies_to=100} ]
