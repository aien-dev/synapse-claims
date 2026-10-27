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

BIN=$TEST_ROOT/bin/synapse-claims
OUT=$TEST_ROOT/out
ERR=$TEST_ROOT/err
pass=0
fail=0
T0=2026-10-27T00:00:00Z

ok() { pass=$((pass + 1)); echo "PASS $1"; }
bad() {
  fail=$((fail + 1)); echo "FAIL $1: $2"
  sed 's/^/  stdout: /' "$OUT"; sed 's/^/  stderr: /' "$ERR"
}

# t NAME WANT_RC -- command...: run, check the exit code
t() {
  name=$1; want=$2; shift 3
  "$@" > "$OUT" 2> "$ERR"
  rc=$?
  if [ "$rc" = "$want" ]; then ok "$name (rc=$rc)"; else bad "$name" "rc=$rc want $want"; fi
}
# has NAME FIXED-STRING [FILE]: the last output contains the string
has() {
  if grep -qF -- "$2" "${3:-$OUT}"; then ok "$1"; else bad "$1" "missing $2"; fi
}
hasnt() {
  if grep -qF -- "$2" "${3:-$OUT}"; then bad "$1" "unexpected $2"; else ok "$1"; fi
}
lines() {
  n=$(wc -l < "$OUT" | tr -d ' ')
  if [ "$n" = "$2" ]; then ok "$1"; else bad "$1" "$n lines, want $2"; fi
}
idof() { sed -n 's/.*"id":"\([0-9a-f]\{16\}\)".*/\1/p' "$OUT" | head -n 1; }

H=$TEST_ROOT/h1
C="$BIN --home $H --now $T0"

# --- usage and pre-init behaviour ---
t usage-none 64 -- "$BIN"
t usage-unknown-option 64 -- $C list --bogus
t usage-unknown-command 64 -- $C frobnicate
t usage-missing-value 64 -- $C claim --agent
t who-before-init 0 -- $C who repo:aien-dev/omega-mv
lines who-before-init-empty 0
t verify-before-init 0 -- $C verify
has verify-empty-head '{"ok":true,"events":0,"head":"0000000000000000000000000000000000000000000000000000000000000000"}'
t claim-before-init 70 -- $C claim --agent A --session s1 --target repo:aien-dev/omega-mv
has claim-before-init-msg 'run init' "$ERR"

# --- init ---
t init 0 -- $C init
has init-pub '{"ok":true,"pub":"did:key:z'
cp "$OUT" "$TEST_ROOT/pub1"
t init-again 0 -- $C init
if cmp -s "$OUT" "$TEST_ROOT/pub1"; then ok init-idempotent; else bad init-idempotent "pub changed"; fi
mode=$(stat -c %a "$H/keys/ledger.key")
if [ "$mode" = 600 ]; then ok key-mode-600; else bad key-mode-600 "mode $mode"; fi
seed=$(cat "$H/keys/ledger.key")
if grep -rqF -- "$seed" "$TEST_ROOT/pub1" "$OUT" "$ERR"; then bad seed-not-printed "seed leaked"; else ok seed-not-printed; fi

