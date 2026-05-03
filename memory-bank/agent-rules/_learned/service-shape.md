---
name: "Learned: Service Class Shape"
globs: ["app/services/**/*.rb"]
topics: ["service-classes", "testing", "value-objects"]
priority: low
evidence_count: 1
last_updated: 2026-05-03
auto_generated: true
---

# Service Class Shape

- Pure service classes should return typed value objects (`Struct.new(..., keyword_init: true)`) — not raw values, not multiple return types, not exceptions used as control flow. Callers branch on the value. Makes the call site greppable, mockable, and testable without database state. Apply to any service that has more than one outcome (success/failure/skip) or whose result is consumed by a view or controller branch.

## Evidence

| Learning | Source | Date |
|----------|--------|------|
| `OnboardingReplyParser` → `ParsedReply` Struct; `Accountability::DigestAssembler` → `Digest`+`Row`; `Setup::Completion` → `Result.success?`. All three made test pyramid cheap and call sites readable. | [reflection-TASK-001.md](../../reflection/reflection-TASK-001.md) | 2026-05-03 |
