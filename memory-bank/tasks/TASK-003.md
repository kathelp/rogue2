# TASK-003: Escalation Cascade

**Complexity**: Level 3 (inherited from FEAT-004)
**Status**: COMPLETE
**Completed**: 2026-05-03
**Roadmap**: FEAT-004
**Branch**: feature/FEAT-004-escalation-cascade (merged + deleted at archive)
**Worktree**: N/A
**Reflection**: memory-bank/reflection/reflection-TASK-003.md
**Archived**: memory-bank/archive/archive-TASK-003.md
**Docs Opt-In**: no
**Docs Opt-In Reason**: No Docusaurus tree at `docs/`; feature is internal-platform infrastructure (recurring detector + escalation mailers).
**Marketing Opt-In**: no
**Marketing Opt-In Reason**: No marketing schema at `db/seeds/marketing/`; no customer-facing landing surface in this feature.

## Task Description

Closes the productBrief's "graduated escalation" promise. After a `SubmissionPrompt` ships but no `Submission` lands within the configured grace windows, the escalation cascade fires through four severity levels:

1. **Due-soon reminder** — `due_soon_grace_days` (default 3) before the period closes, send a friendly "heads up, your data is due in N days" reminder to the original contact.
2. **Overdue notice** — `overdue_grace_days` (default 3) past the period close, send a sterner "your submission is overdue" notice to the same contact.
3. **Fallback fan-out** — `fallback_grace_days` (default 4) after the overdue notice, walk through the responsibility's `fallback_contact_emails` (jsonb array, ordered) one at a time. Each fallback gets the same overdue email, and a separate FlowEvent is recorded per fallback.
4. **GM nudge** — when the fallback list is exhausted (or empty) and `gm_grace_days` (default 5) past the last fallback fan-out, send a single email to `tenant.gm_email` naming the responsibility, the original contact, and the fallback chain.

Severity is computed as a **pure function** of `(prompt.scheduled_for, period_length, current_time, escalation_history_for_prompt)`. The detector job is stateless; the FlowEvent log is the single source of truth for "have we escalated at this level for this prompt?"

A submission landing at any time short-circuits the cascade — `Submissions::Capture` already flips the prompt to `:fulfilled`, and the detector's filter (`status: :sent`) excludes fulfilled prompts naturally.

The `Accountability::DigestAssembler` is extended with two new statuses: `:late` (prompt is `:sent`, past `period_end`, but still inside the escalation window) and `:overdue` (past escalation window or after fallback fan-out has begun).

**Explicit MVP boundaries:**

- Grace-window constants live in `OnboardingFlow::EscalationCascade` for now; per-tenant overrides are FEAT-005.
- Mail copy is the same for primary contact, fallbacks, and GM nudge — the differentiator is who's named in the body. Per-severity copy refinement is FEAT-005.
- We do NOT escalate again after the GM nudge (one-shot nudge per period). If the GM ignores it, the next reporting period's cycle restarts the cascade.
- Submissions for past periods (back-fill) do NOT cancel an in-flight cascade for an unrelated period.

## Specification

**Feature Type**: NFR / Operational guarantee (touches the Invited Contact + Dealership GM personas via the inbox).

**Primary Persona**: Dealership GM — the cascade exists so they don't have to chase. Secondary: Invited Contact (primary submitter) and their fallback chain.

**Creative Exploration Needed**: No. Severity rules are mechanical; mailer copy is straightforward; FlowEvent-as-source-of-truth pattern was established in TASK-001.

### Invocation Method

#### Detector — recurring job
- **Location**: `EscalationDetectorJob` declared in `config/recurring.yml` to run **hourly at minute 23** in production. Other environments invoke inline / per-spec.
- **Element**: No human surface — runs by schedule.
- **Outcome on run**:
  - For each `SubmissionPrompt` with `status: :sent` AND `scheduled_for + due_soon_threshold <= now`, the job calls `OnboardingFlow::EscalationCascade.next_action_for(prompt:, now:)`.
  - The cascade returns a `NextAction` value object: `{ severity:, recipient_email:, payload: }` — or `nil` if it's not yet time for the next escalation.
  - On a non-nil return: the job records a `FlowEvent` (`event_type: "escalation.<severity>"`) and queues the matching `EscalationMailer` action.
  - All FlowEvents fire BEFORE the mailer — re-runs of the detector see the FlowEvent and short-circuit, so duplicate emails are impossible.

#### Recipient — escalation email
- **Location**: Inbox of the recipient (primary contact / fallback / GM).
- **From**: per-tenant onboarding address (re-uses `Threadable`).
- **Subject (3 templates)**:
  - `"<Dealership>: <metric label> due in <N> days"` (due_soon)
  - `"<Dealership>: <metric label> is now overdue"` (overdue + fallback fan-out)
  - `"<Dealership>: still no <metric label> for <period>"` (gm_nudge)
- **Body**: HTML+text. Carries a magic-link to the same `Submissions::FormsController` (via the existing `submission_form_signed_id`). For GM nudge, the body names the original contact + fallbacks already pinged.

### Success Criteria