# --- claim / conflict ---
t claim-a 0 -- $C claim --agent A --session s1 --target branch:aien-dev/omega-mv#feat-x --intent 'tls work "x"
line2'
has claim-a-out '"seq":1,"expires":"2026-10-27T01:00:00Z"}'
IDA=$(idof)
t claim-b-conflict 2 -- $C claim --agent B --session s2 --target branch:aien-dev/omega-mv#feat-x
has conflict-json "{\"ok\":false,\"error\":\"conflict\",\"holder\":{\"id\":\"$IDA\",\"agent\":\"A\""
has conflict-stderr "synapse-claims: conflict: branch:aien-dev/omega-mv#feat-x held by A ($IDA) until 2026-10-27T01:00:00Z: tls work" "$ERR"
t claim-b-casefold-target 2 -- $C claim --agent B --session s2 --target branch:Aien-Dev/Omega-MV#feat-x
t claim-a-self-no-conflict 0 -- $C claim --agent A --session s1b --target branch:aien-dev/omega-mv#feat-x
t claim-b-shared 0 -- $C claim --agent B --session s2 --target branch:aien-dev/omega-mv#feat-x --mode shared
t claim-b-repo-default-shared 0 -- $C claim --agent B --session s2 --target repo:aien-dev/omega-mv
t claim-c-repo-excl-covers 2 -- $C claim --agent C --session s3 --target repo:aien-dev/omega-mv --mode excl
t claim-a-path 0 -- $C claim --agent A --session s1 --target 'path:aien-dev/synapse:src/**'
t claim-b-path-overlap 2 -- $C claim --agent B --session s2 --target 'path:aien-dev/synapse:src/core/*.om'
t claim-b-path-disjoint 0 -- $C claim --agent B --session s2 --target 'path:aien-dev/synapse:docs/*'
t claim-a-ext 0 -- $C claim --agent A --session s1 --target ext:mailto:Bob@Example.org
t claim-b-ext-casefold 2 -- $C claim --agent B --session s2 --target ext:mailto:bob@example.org
t claim-b-other-repo 0 -- $C claim --agent B --session s2 --target branch:aien-dev/aienux#feat-x
t claim-branch-slash 0 -- $C claim --agent B --session s2 --target branch:aien-dev/omega-mv#feat/y

# --- invalid input ---
t bad-target 64 -- $C claim --agent A --session s --target repo:noslash
t bad-target-kind 64 -- $C claim --agent A --session s --target ext:x
t bad-ttl-zero 64 -- $C claim --agent A --session s --target repo:aien-dev/q --ttl 0
t bad-ttl-text 64 -- $C claim --agent A --session s --target repo:aien-dev/q --ttl 1h
t bad-mode 64 -- $C claim --agent A --session s --target repo:aien-dev/q --mode mine
t bad-state 64 -- $C claim --agent A --session s --target repo:aien-dev/q --state DONE
t bad-agent-quote 64 -- $C claim --agent 'A"' --session s --target repo:aien-dev/q
t bad-intent-utf8 64 -- $C claim --agent A --session s --target repo:aien-dev/q --intent "$(printf 'bad \377 byte')"
t missing-session 64 -- $C claim --agent A --target repo:aien-dev/q

# --- holder operations ---
t renew-unknown 4 -- $C renew --agent A --id 0123456789abcdef
has renew-unknown-msg 'not found' "$ERR"
t renew-not-holder 4 -- $C renew --agent B --id "$IDA"
has renew-not-holder-msg 'not holder' "$ERR"
t renew-ok 0 -- $BIN --home "$H" --now 2026-10-27T00:30:00Z renew --agent A --id "$IDA" --ttl 7200
has renew-expires "\"id\":\"$IDA\""
has renew-expires2 '"expires":"2026-10-27T02:30:00Z"'
t state-missing-state 64 -- $C state --agent A --id "$IDA"
t state-ok 0 -- $C state --agent A --id "$IDA" --state IMPLEMENTED --evidence https://github.com/aien-dev/omega-mv/pull/1
t list 0 -- $C list
has list-state "\"id\":\"$IDA\",\"agent\":\"A\",\"session\":\"s1\",\"kind\":\"branch\",\"target\":\"branch:aien-dev/omega-mv#feat-x\",\"mode\":\"excl\",\"state\":\"IMPLEMENTED\""
has list-intent-escaped 'tls work \"x\"\nline2'
has list-evidence '"evidence":["https://github.com/aien-dev/omega-mv/pull/1"]'
t who 0 -- $C who branch:aien-dev/omega-mv#feat-x
has who-holder "\"id\":\"$IDA\""
hasnt who-no-other-repo 'aien-dev/aienux'

# --- agent prefix ---
t claim-lane 0 -- $C claim --agent Lane --session l --target repo:aien-dev/l1
t claim-lane-sub 0 -- $C claim --agent Lane.Sub --session l --target repo:aien-dev/l2
t claim-lanex 0 -- $C claim --agent LaneX --session l --target repo:aien-dev/l3
t list-prefix 0 -- $C list --agent-prefix Lane
lines list-prefix-count 2
hasnt list-prefix-excludes 'LaneX'

