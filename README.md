Child of [aien-dev/synapse](https://github.com/aien-dev/synapse) at `099a980fedab8a6797bbf0358b8c5502c8045142` (see `synapse.pin`).

# synapse-claims

A signed, append-only claims ledger for AI lanes working on the aien-dev organisation. Before a lane
touches a branch, PR, path, repository or external target (an outreach recipient, a cloud box), it
claims it. A second lane that tries to claim an overlapping target gets exit 2 and the holder's
id, agent, intent and lease expiry. Claims are leases: they expire unless renewed, and
`synapse-claims expire` (run by synapse-pulse) closes them. Every event is hash-chained and
Ed25519-signed, so `verify` can prove the ledger has not been edited.

`synapse-claims` is seeded Omega (`src/*.om` plus `om/tls/sha2.om` from omega-mv), compiled by the
pinned `omc` (`omega.pin`). Signing is the one exception:

> **INTERIM:** `sig/` builds `synapse-claims-sig`, a Rust helper (ed25519-dalek, synapse-core) for
> key generation, signing and signature checks, because omega-mv at the pin has no Ed25519.
> See `docs/EXTENSION-PROPOSALS.md` for the missing capability and the replacement plan.

## Build and test

```sh
SYNAPSE_SRC=/path/to/synapse sh build.sh /path/to/omega-mv out/synapse-claims   # also builds out/synapse-claims-sig
OMEGA_SRC=/path/to/omega-mv SYNAPSE_SRC=/path/to/synapse sh tests/run.sh
```

`build.sh` refuses a source tree whose HEAD differs from `omega.pin` / `synapse.pin`, or an `omc`
whose sha256 differs from the pin. CI (`.github/workflows/ci.yml`, ubuntu-24.04-arm) runs the same
`tests/run.sh`.

## Commands

Global options: `--home DIR` (else `$AIEN_COORD_HOME`, else `$HOME/.local/state/aien-coord`),
`--now YYYY-MM-DDTHH:MM:SSZ` (tests only), `--sig-bin PATH` (default: `synapse-claims-sig` next to
the running binary). Output on stdout is JSONL; human text goes to stderr.

| command | does | exit |
|---|---|---|
| `init` | creates the home and the signing key (once); prints `{"ok":true,"pub":"did:key:…"}` | 0 |
| `claim --agent A --session S --target T [--ttl N] [--mode excl\|shared] [--state ST] [--intent TEXT] [--evidence URL]... [--import ORIGIN]` | appends a claim | 0, 2 conflict |
| `renew --agent A --id ID [--ttl N]` | extends an active lease | 0, 4 |
| `release --agent A --id ID [--state ST] [--evidence URL]...` | closes the claim | 0, 4 |
| `state --agent A --id ID --state ST [--evidence URL]...` | records progress | 0, 4 |
| `who TARGET` | active claims overlapping TARGET | 0 |
| `list [--all] [--agent-prefix P]` | active (or all) claims; P matches agent `P` and `P.*` | 0 |
| `conflicts` | conflicting active pairs `{"a":…,"b":…,"reason":…}` | 0, 1 if any |
| `verify` | checks seq, prev, hash, claim id, signatures | 0, 3 |
| `expire [--agent pulse]` | appends `expire` for every lease past its expiry, prints those lines | 0 |

Exit codes: 0 ok, 1 conflicts found, 2 claim conflict, 3 ledger verification failure, 4 unknown id /
not holder / not active, 64 usage, 70 I/O or signer failure.

## Ledger

`$HOME/claims.jsonl`, one event per line in fixed key order (see the parent's coordination
contract):
`{"v":1,"seq":N,"ts":…,"op":…,"id":…,"agent":…,"session":…,"kind":…,"target":…,"mode":…,"ttl_s":N,"expires":…,"state":…,"intent":…,"evidence":[…],"origin":…,"prev":…,"hash":…,"sig":…}`

- `hash = sha256("AIEN_CLAIMS_EVENT_V1\n" ++ body)`, body = the line up to `,"hash":` plus `}`.
- `sig = Ed25519("AIEN_CLAIMS_EVENT_V1\0" ++ raw32(hash))` with `keys/ledger.key`.
- Claim id: the first 16 hex of the hash of the claim event's body written with
  `"id":"0000000000000000"`; the stored hash covers the real body. `verify` checks both.
- Conflict: targets overlap, agents differ, both claims `excl`, both active (`shared` never
  conflicts). `--import` records a claim even when it conflicts, so `conflicts` surfaces migrated
  collisions.
- Appends take `flock(LOCK_EX)` on `claims.lock`, re-read the ledger, re-check conflicts, sign, write
  each line with one `write()`, then `fdatasync`. Readers take `LOCK_SH`.
- Limits: 131072 claims, 999999 ledger lines, 65535-byte lines, 4096-byte intents.

## Connected repos

- [aien-dev/synapse](https://github.com/aien-dev/synapse) (parent)
- [aien-dev/synapse-map](https://github.com/aien-dev/synapse-map): repo map and task routing
- [aien-dev/synapse-pulse](https://github.com/aien-dev/synapse-pulse): runs `expire`, checks claims against GitHub
- [aien-dev/synapse-mcp](https://github.com/aien-dev/synapse-mcp): MCP server exposing claims to agents
- [aien-dev/synapse-board](https://github.com/aien-dev/synapse-board): BOARD.md migration (`claim --import`)

## License

Apache-2.0 WITH LLVM-exception (`LICENSE`).
