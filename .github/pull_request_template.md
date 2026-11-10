## What and why

<!-- The symptom in the user's words, then the cause. -->

## Proof

- [ ] `sh tests/gate.sh` passes locally (paste the last line: `=== GATE PASS (N steps)`)
- [ ] **Each new or changed test fails without the fix.** Red against: `<commit sha>`, output pasted below. Not
  "verified" and not a compile error: the failing assertion itself, copied from the run.
  ```
  <the failing assertion, as printed>
  ```
- [ ] Tried on a real server, or why not: <!-- version, client, what was done -->

## Risk

<!-- What could this break for someone who never uses the feature? Which plugins or contracts does it touch? -->
