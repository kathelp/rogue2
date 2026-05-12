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

---

## 2026-05-12 — TASK-010 Reflection

### Extracted Patterns
- **html-entity-agnostic-assertions** → amended (evidence count: 1 → 2) and renamed in frontmatter to "Rendered-output spec assertion patterns" — widened scope to cover both the original HTML-entity-agnostic pattern AND a new positive+negative assertion-pair pattern for field-swap regressions. New evidence: TASK-010 Phase 2 tightened five existing spec assertions from `include("marketing strategy")` (passes against both old and new behavior) to `include("Marketing strategy report") + not_to include("Who controls")` (fails old, passes new — the negative assertion is the regression guard).

### Learnings Not Extracted
- **"Audit adjacent template prose when introducing a named data field"** — TASK-010 hit "report report" doubling when deliverable "marketing strategy report" met template prose "submit your first X report". Caught at end-of-build human eyeball, not by any spec. Single-task evidence and `_learned/` is at-or-over the 10-file cap; preserved in the reflection's Extractable Learnings section for promotion if a future task reinforces. The lesson generalizes as: when a refactor replaces inline string-mangling with an explicit data field, the words around it in templates may need pruning.

### systemPatterns.md Updates
- None this round — both extracted/captured learnings are testing/copy practices, not novel architectural patterns.

---

## 2026-05-12 — Consolidation (during TASK-010 archive)

- Files before: 12, Files after: 12
- Merged: 0 (no pair has >50% topic/glob overlap — `build-orchestration`-tagged files [forward-debt-resolution, lighter-route-eligibility, scope-cut-resilience] each describe distinct concerns; `planning`-tagged files [schema-validation, scope-cut-resilience] address different planning steps)
- Expired: 0 (all bullets created May 3 – May 12 2026; well under the 90-day expiry threshold)
- Promoted: 0 (only `service-shape.md` was at the 3-evidence promotion threshold and was already promoted in the May 11 cycle; html-entity-agnostic-assertions.md is at 2-evidence after TASK-010 — one more reinforcement to promote)
- Pruned: 0 (all files are well under the 15-bullet cap)

Note: `_learned/` is 2 files over the configured cap of 10. The cap is enforced at extraction time (prefer amend over create when >= 10), which is why TASK-010's two learnings produced 1 amendment + 1 not-extracted rather than 2 new files. The cap is not retroactively pruned — the 12 existing files were created over the May 3 – May 11 window when the cap was being approached but not yet exceeded.
