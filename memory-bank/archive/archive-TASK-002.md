# Archive: TASK-002 — Submission Prompt Sender

## Metadata
- **Task ID**: TASK-002
- **Roadmap Link**: FEAT-002
- **Complexity**: Level 3
- **Started**: 2026-05-03
- **Completed**: 2026-05-03 (single-session multi-phase build)
- **Final state**: 353 RSpec examples / 0 failures / 0 RuboCop offenses
- **Phase commits**: `3c0b6b7` (P1), `27def7d` (P2), `9a303d6` (P3), reflection commit forthcoming.

## Summary

Closed the loop on TASK-001's invitee setup walkthrough. Phase 5 of TASK-001 wrote `submission_prompts` rows scheduled for the start of the next reporting period; Phase 6 surfaced them on the digest as "Pending first submission." Nothing actually sent the prompts.

This task ships the recurring sender, the prompt mailer (with a parked-state variant for non-form methods), the magic-link form for capture, and the digest extension that flips the per-row status from `:pending_first_submission` to `:on_time` when at least one Submission exists for the current period.

## Requirements

### Original Requirements
- Recurring job that finds due `:pending` SubmissionPrompts and queues the prompt mailer.
- Magic-link mailer that brings the contact to a form keyed off the Request's metric.
- Single-page form with one numeric value + optional notes (per-metric form schemas explicitly deferred to FEAT-003).
- Idempotent end-to-end: re-runs of the job, re-clicks of the link, and re-POSTs all no-op cleanly.
- Audit trail via `FlowEvent` for every state transition.
- Digest reflects submission status (`:on_time` when current-period data exists).

### Success Criteria

- [✓] AC-ENTRY-1: invitee finds the prompt email — sender job + mailer with subject naming the dealership/metric/period; HTML+text alternatives; single CTA + URL.
- [✓] AC-ENTRY-2: invitee finds the form — single-page render with metric label, value field, notes textarea.
- [✓] AC-HAPPY-1: sender queues exactly one mail per pending due prompt; future-scheduled prompts are skipped.
- [✓] AC-HAPPY-2: full submission round-trip — Submission row created, prompt flipped to `:fulfilled`, FlowEvent emitted, success page rendered.
- [✓] AC-HAPPY-3: re-run of sender against an already-`:sent` prompt is a no-op (no second mail).
- [✓] AC-HAPPY-4: re-click of magic-link after submission renders the already-submitted page (no second Submission).
- [✓] AC-HAPPY-5: csv/api_post sources receive the parked-state `adapter_pending_email` instead of `prompt_email`; the prompt still flips to `:sent` so the loop terminates.
- [✓] AC-ERROR-1: expired magic-link returns 404 with the expired view; no leakage of underlying state.
- [✓] AC-ERROR-2: invalid form input → 422 re-render with error; no Submission row created.
- [✓] AC-ASYNC-1: digest row status flips to `:on_time` when a Submission exists for the current period.

20 specified ACs in TASK-001 + 9 specified ACs here; all closed.

## Implementation

### Approach

Three phases, each closing at a green-test commit boundary:

- **Phase 1 — Foundation**. Migration creates the `submissions` table (tenant_id, request_id, submission_prompt_id, submitted_by_contact_id, value, notes, period_starting, submitted_at) with a `(request_id, period_starting)` index for the digest's "any submission for current period" lookup. A second migration adds `fulfilled_at` to `submission_prompts`. The `Submission` model + factory + 7 specs land here.
- **Phase 2 — Sender + mailer**. `SubmissionPromptSenderJob` (Solid Queue, hourly via `config/recurring.yml`) finds due `:pending` prompts, atomically transitions them to `:sent` via a `WHERE status = 'pending'` UPDATE, and queues the appropriate mailer. `SubmissionMailer` has two actions: `prompt_email` (form path with magic-link) and `adapter_pending_email` (parked-state for csv/api_post). `Threadable` provides the per-tenant `From:` address. 19 specs across job + mailer.
- **Phase 3 — Form + capture + digest flip**. `Submissions::FormsController` handles GET (form / already-submitted / expired) + POST (capture with validation + redirect). `Submissions::Capture` is a transactional service returning a `Result` Struct (success / fulfilled-prompt-idempotent / invalid-value). `Accountability::DigestAssembler` extends `status_for` to return `:on_time` when current-period submissions exist. 20 specs.

