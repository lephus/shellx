# Flowchart rules

A flowchart shows how a skill runs, as one JSON object:

```json
{
  "trigger": "short phrase from the description",
  "nodes": [
    { "id": "n1", "type": "step", "label": "Measure disk usage", "detail": "optional longer note" }
  ],
  "edges": [
    { "from": "n1", "to": "n2", "label": "optional, short" }
  ]
}
```

- `type` is one of `step`, `decision`, `askUser` or `end`.
- `id` is unique within the flow. `detail`, edge `label` and `trigger` are optional.
- Every edge joins two existing node ids.

Rules:

- The first node is where the work starts. ShellX draws the start pill and, for cronjobs, the notification itself.
- Draw only what SKILL.md says. Do not invent steps, checks or outcomes.
- Every point where the user is asked, or must approve, is an `askUser` node.
- Every destructive or irreversible action (delete, overwrite, send, publish) is its own `step`.
- Conditions the skill checks by itself are `decision` nodes. Every edge leaving a decision carries a short label.
- Labels are at most about 6 words, in the language SKILL.md is written in (in the creator chat: the user's language).
- `trigger` is a short phrase taken from the description, and only for skills.
- Loops are allowed as edges back to an earlier node.
