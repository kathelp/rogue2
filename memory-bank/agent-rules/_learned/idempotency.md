---
name: "Learned: Idempotency"
globs: ["app/jobs/**/*.rb", "app/mailboxes/**/*.rb", "app/services/**/*.rb"]
topics: ["idempotency", "recurring-jobs", "inbound-handlers"]
priority: low
evidence_count: 1
last_updated: 2026-05-03
auto_generated: true
---

# Idempotency

- Recurring jobs and inbound handlers must establish idempotency via a unique-constraint marker row (`find_or_create_by!` or `create!` with `RecordNotUnique` rescue) BEFORE side effects fire. Protects against re-deliveries, concurrent workers, and accidental re-runs without distributed locks. Apply to any `config/recurring.yml` job, any Action Mailbox `process` method, and any webhook handler.

## Evidence

| Learning | Source | Date |
|----------|--------|------|
| WeeklyDigestDelivery insert-first pattern; Action Mailbox Message-ID dedup; `find_or_create_by!` everywhere domain mutations meet inbound traffic | [reflection-TASK-001.md](../../reflection/reflection-TASK-001.md) | 2026-05-03 |