#### Due-soon reminder
- **Given**: A `SubmissionPrompt` with `status: :sent`, `scheduled_for` such that `today` is exactly `due_soon_threshold` days before `period_end` (default 3 days). No prior `escalation.*` FlowEvents for this prompt.
- **When**: `EscalationDetectorJob.perform_now`.
- **Then**: An `escalation.due_soon` FlowEvent is recorded; `EscalationMailer#due_soon_reminder` queued for the primary contact; subject names dealership + metric + "due in 3 days".

#### Overdue notice
- **Given**: Prompt is `:sent`, period end has passed by `overdue_grace_days` (default 3). Prior `escalation.due_soon` exists but no `escalation.overdue` yet.
- **When**: Detector runs.
- **Then**: `escalation.overdue` FlowEvent recorded; mailer queued to primary contact; subject names "now overdue".

#### Fallback fan-out
- **Given**: Prompt is `:sent`. `escalation.overdue` exists. `fallback_grace_days` (default 4) has passed since the overdue FlowEvent. Responsibility has `fallback_contact_emails: ["taylor@...", "casey@..."]`.
- **When**: Detector runs.
- **Then**: `escalation.fallback_fanout` FlowEvent recorded with `payload: { fallback_index: 0, fallback_email: "taylor@..." }`; mailer queued to `taylor@...`. Next detector run after `fallback_grace_days` records a second FlowEvent for `casey@...`.

#### GM nudge
- **Given**: All fallbacks have been notified. `gm_grace_days` (default 5) has passed since the last fallback FlowEvent.
- **When**: Detector runs.
- **Then**: One `escalation.gm_nudge` FlowEvent recorded; mailer queued to `tenant.gm_email`. Subject "still no <metric> for <period>". Body lists the contact chain that was pinged. No further escalations for this prompt.

#### Submission short-circuit
- **Given**: A prompt has been through `due_soon` and `overdue` escalations.
- **When**: A Submission is captured (prompt becomes `:fulfilled`).
- **Then**: Detector excludes the prompt on next run (filter is `status: :sent`); no further escalations fire.

#### Digest reflects late/overdue
- **Given**: A Source's current-period prompt is `:sent`, period_end has passed, no Submission yet.
- **When**: `Accountability::DigestAssembler.call(tenant:)`.
- **Then**: The corresponding Row has `status: :late`. Once `escalation.fallback_fanout` has been recorded, status flips to `:overdue`.

### Acceptance Criteria

#### AC-DETECT-1: Severity classifier is a pure function
**Priority**: MUST
- **Given**: Various `(scheduled_for, fallback_count, escalation_history)` inputs.
- **When**: `OnboardingFlow::EscalationCascade.next_action_for` is called.
- **Then**: Returns the right severity (or `nil`) without hitting any database or sending any mail.
- **Verification**:
  - [ ] Service spec covers due_soon, overdue, fallback_0..n, gm_nudge, and "no action yet" branches.

#### AC-DETECT-2: FlowEvent log is the idempotency anchor
**Priority**: MUST
- **Given**: A prompt that's been through due_soon already.
- **When**: Detector runs again within the same threshold window.
- **Then**: No duplicate FlowEvent; no duplicate mail.
- **Verification**:
  - [ ] Job spec asserts second-run delta is zero.

#### AC-MAIL-1: Due-soon mailer
**Priority**: MUST
- **Given**: A prompt and its primary contact.
- **When**: `EscalationMailer.with(prompt: prompt, severity: :due_soon).escalation_email`.
- **Then**: To the primary contact; subject names dealership + metric + "due in N days"; body has a magic-link to the form; html + text alts.
- **Verification**:
  - [ ] Mailer spec for due_soon variant.

#### AC-MAIL-2: Overdue and fallback mailer
**Priority**: MUST
- **Verification**:
  - [ ] Mailer spec for overdue variant (recipient = primary contact).
  - [ ] Mailer spec for fallback variant (recipient = fallback email; subject same as overdue).

#### AC-MAIL-3: GM nudge mailer
**Priority**: MUST
- **Given**: A prompt that has gone through all fallbacks.
- **When**: GM nudge fires.
- **Then**: To `tenant.gm_email`; subject "still no <metric>"; body lists the names of the contacts already pinged in order.
- **Verification**:
  - [ ] Mailer spec for gm_nudge variant — body asserts the contact chain.

#### AC-DIGEST-1: Late status surfaces on digest
**Priority**: MUST
- **Verification**:
  - [ ] DigestAssembler spec for `:late` (prompt sent, period passed, no submission, no fallback FlowEvent yet).
  - [ ] DigestAssembler spec for `:overdue` (after first fallback FlowEvent).

### Scope Boundaries

#### In scope
- `OnboardingFlow::EscalationCascade` service — pure-function `next_action_for(prompt:, now:)` returning a typed `NextAction` Struct or `nil`.
- `EscalationDetectorJob` — recurring (hourly via `config/recurring.yml`). Iterates `:sent` prompts, calls cascade, records FlowEvent + queues mailer.
- `EscalationMailer#escalation_email` — single mailer action with `severity:` param. Selects subject + body partial based on severity.
- 3 escalation views (or 1 view with severity branches): due_soon, overdue, gm_nudge. HTML + text per severity.
- `Accountability::DigestAssembler#status_for` extended: `:late` and `:overdue` branches based on prompt state + most-recent escalation FlowEvent.
- FlowEvent additions: `escalation.due_soon`, `escalation.overdue`, `escalation.fallback_fanout`, `escalation.gm_nudge`.

