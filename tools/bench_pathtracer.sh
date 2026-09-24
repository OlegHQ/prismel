#!/bin/sh
# Finite path-tracer throughput probe: prints resolution, frames, accumulated
# spp, and mean wall ms/frame (GPU dispatch + readback + presentation).
# Usage: tools/bench_pathtracer.sh [frames] [scale] [spp]
set -eu
cd "$(dirname "$0")/.."
PRISMEL_PATHTRACER_FRAMES="${1:-240}" PRISMEL_PATHTRACER_SCALE="${2:-1}" \
PRISMEL_PATHTRACER_SPP="${3:-1}" dune exec examples/pathtracer/main.exe
