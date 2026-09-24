#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
dune build sketches/code_quadtree/main.exe
sketch=_build/default/sketches/code_quadtree/main.exe
"$sketch" --index-only
if [ "${2:-tour}" = renderer ]; then
  PRISMEL_SCENE2_DENSE_RUNS=0 /usr/bin/time -l "$sketch" --smoke --bench --frames "${1:-120}"
  /usr/bin/time -l "$sketch" --smoke --bench --frames "${1:-120}"
elif [ "${2:-tour}" = hover ]; then
  /usr/bin/time -l "$sketch" --hover-bench --zoom 1.45 --bench --frames "${1:-120}" --rebuild-art
  /usr/bin/time -l "$sketch" --hover-bench --zoom 1.45 --bench --frames "${1:-120}"
else
  /usr/bin/time -l "$sketch" --smoke --bench --frames "${1:-120}" --reference-draws
  /usr/bin/time -l "$sketch" --smoke --bench --frames "${1:-120}"
fi
