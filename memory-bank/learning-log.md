# Learning Log

Chronological record of pattern extraction and consolidation events from task reflections.

---

## 2026-05-03 — TASK-001 Reflection

### Extracted Patterns
- **idempotency** → created `agent-rules/_learned/idempotency.md` (evidence count: 1)
- **time-zones** → created `agent-rules/_learned/time-zones.md` (evidence count: 1)
- **service-shape** → created `agent-rules/_learned/service-shape.md` (evidence count: 1)
- **audit-trail** → created `agent-rules/_learned/audit-trail.md` (evidence count: 1)

### systemPatterns.md Updates
- None this round (all four learnings are coding-practice patterns, not novel architecture; codebase already lives the patterns).

---

## 2026-05-03 — Consolidation (during TASK-001 archive)

- Files before: 4, Files after: 4
- Merged: 0 (no >50% overlap between idempotency / time-zones / service-shape / audit-trail)
- Expired: 0 (all bullets created today; 90-day rule does not fire)
- Promoted: 0 (all `evidence_count: 1`; promotion threshold is 3)
- Pruned: 0 (all files have 1 bullet; well under 15-bullet limit)

---

## 2026-05-03 — TASK-002 Reflection

### Extracted Patterns
- **idempotency** → amended `agent-rules/_learned/idempotency.md` (evidence count: 1 → 2). New bullet: row-status UPDATE-WHERE pattern when the marker IS the domain row.
- **time-zones** → amended `agent-rules/_learned/time-zones.md` (evidence count: 1 → 2). Period derivation in tenant TZ reinforced (Submissions::Capture, DigestAssembler).
- **namespacing** → created `agent-rules/_learned/namespacing.md` (evidence count: 1). Use plural service namespace when noun matches a model class.

### systemPatterns.md Updates
- None this round — same coding-practice patterns; codebase already lives them.

---

## 2026-05-03 — TASK-003 Reflection

### Extracted Patterns
- **idempotency** → amended `agent-rules/_learned/idempotency.md` (evidence count: 2 → 3) and **promoted** to `medium` priority (promotion threshold = 3 met). New bullet: FlowEvent log as state-machine source of truth for multi-step ladders.
- **time-zones** → amended `agent-rules/_learned/time-zones.md` (evidence count: 2 → 3) and **promoted** to `medium` priority. New bullet: mix Date and Time math intentionally — calendar-day boundaries want Date arithmetic; hour-precise thresholds want Time arithmetic anchored on a specific event.

### systemPatterns.md Updates
- None this round (FlowEvent-as-state-machine reinforces an existing TASK-001 pattern; not novel).
