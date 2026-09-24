#!/bin/sh
# Five warmed geometry builds per reference preset; no native window is opened.
set -eu
cd "$(dirname "$0")/.."
uname -sm
sysctl -n machdep.cpu.brand_string
ocamlc -version
dune build sketches/pastel_flow/main.exe
for preset in waves silk; do
  printf '%s\n' "preset=$preset profile=dev geometry_domains=1"
  _build/default/sketches/pastel_flow/main.exe --preset "$preset" --bench
done