# --- import and conflicts ---
t conflicts-none 0 -- $C conflicts
t import-conflict 0 -- $C claim --agent D --session d --target branch:aien-dev/omega-mv#feat-x --import board
t conflicts 1 -- $C conflicts
has conflicts-reason '"reason":"same_target"}'
has conflicts-origin '"origin":"import:board"'

# --- release ---
t release-ok 0 -- $C release --agent A --id "$IDA" --state MERGED
t release-again 4 -- $C release --agent A --id "$IDA"
has release-again-msg 'not active' "$ERR"
t list-all 0 -- $C list --all
has list-all-released "\"id\":\"$IDA\""
t verify-h1 0 -- $C verify
has verify-ok '{"ok":true,"events":'

# --- expire ---
H3=$TEST_ROOT/h3
C3="$BIN --home $H3"
t h3-init 0 -- $C3 --now $T0 init
t h3-claim-short 0 -- $C3 --now $T0 claim --agent A --session s --target repo:aien-dev/e1 --ttl 60
IDE=$(idof)
t h3-claim-long 0 -- $C3 --now $T0 claim --agent A --session s --target repo:aien-dev/e2 --ttl 86400
t expire 0 -- $C3 --now 2026-10-27T00:02:00Z expire --agent pulse
lines expire-one 1
has expire-line "\"op\":\"expire\",\"id\":\"$IDE\""
has expire-origin '"origin":"pulse"'
t expire-again 0 -- $C3 --now 2026-10-27T00:02:00Z expire --agent pulse
lines expire-again-none 0
t renew-expired 4 -- $C3 --now 2026-10-27T00:03:00Z renew --agent A --id "$IDE"
t h3-list 0 -- $C3 --now 2026-10-27T00:03:00Z list
lines h3-list-active 1
t h3-verify 0 -- $C3 verify
has h3-verify-events '"events":3,'

# --- tamper detection ---
cp -r "$H3" "$TEST_ROOT/h4"
sed -i '2s/"intent":"/"intent":"X/' "$TEST_ROOT/h4/claims.jsonl"
t tamper-hash 3 -- "$BIN" --home "$TEST_ROOT/h4" verify
has tamper-hash-out '{"ok":false,"seq":2,"error":"hash"}'
cp -r "$H3" "$TEST_ROOT/h5"
garb=$(printf 'ab%.0s' $(seq 1 64))
sed -i "3s/\"sig\":\"[0-9a-f]*\"/\"sig\":\"$garb\"/" "$TEST_ROOT/h5/claims.jsonl"
t tamper-sig 3 -- "$BIN" --home "$TEST_ROOT/h5" verify
has tamper-sig-out '{"ok":false,"seq":3,"error":"signature"}'
cp -r "$H3" "$TEST_ROOT/h6"
sed -i '2d' "$TEST_ROOT/h6/claims.jsonl"
t tamper-seq 3 -- "$BIN" --home "$TEST_ROOT/h6" verify
has tamper-seq-out '{"ok":false,"seq":2,"error":"seq"}'
cp -r "$H3" "$TEST_ROOT/h7"
echo '{"v":1,"junk":true}' >> "$TEST_ROOT/h7/claims.jsonl"
t tamper-malformed 3 -- "$BIN" --home "$TEST_ROOT/h7" verify
has tamper-malformed-out '{"ok":false,"seq":4,"error":"malformed"}'
t tamper-blocks-append 3 -- "$BIN" --home "$TEST_ROOT/h7" --now $T0 claim --agent Z --session z --target repo:aien-dev/z

# --- signer missing ---
t sig-bin-missing 70 -- $C claim --agent A --session s --target repo:aien-dev/sigless --sig-bin "$TEST_ROOT/nope"

echo "passed=$pass failed=$fail"
[ "$fail" = 0 ]
