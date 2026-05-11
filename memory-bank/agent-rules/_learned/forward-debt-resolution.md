---
name: "Learned: Forward-debt resolution as Phase 0"
globs: ["memory-bank/archive/**/*.md", "memory-bank/tasks/**/*.md"]
topics: ["build-orchestration", "archive-cleanup", "task-continuation"]
priority: low
evidence_count: 1
last_updated: 2026-05-11
auto_generated: true
---

# Forward-Debt Resolution as Phase 0

- When an archive document flags forward debt (contract divergence, doc-vs-implementation drift, deferred refactor), the consuming task should resolve it as its **Phase 0** — before any other consuming code lands. Resolving the divergence before the first consumer means the architecture doc and implementation stay aligned, downstream phases avoid translation overhead, and the consumer code lands in one pass rather than needing rework after the debt is paid.
- A continuation task's Phase 0 is by definition small (one file refactor, one spec rewrite, optional one doc tightening). Larger forward-debt items should be split into their own task. The Phase 0 pattern is for items that can be addressed in <30 minutes and gate clean Phase 1 implementation.
- At archive time, the "Forward Debt" section of the archive document should explicitly name the **preferred resolution** (a, b, c) so the consuming task picks up the design intent rather than re-deriving it. The TASK-008 archive's clean Forward Debt section ("preferred path per `_learned/service-shape.md`") was the direct input that enabled TASK-009 Phase 0 to land without rework.

## Evidence

| Learning | Source | Date |
|----------|--------|------|
| TASK-008 archive flagged the `Contacts::PhoneNormalizer` nil-or-String contract diverging from the architecture doc's prescribed `Result` struct. TASK-009 addressed this as Phase 0 (single-file refactor + spec rewrite) before Phase 1's controller branch consumed the normalizer. Result: the controller's `phone_result.valid?` call landed in one pass; the architecture doc's prescribed shape matched the implementation byte-for-byte; no mid-build "translate the doc" overhead. | [reflection-TASK-009.md](../../reflection/reflection-TASK-009.md) | 2026-05-11 |
