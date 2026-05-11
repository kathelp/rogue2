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

---

## 2026-05-09 — TASK-008 Reflection

### Extracted Patterns
- **schema-validation** → created `agent-rules/_learned/schema-validation.md` (evidence count: 1). Spec Writer should grep proposed column names against `app/` and `spec/` to surface dead schema before planning builds on it.
- **scope-cut-resilience** → created `agent-rules/_learned/scope-cut-resilience.md` (evidence count: 1). Post-creative scope cuts require regenerating Implementation Roadmap and Test Strategy from scratch, not in-place edits.
- **gating-filter-passthrough** → created `agent-rules/_learned/gating-filter-passthrough.md` (evidence count: 1). When filtering a collection by a related model's state, "no record" → KEEP; only "record exists AND fails gate" → DROP.
- **service-shape** → amended `agent-rules/_learned/service-shape.md` (evidence count: 1 → 2). Two-outcome services may return nil-or-value, but if an architecture doc has specified a Result struct, implement OR update the doc — don't diverge silently.

### systemPatterns.md Updates
- None this round — all four learnings are coding/workflow practices, not novel architectural patterns.

---

## 2026-05-11 — TASK-009 Reflection

### Extracted Patterns
- **service-shape** → amended `agent-rules/_learned/service-shape.md` (evidence count: 2 → 3) and **promoted** to `medium` priority (promotion threshold = 3 met). New evidence: TASK-009 Phase 0 resolved the TASK-008 PhoneNormalizer divergence by refactoring to the architecture-doc-prescribed Result struct shape before any consuming code landed.
- **forward-debt-resolution** → created `agent-rules/_learned/forward-debt-resolution.md` (evidence count: 1). When archive flags forward debt, the consuming task should resolve it as **Phase 0** before any other code consumes the diverged contract.
- **html-entity-agnostic-assertions** → created `agent-rules/_learned/html-entity-agnostic-assertions.md` (evidence count: 1). Spec assertions on HTML-rendered error text should check the error element's `id` plus a regex agnostic to entity encoding (`&#39;` for `'`, etc.).
- **predicate-pair-symmetry** → created `agent-rules/_learned/predicate-pair-symmetry.md` (evidence count: 1). When extending a model with a positive predicate (`verified?`), also add the negation (`unverified?`) if a scope of that name exists or is likely to be added.
- **lighter-route-eligibility** → created `agent-rules/_learned/lighter-route-eligibility.md` (evidence count: 1). Continuation tasks with resolved design questions and bounded scope can run a lighter workflow (skip `/rai-plan`, skip `/rai-creative`, inline build phases) — opt-in escape hatch declared at task creation, not the default.

### systemPatterns.md Updates
- None this round — all five learnings are workflow/coding practices, not novel architectural patterns. The lighter-route eligibility pattern is itself meta-architectural (about how we decide between workflow shapes) and lives more naturally in `_learned/` than in `systemPatterns.md`.