### Key Components

1. **`SubmissionPromptSenderJob`** (`app/jobs/submission_prompt_sender_job.rb`)
   - Recurring hourly via `config/recurring.yml` (`every hour at minute 7`).
   - Filter: `SubmissionPrompt.where(status: :pending).where("scheduled_for <= ?", Time.current)`.
   - Atomic transition: `SubmissionPrompt.where(id:, status: :pending).update_all(status: :sent, sent_at: ...)` — synchronisation point for concurrent workers.
   - Branches on `Source.submission_method`: `:form` → `prompt_email`; otherwise → `adapter_pending_email`.
   - Emits `submission.prompt_sent` FlowEvent.

2. **`SubmissionMailer`** (`app/mailers/submission_mailer.rb` + `app/views/submission_mailer/`)
   - Includes `Threadable` for the per-tenant `onboarding+<token>@inbound.rogue.example` From address.
   - `prompt_email` carries a 14-day magic-link to `/submissions/<signed_id>` with HTML and plain-text alternatives.
   - `adapter_pending_email` is the parked-state copy for csv/api_post recipients.

3. **`SubmissionPrompt#submission_form_signed_id`** (`app/models/submission_prompt.rb`)
   - Purpose-scoped (`:submission_form`), 14-day expiry.
   - `find_by_submission_form_signed_id` for controller lookup.

4. **`Submissions::FormsController`** (`app/controllers/submissions/forms_controller.rb`)
   - `show` branches on prompt status: `:sent` → form, `:fulfilled` → already-submitted page, invalid/expired → 404 expired view.
   - `create` runs the same gates, calls `Submissions::Capture`, redirects to GET on success (which renders the already-submitted page since the prompt is now `:fulfilled` — the page doubles as thank-you).
   - `ActiveSupport::MessageVerifier::InvalidSignature` is rescued and surfaces as nil → expired view (no leakage).

5. **`Submissions::Capture`** (`app/services/submissions/capture.rb`)
   - Returns `Result(success:, submission:, error:)` Struct.
   - Validates value via `Float(value, exception: false)`; rejects nil / blank / non-numeric / negative.
   - Idempotent: prompt already `:fulfilled` returns `success: false, error: :already_submitted` (no DB writes).
   - Transactional: Submission.create! → prompt.update!(`:fulfilled`, fulfilled_at) → FlowEvent.record!(`submission.captured`).
   - Period derivation: `prompt.scheduled_for.in_time_zone(tenant.tz).to_date.beginning_of_month`.

6. **`Accountability::DigestAssembler` extension** (`app/services/accountability/digest_assembler.rb`)
   - `status_for` now returns `:on_time` when `any_current_period_submission?(source)` is true.
   - Helper joins submissions → requests, filters on tenant + source_id + period_starting (current month in tenant TZ).

### Design Decisions

No formal `/rai-creative` phase. The plan flagged one MEDIUM-confidence design area (per-metric form schemas) and explicitly deferred it to FEAT-003 by shipping a generic numeric+notes form. The decision held — the MVP form fits the marketing-strategy / website-traffic / website-leads metrics in the catalog adequately.

