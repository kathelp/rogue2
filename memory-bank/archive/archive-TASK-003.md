# Archive: TASK-003 — Escalation Cascade

## Metadata
- **Task ID**: TASK-003
- **Roadmap Link**: FEAT-004
- **Complexity**: Level 3
- **Started**: 2026-05-03
- **Completed**: 2026-05-03 (single-session multi-phase build)
- **Final state**: 379 RSpec examples / 0 failures / 0 RuboCop offenses
- **Phase commits**: `8fd5c15` (P1 cascade service), `9be2ac2` (P2 detector + mailer), Phase 3 + reflection commit forthcoming.

## Summary

Closes the productBrief's "graduated escalation" promise. After a SubmissionPrompt ships but no Submission lands within configured grace windows, the cascade fires through four severity levels: **due_soon → overdue → fallback_fanout → gm_nudge**. Severity is computed as a pure function of `(prompt, current_time, FlowEvent log for this prompt)`. The detector job is stateless; the FlowEvent log is the single source of truth.

The DigestAssembler is extended with `:late` and `:overdue` row statuses derived from the same FlowEvent log, so the weekly digest reflects in-flight escalations.

## Requirements

### Original Requirements
- Recurring detector that finds `:sent` SubmissionPrompts past their grace windows.
- Pure-function severity classifier driven by the FlowEvent log.
- Single mailer with severity-driven subject + body.
- Idempotent: re-runs and concurrent workers no-op cleanly.
- Digest reflects late/overdue states.

### Success Criteria

- [✓] AC-DETECT-1: Severity classifier is a pure function (database read-only, no side effects).
- [✓] AC-DETECT-2: FlowEvent log is the idempotency anchor — re-runs in the same window don't duplicate.
- [✓] AC-MAIL-1: Due-soon mailer sends to primary contact with magic-link.
- [✓] AC-MAIL-2: Overdue + fallback variants share subject framing; recipients differ.
- [✓] AC-MAIL-3: GM nudge mailer sends to GM with the contact chain named in the body.
- [✓] AC-DIGEST-1: Late/overdue surface on digest.

## Implementation

### Approach

Three phases:

- **Phase 1** — `OnboardingFlow::EscalationCascade` (pure-function classifier returning `NextAction(severity:, recipient_email:, payload:)` Struct or nil). 9 service specs.
- **Phase 2** — `EscalationDetectorJob` (Solid Queue, hourly recurring) + `EscalationMailer` (single action, severity-driven view branching). 15 specs.
- **Phase 3** — `Accountability::DigestAssembler` extended with `:late` / `:overdue` branches. Reflection + archive land in this phase.

### Key Components

1. **`OnboardingFlow::EscalationCascade`** — pure-function severity classifier. Constants: `DUE_SOON_GRACE_DAYS=3`, `OVERDUE_GRACE_DAYS=3`, `FALLBACK_GRACE_DAYS=4`, `GM_GRACE_DAYS=5`. Mixes Date math (calendar-day thresholds for due_soon / overdue) with Time math (occurred_at-anchored for fallback / gm_nudge).
2. **`EscalationDetectorJob`** — `find_each` over `:sent` prompts; calls cascade; on a non-nil action records FlowEvent BEFORE queueing mailer (idempotency anchor). `Current.tenant` set per prompt.
3. **`EscalationMailer#escalation_email`** — single action, four severities. Subjects branch on severity; HTML+text views render `case @severity` with appropriate copy. Uses `Threadable` for per-tenant `From:`. Magic-link via `SubmissionPrompt#submission_form_signed_id` (FEAT-002).
4. **`Accountability::DigestAssembler` extension** — `escalation_status_for(source)` finds the latest `:sent` prompt for a Source, returns `:overdue` if any `escalation.fallback_fanout` or `escalation.gm_nudge` event exists, `:late` if past period_end with no fan-out yet, nil otherwise. `status_for` calls it after the on_time check.
5. **`config/recurring.yml`** schedule: `escalation_detector: every hour at minute 23`.

### Design Decisions

No formal `/rai-creative` phase. The plan flagged one MEDIUM-confidence area (single mailer action with severity branching vs. four separate actions) and resolved it inline by going single-action. Decision held.

The notable in-build decision: switching due_soon and overdue thresholds from Time math to Date math after the first spec failure. The cascade now intentionally mixes the two (Date for calendar-day boundaries, Time for inter-event waits). Captured this as a new bullet in `agent-rules/_learned/time-zones.md`.

## Testing

- **Unit**: 9 specs on the cascade service (covers all 4 severities + idempotency-via-FlowEvent + nil-returns).
- **Integration**: 5 specs on the detector job (single-severity + idempotency + fulfilled-skip + full ladder traversal across travel_to hops).
- **Mailer**: 10 specs across 4 severities (recipient + subject + body assertions; GM-nudge body asserts the fallback chain).
- **Digest extension**: 2 new specs (`:late` and `:overdue` branches).

**Total added**: 24 specs. **Final suite**: **379 examples, 0 failures.**

## Files Changed

### App code
- `app/jobs/escalation_detector_job.rb` — recurring detector.
- `app/mailers/escalation_mailer.rb` — single-action mailer with severity branching.
- `app/services/accountability/digest_assembler.rb` — extended with `escalation_status_for`.
- `app/services/onboarding_flow/escalation_cascade.rb` — pure severity classifier.
- `app/views/escalation_mailer/escalation_email.{html,text}.erb` — severity-conditional.

### Configuration
- `config/recurring.yml` — added `escalation_detector` schedule.

### Specs
- `spec/jobs/escalation_detector_job_spec.rb`
- `spec/mailers/escalation_mailer_spec.rb`
- `spec/services/onboarding_flow/escalation_cascade_spec.rb`
- `spec/services/accountability/digest_assembler_spec.rb` (extended)

### Memory bank
- `memory-bank/roadmap.md` — FEAT-004 added.
- `memory-bank/tasks.md` — TASK-003 row added.
- `memory-bank/tasks/TASK-003.md` — full spec + plan.
- `memory-bank/reflection/reflection-TASK-003.md` — Level 3 reflection.
- `memory-bank/agent-rules/_learned/idempotency.md` — amended (evidence_count 2→3) and **promoted** to `medium` priority.
- `memory-bank/agent-rules/_learned/time-zones.md` — amended (evidence_count 2→3) and **promoted** to `medium` priority.

## Lessons Learned

Reference: `memory-bank/reflection/reflection-TASK-003.md`. Highlights:

- **FlowEvent log as state-machine source of truth** generalized cleanly from TASK-001's domain events to TASK-003's escalation ladder. No dedicated state column needed.
- **Mix Date and Time math intentionally** in scheduling logic. Calendar-day boundaries → Date math. Hour-precise inter-event waits → Time math anchored on `occurred_at`.
- **Single mailer action with severity branching** kept template count to one and `case @severity` blocks small. Trade-off acceptable at MVP.

## References

- **Reflection**: `memory-bank/reflection/reflection-TASK-003.md`
- **Plan**: `memory-bank/tasks/TASK-003.md`
- **Roadmap**: `memory-bank/roadmap.md` → FEAT-004
- **Phase commits**: `8fd5c15`, `9be2ac2`, Phase 3 forthcoming.

## Follow-up

- **Per-tenant grace-window overrides (FEAT-005)** — current constants are module-level. FEAT-005 will likely add per-tenant or per-Responsibility override columns.
- **Per-severity copy refinement (FEAT-005)** — same body template across severities at MVP; FEAT-005 may refine tone progression.
- **Digest UX for late/overdue rows** — status column already renders the symbol; FEAT-005 could add color/icon distinction.
