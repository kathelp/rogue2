# Learning Metrics

## Configuration

| Setting | Value | Description |
|---------|-------|-------------|
| Max learned rule files | 10 | Hard cap on files in `agent-rules/_learned/` |
| Expiry period (days) | 90 | Remove unreinforced bullets after this period |
| Promotion threshold | 3 | Promote to `medium` priority at this evidence count |
| Max bullets per file | 15 | Prune to 10 most-evidenced when exceeded |

## Task History

| Task ID | Date | Learnings Extracted | Rules Amended | Rules Created |
|---------|------|--------------------:|-------------:|-------------:|
| TASK-001 | 2026-05-03 | 4 | 0 | 4 |
| TASK-002 | 2026-05-03 | 3 | 2 | 1 |
| TASK-003 | 2026-05-03 | 2 | 2 | 0 |
| TASK-008 | 2026-05-09 | 4 | 1 | 3 |
| TASK-010 | 2026-05-12 | 2 | 1 | 0 |

## Rule Effectiveness

| File | Topics | Evidence Count | Priority | Last Updated |
|------|--------|---------------:|:--------:|:------------:|
| idempotency.md | idempotency, recurring-jobs, inbound-handlers | 3 | medium | 2026-05-03 |
| time-zones.md | time-zones, scheduling | 3 | medium | 2026-05-03 |
| service-shape.md | service-classes, testing, value-objects | 2 | low | 2026-05-09 |
| audit-trail.md | audit-logging, observability, domain-events | 1 | low | 2026-05-03 |
| namespacing.md | namespacing, service-classes, zeitwerk | 1 | low | 2026-05-03 |
| schema-validation.md | planning, schema, spec-writing | 1 | low | 2026-05-09 |
| scope-cut-resilience.md | planning, build-orchestration | 1 | low | 2026-05-09 |
| gating-filter-passthrough.md | filtering, data-modeling, gating | 1 | low | 2026-05-09 |
| html-entity-agnostic-assertions.md | testing, assertion-patterns, field-swap | 2 | low | 2026-05-12 |

## Consolidation History

| Date | Rules Before | Rules After | Merged | Expired | Promoted |
|------|------------:|------------:|-------:|--------:|---------:|
| 2026-05-03 | 4 | 4 | 0 | 0 | 0 |
| 2026-05-03 | 5 | 5 | 0 | 0 | 2 |
| 2026-05-09 | 5 | 8 | 0 | 0 | 0 |
