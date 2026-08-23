# MTL4 residual qualification (190 IDs)

The exact sorted-ID SHA-256 is `3c2848f1c1dc8b31de399cb502a444f30a672b1da00c07246989f0561dd0c2a4`.
It selects every current unreviewed `Metal/MTL4*.h` declaration except
`MTL4AccelerationStructure.h`, which belongs to the acceleration family.

The semantic partition is 38 mechanical method/property IDs (31 callable
typed direct Objective-C methods), 130 ownership/validation IDs, and 22
metadata IDs. Handles, callbacks, arrays, descriptors, pipeline construction,
and resource references stay handwritten. The safe model proves command-buffer
parent retention, recording/commit/completion transitions, encoder end-state
invalidation, same-device rejection, and completion-time release.

Exact intersections are zero with resource100, corrected presentation125,
shader157, corrected compute76, and pipeline113. Header/owner exclusions make
the intersections with acceleration115, mesh/tile105, render encoder106,
layout102, device94, and classic render-resource batches zero. This package is
isolated qualification evidence and does not promote inventory.

The generated native shard SHA-256 is
`d05eb7a9d21d43a8296c05f5529ecb73e99f1240d613723e4bcf8ee3d2fc6150`.
