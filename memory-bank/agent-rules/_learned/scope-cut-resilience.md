---
name: "Learned: Post-Creative Scope Cuts Need Full Roadmap Rewrite"
globs: ["memory-bank/tasks/**/*.md"]
topics: ["planning", "build-orchestration"]
priority: low
evidence_count: 1
last_updated: 2026-05-09
auto_generated: true
---

# Post-Creative Scope Cuts Need Full Roadmap Rewrite

- When a user defers a feature scope after creative agents have written their docs, regenerate the Implementation Roadmap and Test Strategy sections from scratch against the reduced scope rather than editing them in-place. In-place edits leave dangling phase references, inconsistent test counts, and stale "this depends on Question N" annotations that no longer apply. The creative docs themselves stay valid — they remain the input to the deferred phase — but everything downstream of plan + creative needs a clean redraft.

## Evidence

| Learning | Source | Date |
|----------|--------|------|
| Mid-cycle on TASK-008 the user directed "skip all FE for now". The 6-phase Roadmap and 12–16 test plan had to be manually rewritten to a 3-phase backend scope with 8–11 tests. In-place editing surfaced inconsistencies (Phase numbering, test-strategy file targets) that took multiple passes to clean up. | [reflection-TASK-008.md](../../reflection/reflection-TASK-008.md) | 2026-05-09 |