#### Out of scope (explicit)
- Per-tenant grace-window overrides (FEAT-005).
- Per-severity copy refinement (FEAT-005 — same body template for all severities at MVP, only subject differs).
- Manual "stop escalation" controls for the GM (FEAT-005).
- Re-escalation after GM nudge (one-shot per period).
- Slack / SMS / push escalation channels.

#### Dependencies
- Solid Queue + recurring (FEAT-001 / FEAT-002).
- `Threadable` mailer concern (FEAT-001).
- `SubmissionPrompt#submission_form_signed_id` (FEAT-002).
- FlowEvent.record! pattern (FEAT-001).

#### NFR implications
- **Idempotency**: FlowEvent log is the single source of truth. The detector emits the FlowEvent BEFORE the mailer; if mailer enqueue fails, the FlowEvent is rolled back (transactional `FlowEvent.record!` + `deliver_later` inside the same transaction).
- **Tenant isolation**: every read filters on `tenant_id`. `Current.tenant` is set in the job per prompt.
- **Audit trail**: every escalation event is recorded; `flow_events` is the report for "how many escalations did Smith Toyota receive last quarter?"

### Confidence Assessment

#### HIGH confidence
- The severity rules are mechanical (linear ladder + grace windows).
- FlowEvent-as-idempotency-anchor is a TASK-001 pattern.
- DigestAssembler extension is a small additive change.

#### MEDIUM confidence
- Single mailer with severity-driven view selection vs. three separate mailer actions. Going with single mailer + severity param to keep view template count minimal at MVP.

#### LOW confidence
- (None — task is mechanical.)

## Test Strategy

### Approach
- Heavy unit tests on `OnboardingFlow::EscalationCascade` (pure function, easy to test). Job spec covers integration. Mailer spec covers each severity.
- **Test framework**: RSpec + FactoryBot.
- **Target**: ~25-35 specs.

### File Organization
- New:
  - `spec/services/onboarding_flow/escalation_cascade_spec.rb`
  - `spec/jobs/escalation_detector_job_spec.rb`
  - `spec/mailers/escalation_mailer_spec.rb`
- Extend:
  - `spec/services/accountability/digest_assembler_spec.rb` — add `:late` and `:overdue` branches.

### Per-Phase Test Guidance
- **Phase 1**: ~12 tests on the cascade service — happy ladder + idempotency-via-FlowEvent + nil-returns.
- **Phase 2**: ~10 tests across job + mailer.
- **Phase 3**: ~3 tests on digest extension; reflection + archive.

## Implementation Roadmap

- [x] **Phase 1 — Cascade service** *(COMPLETE 2026-05-03)* (closes AC-DETECT-1)
  - `app/services/onboarding_flow/escalation_cascade.rb` with `OnboardingFlow::EscalationCascade.next_action_for(prompt:, now: Time.current)` returning `NextAction(severity:, recipient_email:, payload:)` Struct or nil.
  - Severity ladder + grace window constants exposed for spec.
  - **Acceptance**: pure-function spec covers all severity branches.

- [x] **Phase 2 — Detector + EscalationMailer** *(COMPLETE 2026-05-03)* (closes AC-DETECT-2, AC-MAIL-1..3)
  - `app/jobs/escalation_detector_job.rb` — iterates `:sent` prompts, calls cascade, transactional `FlowEvent.record!` + `EscalationMailer.with(...).escalation_email.deliver_later`.
  - `app/mailers/escalation_mailer.rb` with one action `escalation_email(severity:)`. Selects subject + body partial.
  - Views: `escalation_email.html.erb` + `.text.erb` rendering severity-conditional body.
  - `config/recurring.yml`: schedule `EscalationDetectorJob` hourly at minute 23.
  - **Acceptance**: job spec covers FlowEvent idempotency + mailer enqueue per severity; mailer spec covers subject + body per severity.

- [x] **Phase 3 — Digest late/overdue + reflection + archive** *(COMPLETE 2026-05-03)* (closes AC-DIGEST-1)
  - Extend `Accountability::DigestAssembler#status_for`:
    - Find latest `escalation.*` FlowEvent for the source's current-period prompt.
    - No submission + no escalation yet but past period_end → `:late`.
    - At least one `escalation.fallback_fanout` or `escalation.gm_nudge` → `:overdue`.
  - `spec/services/accountability/digest_assembler_spec.rb` extension.
  - Reflection + archive following the FEAT-002 pattern.

## Live-Dogfood-Pending Tracker

(none — feature is fully exercisable on local dev with Letter Opener and travel_to.)

---

## Execution State

**Build Status**: IDLE
**Current Phase**: COMPLETE
**Last Completed**: Archive (2026-05-03)
**Can Resume**: NO — task closed.
