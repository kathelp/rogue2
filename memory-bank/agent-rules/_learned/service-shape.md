---
name: "Learned: Service Class Shape"
globs: ["app/services/**/*.rb"]
topics: ["service-classes", "testing", "value-objects"]
priority: low
evidence_count: 2
last_updated: 2026-05-09
auto_generated: true
---

# Service Class Shape

- Pure service classes should return typed value objects (`Struct.new(..., keyword_init: true)`) — not raw values, not multiple return types, not exceptions used as control flow. Callers branch on the value. Makes the call site greppable, mockable, and testable without database state. Apply to any service that has more than one outcome (success/failure/skip) or whose result is consumed by a view or controller branch.
- Two-outcome services (valid-result vs nil) MAY return nil-or-value directly, but if any architecture or design doc has already specified a Result struct shape and downstream stubs assume `.valid?`, either implement the Result struct OR update the architecture doc and consuming stubs in the same change. A divergence between architecture-doc shape and implementation shape is forward-compatibility debt that bites the next phase.

## Evidence

| Learning | Source | Date |
|----------|--------|------|
| `OnboardingReplyParser` → `ParsedReply` Struct; `Accountability::DigestAssembler` → `Digest`+`Row`; `Setup::Completion` → `Result.success?`. All three made test pyramid cheap and call sites readable. | [reflection-TASK-001.md](../../reflection/reflection-TASK-001.md) | 2026-05-03 |
| `Contacts::PhoneNormalizer` returned nil-or-String while the architecture doc specified `Result = Struct.new(:normalized, :valid?, ...)` and the deferred controller stub used `phone_result.valid?`. Divergence detected at reflection, not at build — a reconciliation gate would have surfaced it earlier. | [reflection-TASK-008.md](../../reflection/reflection-TASK-008.md) | 2026-05-09 |
