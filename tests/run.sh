#!/bin/sh
# tests/run.sh: build synapse-claims + synapse-claims-sig, then run positive and negative cases in
# throwaway homes. Env: OMEGA_SRC (default /tmp/Coord/omega-mv), SYNAPSE_SRC (default /tmp/Coord/synapse),
# TEST_ROOT (default /tmp/Coord/test-homes/claims-run). Exit 0 only if every case passes.
set -u
here=$(cd "$(dirname "$0")/.." && pwd)
OMEGA_SRC=${OMEGA_SRC:-/tmp/Coord/omega-mv}
SYNAPSE_SRC=${SYNAPSE_SRC:-/tmp/Coord/synapse}
TEST_ROOT=${TEST_ROOT:-/tmp/Coord/test-homes/claims-run}
export SYNAPSE_SRC
rm -rf "$TEST_ROOT"
mkdir -p "$TEST_ROOT/bin"
if ! sh "$here/build.sh" "$OMEGA_SRC" "$TEST_ROOT/bin/synapse-claims"; then
  echo "FAIL build"
  exit 1
fi
echo "PASS build"
exit 0
