# Vec2 and Mat3

`Vec2` and `Mat3` are immutable, renderer-independent mathematical values.
They contain no native resource and are safe to share across OCaml domains.

## Vec2

```ocaml
type t = { x : float; y : float }
```

The module provides construction, zero/unit vectors, addition, subtraction,
negation, scalar multiplication, dot product, squared length, length,
normalization, distance, angle, rotation, interpolation, and epsilon-aware
comparison.

`normalize Vec2.zero` follows the module's defined safe result; callers that
need to distinguish a degenerate direction should check `length_sq` first.
Pair conversions are explicit: integer conversion is for logical drawing
coordinates, while `to_pair_float` preserves the mathematical value.

## Mat3

`Mat3.t` stores a full immutable 3×3 matrix. Constructors cover identity,
translation, non-uniform scale, rotation in radians, shear, and a combined
affine transform. `mul a b` defines composition according to the tested public
convention; code should not infer order from storage layout.

`transform_point` applies translation and homogeneous division as appropriate.
`transform_vector` applies only the linear portion. `transform_vec2` is the
typed point convenience. Determinant and inverse operations use the module's
documented result/exception behavior for singular input.

## Scene use

`Scene.translate`, `rotate`, `scale`, and grouped transforms remain pure scene
constructors. Native lowering composes their mathematical values before OGPU
command recording. Metal receives the final checked transform data; Mat3 does
not expose or depend on renderer state.

## Regression requirements

- vector identities, zero/near-zero behavior, rotation, and interpolation;
- matrix identity and constructor fixtures;
- explicit multiplication/composition order;
- point versus direction translation behavior;
- inverse round trips and singular rejection;
- nested scene-transform order through a native framebuffer fixture;
- exact one-domain/multi-domain results for pure bulk transforms.
