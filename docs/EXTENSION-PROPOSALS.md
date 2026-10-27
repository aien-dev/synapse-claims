# Extension proposals

## E1: Ed25519 keygen, sign and verify in seeded Omega

**Interim code:** `sig/` (Rust crate `synapse-claims-sig`, INTERIM). It exists only because the
pinned omega-mv (`omega.pin`, e5b32567) has SHA-256 (`om/tls/sha2.om`) but no Ed25519.

**What it does for us:** `keygen DIR` writes `ledger.key` (hex seed, 0600) and `ledger.pub`
(`did:key:z…` via `synapse_core::encode_did_key_ed25519`); `sign KEYFILE` signs
`"AIEN_CLAIMS_EVENT_V1\0" ++ hash` for each hash line on stdin; `verify PUBFILE` checks
`hash sig` lines and prints `ok N` or `bad <line>`.

**Pinned host dependencies:** ed25519-dalek 2.2.0, hex 0.4.3, synapse-core at
`synapse.pin` (see `sig/Cargo.lock`), built with the stable Rust toolchain on ubuntu-24.04-arm in CI.

**Missing Omega capability:** an Ed25519 unit (field arithmetic mod 2^255-19, Edwards point
add/double/scalar-mult, SHA-512, RFC 8032 sign/verify) and base58btc for the did:key encoding.
Work in progress elsewhere: omega-mv branch `audit/x509-compat` and lane `X509Compat-3.Ed25519Unit`.

**Replacement plan:** once an Ed25519 unit lands on omega-mv main, bump `omega.pin`, add the unit
to `build.sh`'s concatenation, replace `pe_flush` / `vf_sigs` / `cm_init` child-process calls with
in-process calls, keep the on-disk formats unchanged (key file, pub file, signature domain tag),
re-run `tests/run.sh` (the tamper cases must still fail with `signature`), then delete `sig/`.
