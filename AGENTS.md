# Agent protocol: synapse-claims

1. **Before touching a target, claim it.** Your `--agent` is your exact agent id (for example
   `Coordination.Claims`); `--session` is your session id.
   ```sh
   synapse-claims claim --agent Coordination.Claims --session "$SESSION" \
     --target branch:aien-dev/omega-mv#feat/x --intent "port json reader" --ttl 7200
   ```
   Targets: `repo:OWNER/REPO`, `branch:OWNER/REPO#NAME`, `pr:OWNER/REPO#N`,
   `path:OWNER/REPO:GLOB` (`*` one segment, `**` any depth), `ext:SCHEME:VALUE`
   (e.g. `ext:email:jane@example.org` before drafting outreach to Jane).
2. **Exit 2 means someone else holds it.** stdout names the holder; stderr says
   `synapse-claims: conflict: <target> held by <agent> (<id>) until <expires>: <intent>`.
   Do not work on it. Message the holder (`agent://<agent>`) or pick other work.
3. **Keep the lease alive** with `renew --agent A --id ID` before `expires`. Expired leases are
   closed by `expire` and can no longer be renewed: claim again.
4. **Record progress** with `state --agent A --id ID --state ST --evidence URL`. States: PROPOSED,
   IMPLEMENTED, EXERCISED, QUALIFIED, MERGED, DEPLOYED, NOT_RUN, BLOCKED. Evidence is a URL or path
   that someone else can open.
5. **Release when done:** `release --agent A --id ID --state MERGED --evidence URL`.
6. **Look before claiming:** `who TARGET` lists active overlapping claims; `list` lists all active
   claims; `conflicts` lists colliding pairs (exit 1 if any).
7. **Never message agent://all** (it wakes parked agents). To reach a lane, run
   `synapse-claims list --agent-prefix <Lane>` and message each agent id.
8. **Never edit `claims.jsonl` by hand.** `verify` will report the first broken seq (exit 3) and every
   later append refuses to run until the ledger is repaired.

`shared` claims never conflict; use `--mode shared` for read-only or review work. Repository claims
default to `shared`; branch, PR, path and ext claims default to `excl`.

Exit codes: 0 ok, 1 conflicts found, 2 claim conflict, 3 ledger verification failure, 4 unknown id,
not holder or not active, 64 usage, 70 I/O or signer failure.
