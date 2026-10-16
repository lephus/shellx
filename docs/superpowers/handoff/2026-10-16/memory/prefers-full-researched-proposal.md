---
name: prefers-full-researched-proposal
description: "In brainstorming big features, user cuts off one-at-a-time questions and wants a complete, verified, reasoned proposal instead"
metadata:
  node_type: memory
  type: feedback
  originSessionId: c68aea52-eaaf-4b45-9a7d-989a8fedf901
  modified: 2026-10-13T11:51:23.322Z
---

On 2026-10-13, while brainstorming an AI-IDE feature for ShellX, after four sequential multiple-choice questions the user interrupted: "Suy luận và cho tôi chi tiết bạn đề xuất sẽ làm, bạn cần suy luận kỹ và chắc chắn" (reason it through and give me the detailed proposal; be careful and certain).

**Why:** They want Claude to do the reasoning and the fact-checking itself and present a complete, evidence-backed design, rather than drip-feeding questions.

**How to apply:** Ask only the one or two questions whose answers change the architecture. Then research the code and the web, verifying current facts, and present the whole proposal in one message: decisions with evidence and rejected options, phases, risks, an explicit "not yet verified" list, and the remaining decisions as a short numbered list at the end. Related: [[fast-track-push-main]].
