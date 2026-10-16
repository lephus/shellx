---
name: fast-track-push-main
description: "In shellx, user wants short in-chat designs then straight to code, merged and pushed to main; no separate spec/plan review stops"
metadata:
  node_type: memory
  type: feedback
  originSessionId: 513959bd-8e8f-40c9-9924-9d68c40f96df
  modified: 2026-10-14T04:07:55.424Z
---

After approving a design in chat, the user says "ok code đi" and expects implementation, merge into `main` and `git push origin main` without further stops (spec/plan review gates skipped; a short spec doc is still written for the record). They communicate in Vietnamese.

**Why:** On 2026-10-13 they asked to "làm cả 3 việc rồi push lên main" and approved #2 with "ok code đi" rather than reviewing the spec file.

**How to apply:** Keep designs compact (one approval round), run full analyze+tests on merged main before pushing. Flutter is via `~/fvm/versions/3.41.4/bin` (not on PATH). V2 is built on `shellx-v2`; since 2026-10-15 it is NOT pushed to main until the user says so (main pushes now release the desktop app) — see [[v2-work-on-shellx-v2]].
