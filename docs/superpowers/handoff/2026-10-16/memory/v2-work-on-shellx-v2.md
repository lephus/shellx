---
name: v2-work-on-shellx-v2
description: "ShellX V2 work stays on branch shellx-v2; since 2026-10-15 NOT pushed to main until the user says so (main pushes now release the desktop app)"
metadata:
  node_type: memory
  type: project
  originSessionId: 513959bd-8e8f-40c9-9924-9d68c40f96df
  modified: 2026-10-15T06:49:21.523Z
---

On 2026-10-14 morning the user said: "Tất cả đề xuất, code mới này nên nằm ở branch shellx-v2". That evening they changed it: "hãy test, review và đảm bảo shellx cho trải nghiệm tuyệt nhất; tất cả code push lên main".

On 2026-10-15 a teammate added a workflow that releases the desktop app on every non-docs push to `main` (`release-desktop.yml`, commit 5929cdc). Asked about it, the user said: "giữ ở shellx-v2, chưa push main".

**Why:** a push to `main` can now build, sign and publish a desktop release. V2 has not been tried on real devices, so it must not ship by accident.

**How to apply:**
- Keep V2 work on branch `shellx-v2`. Track branches (e.g. `v2-2b`, `v2-3`, `v2-4`) are merged into it after tests and review.
- Do not push to `main`, not even fast-forwards, until the user explicitly says so.
- Pushing `shellx-v2` and track or backup branches to `origin` is fine.
- `relay/**`, `web/**` and `deploy/**` changes deploy to production from `main`. Keep them on their own branch (e.g. `v2-2b-relay`) until the user consents.
- After each completed task, still run the full analyze and tests.
- The parked A6 browser pane stays on `feat/desktop-a6`.
- See [[fast-track-push-main]].
