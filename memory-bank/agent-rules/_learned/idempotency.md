---
name: "Learned: Idempotency"
globs: ["app/jobs/**/*.rb", "app/mailboxes/**/*.rb", "app/services/**/*.rb"]
topics: ["idempotency", "recurring-jobs", "inbound-handlers"]
priority: medium
evidence_count: 3
last_updated: 2026-05-03
auto_generated: true
---

# Idempotency

- Recurring jobs and inbound handlers must establish idempotency via a unique-constraint marker row (`find_or_create_by!` or `create!` with `RecordNotUnique` rescue) BEFORE side effects fire. Protects against re-deliveries, concurrent workers, and accidental re-runs without distributed locks. Apply to any `config/recurring.yml` job, any Action Mailbox `process` method, and any webhook handler.
- When the natural marker row IS the domain row (e.g., a status column on an existing record), use a single-row `UPDATE WHERE status = '<expected>'` as the lock. `affected_rows == 0` means another worker already took the work — no-op. Cheaper than a separate marker table when the row's lifecycle naturally matches the work unit.
- For multi-step state machines (escalation ladders, multi-stage approvals), use the FlowEvent (or equivalent append-only event log) as the source of truth for "what step are we on?" — read it at the top of every detector run, dispatch on the highest-recorded step, write the new step's event before any side effect. No dedicated state column needed; the log is the state.

## Evidence

| Learning | Source | Date |
|----------|--------|------|
| WeeklyDigestDelivery insert-first pattern; Action Mailbox Message-ID dedup; `find_or_create_by!` everywhere domain mutations meet inbound traffic | [reflection-TASK-001.md](../../reflection/reflection-TASK-001.md) | 2026-05-03 |
| `SubmissionPromptSenderJob` uses `SubmissionPrompt.where(id:, status: :pending).update_all(status: :sent, ...)` as the synchronisation point — the row's own status column is the marker, no separate deliveries table needed | [reflection-TASK-002.md](../../reflection/reflection-TASK-002.md) | 2026-05-03 |
| `OnboardingFlow::EscalationCascade` reads the `escalation.*` FlowEvent log to dispatch on next ladder step (due_soon → overdue → fallback_fanout → gm_nudge); `EscalationDetectorJob` writes the FlowEvent before queueing mail — concurrent workers and re-runs short-circuit on the existing event | [reflection-TASK-003.md](../../reflection/reflection-TASK-003.md) | 2026-05-03 |
