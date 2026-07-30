# Deterministic generative tools

## Purpose

Randomness and coherent noise are basic sketch materials. Prismel keeps them
deterministic and explicit so a promising result can be reproduced, tested,
exported again, and safely calculated across OCaml domains.

## Immutable random generators

`Rand.t` is an immutable generator value:

```ocaml
let radius, random = Rand.int_range ~min:10 ~max:80 random
let hue, random = Rand.range ~min:0. ~max:360. random
let color = Color.hsv hue 0.8 0.95
```

Every sample returns the next generator. Store that value in the sketch model.
Use `Rand.split` before sending independent calculations to `Parallel`; never
share and mutate `Stdlib.Random.State.t`.

The supported sampling vocabulary includes unit floats, ranges, bounded
integers, booleans, probabilities, selection, weighted selection, shuffling,
and generator splitting. Empty selection is represented by `None`, with an
explicit `_exn` convenience when emptiness is a programmer error.

## Coherent noise

`Noise.create seed` builds an immutable permutation table that can be shared
between domains. `sample1`, `sample2`, and `sample3` return coherent gradient
noise normalized to approximately 0..1.

`fbm1`, `fbm2`, and `fbm3` layer octaves for organic detail:

```ocaml
let terrain =
  Noise.fbm3 ~octaves:5 noise ~x:(x *. 0.02) ~y:(y *. 0.02) ~z:time
```

Lacunarity controls frequency growth and gain controls amplitude decay.
Inputs are unbounded, including negative coordinates.

## Color

Color constructors support:

- byte RGB/RGBA and normalized floating channels;
- CSS-like short and long hexadecimal strings;
- HSV and HSL with wrapping degree hue and normalized other components;
- alpha, mixing, lightening, darkening, saturation, and hue rotation;
- evenly spaced palette gradients.

Colors remain immutable 8-bit sRGB values at the renderer boundary. Palette
interpolation currently blends encoded sRGB channels; a future perceptual color
module may add linear-light or OKLCH interpolation explicitly rather than
silently changing existing results.

## Determinism contract

For the same Prismel version, seed, inputs, and parameters:

- `Rand` produces the same sample sequence;
- `Noise` produces the same field;
- parallel scheduling does not change ordered results;
- a headless sketch and a visible sketch calculate the same scene data.

Render backend differences may still affect pixel-level antialiasing. Exact
framebuffer comparisons should be scoped to one SDL/backend version.
