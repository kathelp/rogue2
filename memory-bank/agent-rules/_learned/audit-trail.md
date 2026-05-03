---
name: "Learned: Audit Trail via FlowEvent"
globs: ["app/mailboxes/**/*.rb", "app/services/**/*.rb", "app/jobs/**/*.rb", "app/controllers/**/*.rb"]
topics: ["audit-logging", "observability", "domain-events"]
priority: low
evidence_count: 1
last_updated: 2026-05-03
auto_generated: true
---

# Audit Trail via FlowEvent

- Record domain events through a single `FlowEvent.record!` call inside the same transaction that performs the domain mutation. Do not build a separate audit/events service. Keeps the audit and the mutation atomic, and makes "what happened to X on Y" a one-query lookup against `flow_events`. Apply to any state transition, any external-traffic acknowledgment, any cross-cutting domain event.

## Evidence

| Learning | Source | Date |
|----------|--------|------|
| 10+ event_types emitted across phases (reply.parsed, responsibility.created, question.skipped/revisited, vendor.clarification_*, source.configured, digest.sent, etc.) with `subject:` + `payload:` columns; downstream handler reads payload from prior event to resume vendor-clarification flow | [reflection-TASK-001.md](../../reflection/reflection-TASK-001.md) | 2026-05-03 |
