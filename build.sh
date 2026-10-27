#!/bin/sh
# build.sh OMEGA_SRC OUT: builds OUT (synapse-claims, seeded Omega) and OUT's sibling synapse-claims-sig
# (INTERIM Rust helper, see docs/EXTENSION-PROPOSALS.md).
#   OMEGA_SRC  checkout of aien-dev/omega-mv at the sha in omega.pin (its seed/out/omc must match the pin)
#   OUT        output binary path; OUT.unit.om keeps the concatenated unit for inspection
# Env: SYNAPSE_SRC=DIR  aien-dev/synapse checkout at synapse.pin (linked as .synapse for sig/Cargo.toml)
#      CARGO_OFFLINE=1  pass --offline to cargo;  SKIP_SIG=1  build only the Omega binary
set -eu
[ $# -eq 2 ] || { echo "usage: build.sh OMEGA_SRC OUT" >&2; exit 64; }
here=$(cd "$(dirname "$0")" && pwd)
src=$(cd "$1" && pwd)
out=$2
case $out in /*) ;; *) out=$(pwd)/$out ;; esac
mkdir -p "$(dirname "$out")"

want_sha=$(sed -n 's|^aien-dev/omega-mv@\([0-9a-f]\{40\}\)$|\1|p' "$here/omega.pin")
want_omc=$(sed -n 's|^omc-sha256 \([0-9a-f]\{64\}\)$|\1|p' "$here/omega.pin")
[ -n "$want_sha" ] && [ -n "$want_omc" ] || { echo "build.sh: omega.pin malformed" >&2; exit 65; }
have_sha=$(git -C "$src" rev-parse HEAD)
[ "$have_sha" = "$want_sha" ] || { echo "build.sh: $src is at $have_sha, omega.pin wants $want_sha" >&2; exit 65; }
have_omc=$(sha256sum "$src/seed/out/omc" | cut -d' ' -f1)
[ "$have_omc" = "$want_omc" ] || { echo "build.sh: omc sha256 $have_omc != pin $want_omc" >&2; exit 65; }

unit=$out.unit.om
{ printf 'om2\n'; cat "$src/om/tls/sha2.om" "$here"/src/*.om; } > "$unit"
rm -f "$out"
if ! "$src/seed/out/omc" < "$unit" > "$out.tmp" 2> "$out.err"; then
  cat "$out.err" >&2
  rm -f "$out.tmp"
  echo "build.sh: omc rejected $unit" >&2
  # show the rejected unit line with its source file and line, so CI logs are self-contained
  bad=$(sed -n 's/^omc: line \([0-9][0-9]*\):.*/\1/p' "$out.err" | head -n 1)
  if [ -n "$bad" ] && [ "$bad" -gt 1 ]; then
    awk -v want=$((bad - 1)) 'NR==want{print "build.sh: unit line " want+1 " is " FILENAME ":" FNR ": " $0; exit}' \
      "$src/om/tls/sha2.om" "$here"/src/*.om >&2
  fi
  exit 1
fi
rm -f "$out.err"
chmod 755 "$out.tmp"
mv "$out.tmp" "$out"
echo "build.sh: built $out" >&2

[ "${SKIP_SIG:-0}" = 1 ] && exit 0
[ -n "${SYNAPSE_SRC:-}" ] || { echo "build.sh: set SYNAPSE_SRC to an aien-dev/synapse checkout at synapse.pin (or SKIP_SIG=1)" >&2; exit 64; }
want_syn=$(sed -n 's|^aien-dev/synapse@\([0-9a-f]\{40\}\)$|\1|p' "$here/synapse.pin")
have_syn=$(git -C "$SYNAPSE_SRC" rev-parse HEAD)
[ "$have_syn" = "$want_syn" ] || { echo "build.sh: SYNAPSE_SRC at $have_syn, synapse.pin wants $want_syn" >&2; exit 65; }
ln -sfn "$(cd "$SYNAPSE_SRC" && pwd)" "$here/.synapse"
set -- build --release --locked --manifest-path "$here/sig/Cargo.toml"
[ "${CARGO_OFFLINE:-0}" = 1 ] && set -- "$@" --offline
cargo "$@"
cp "$here/sig/target/release/synapse-claims-sig" "$(dirname "$out")/synapse-claims-sig"
echo "build.sh: built $(dirname "$out")/synapse-claims-sig" >&2