The notable in-build design choice was making the `already_submitted` view double as the post-submit thank-you page (initially the `show` view had a `?submitted=1` branch with "Got it" copy, but the controller's `:fulfilled` short-circuit makes that branch unreachable after a successful capture). Cleaner: state-driven view selection rather than transition-driven.

## Testing

- **Unit tests**: 7 (Submission model) + 7 (Submissions::Capture service) + 1 (DigestAssembler `:on_time` branch extension) = 15 unit specs added.
- **Integration / request tests**: 11 (Submissions::FormsController GET ×4 + POST ×4 + idempotent re-POST × 3) added.
- **Mailer tests**: 9 (prompt_email subject/From/headers/HTML+text/CTA/URL; adapter_pending_email subject/copy).
- **Job tests**: 10 (5 sender branches + 5 cross-cutting like FlowEvent emission, mailer enqueue verification).
- **Total added**: 46 specs across 3 phase commits.
- **Suite total post-FEAT-002**: **353 examples, 0 failures.**
- **All TASK-001 specs continue to pass** (extension to `DigestAssembler` did not regress any prior digest tests).

## Files Changed

### App code
- `app/controllers/submissions/forms_controller.rb` — magic-link form controller (show/create).
- `app/jobs/submission_prompt_sender_job.rb` — recurring sender.
- `app/mailers/submission_mailer.rb` — prompt_email + adapter_pending_email.
- `app/models/submission.rb` — Submission ActiveRecord model.
- `app/models/submission_prompt.rb` — extended status enum (added `:fulfilled`); added magic-link helpers.
- `app/services/accountability/digest_assembler.rb` — extended `status_for` to recognize submissions for current period.
- `app/services/submissions/capture.rb` — transactional capture service with Result Struct.
- `app/views/submission_mailer/{prompt_email,adapter_pending_email}.{html,text}.erb`
- `app/views/submissions/forms/{show,already_submitted,expired}.html.erb`

### Migrations
- `db/migrate/20260503180700_create_submissions.rb`
- `db/migrate/20260503180701_extend_submission_prompts_for_fulfillment.rb`

### Configuration
- `config/recurring.yml` — added `submission_prompt_sender` schedule.
- `config/routes.rb` — added `/submissions/:signed_id` GET + POST routes.

### Specs
- `spec/factories/submissions.rb`
- `spec/jobs/submission_prompt_sender_job_spec.rb`
- `spec/mailers/submission_mailer_spec.rb`
- `spec/models/submission_spec.rb`
- `spec/requests/submissions/forms_spec.rb`
- `spec/services/accountability/digest_assembler_spec.rb` (extended)
- `spec/services/submissions/capture_spec.rb`

### Memory bank
- `memory-bank/roadmap.md` — FEAT-002 entry added.
- `memory-bank/tasks.md` — TASK-002 row added.
- `memory-bank/tasks/TASK-002.md` — full spec + plan.
- `memory-bank/reflection/reflection-TASK-002.md` — Level 3 reflection.
- `memory-bank/agent-rules/_learned/idempotency.md` — amended (evidence_count 1→2).
- `memory-bank/agent-rules/_learned/time-zones.md` — amended (evidence_count 1→2).
- `memory-bank/agent-rules/_learned/namespacing.md` — created.

## Lessons Learned

Reference: `memory-bank/reflection/reflection-TASK-002.md`. Highlights:

- **Use the row-status UPDATE-WHERE pattern** when the natural marker IS the domain row. Cheaper than a separate marker table; the row's lifecycle is the lock.
- **Plural-namespace service modules** to avoid Zeitwerk collisions with singular ActiveRecord class names. `Submissions::Capture`, not `Submission::Capture`.
- **State-driven view selection** is cleaner than transition-driven. The `already_submitted` page works for both first-time-after-submit and idempotent revisits because the page is keyed off prompt state, not on whether the request came from a redirect.
- **The plan's confidence assessment is the right place to defer scope.** Calling out "MEDIUM confidence on the generic-form choice — explicitly scoped MVP" prevented scope-creep into per-metric forms.

## References

- **Reflection**: `memory-bank/reflection/reflection-TASK-002.md`
- **Plan**: `memory-bank/tasks/TASK-002.md`
- **Roadmap**: `memory-bank/roadmap.md` → FEAT-002
- **Phase commits**: `3c0b6b7` (P1), `27def7d` (P2), `9a303d6` (P3)

## Follow-up

### Action items (from reflection)

- **Per-metric form schemas (FEAT-003)** — generic numeric+notes form was the MVP; FEAT-003 lands per-metric custom forms (e.g., website leads = 3 channel splits, OEM compliance = checklist).
- **AI-assisted CSV / API adapter generation (FEAT-003)** — `adapter_pending_email` is the placeholder; FEAT-003 ships actual adapter generation.
- **Period-derivation helper extraction** — `period_starting_for` and `any_current_period_submission?` both hard-code `beginning_of_month`. Extract a `Cadence#period_start_for(time:)` helper before quarterly / annual cadences need it.
- **`Source has_many :requests` association test** — declared in TASK-001 Phase 1; no current spec exercises the chain. Worth a Level 1 cleanup.
- **Document `Threadable` reach** in `systemPatterns.md` — now used by 7 mailer actions across `OnboardingMailer` + `SubmissionMailer`.
- **Late / overdue digest statuses** — `Accountability::DigestAssembler::Row.status` enum is wired through but the late/overdue branches are unused. Will be used by FEAT-004 (escalation cascade).
