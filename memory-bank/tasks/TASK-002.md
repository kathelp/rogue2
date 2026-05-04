# TASK-002: Submission Prompt Sender

**Complexity**: Level 3 (inherited from FEAT-002)
**Status**: COMPLETE
**Completed**: 2026-05-03
**Roadmap**: FEAT-002
**Branch**: feature/FEAT-002-submission-prompt-sender (merged + deleted at archive)
**Worktree**: N/A
**Reflection**: memory-bank/reflection/reflection-TASK-002.md
**Archived**: memory-bank/archive/archive-TASK-002.md
**Docs Opt-In**: no
**Docs Opt-In Reason**: No Docusaurus tree at `docs/`; feature is internal-platform infrastructure (recurring sender + form). Revisit when first end-user-facing capability ships beyond the email path.
**Marketing Opt-In**: no
**Marketing Opt-In Reason**: No marketing schema at `db/seeds/marketing/`; no customer-facing landing surface in this feature.

## Task Description

Closes the loop on TASK-001's invitee setup walkthrough. Phase 5 of TASK-001 wrote `submission_prompts` rows at the start of the next reporting period; Phase 6 surfaced them on the digest as "Pending first submission." Nothing actually sends the prompts yet.

This task ships:

1. **The recurring sender** — `SubmissionPromptSenderJob` runs hourly via `config/recurring.yml`, finds `submission_prompts` rows with `scheduled_for <= Time.current` and `status: :pending`, and queues `SubmissionMailer#prompt_email` for each. Idempotent on `submission_prompts.status` — once flipped to `:sent`, never re-sent.
2. **The prompt mailer** — `SubmissionMailer#prompt_email` is sent to the contact who configured the Source (`Source.configured_by_contact`). Subject names the dealership and the metric / period (e.g., "Smith Toyota: time to submit marketing strategy summary for May 2026"). Body includes a per-prompt magic-link to `/submissions/<signed_id>`. From: the per-tenant onboarding address (re-uses the `Threadable` concern).
3. **The submission form** — `Submissions::FormsController#show` renders a form keyed off the `Request.metric_key` (one numeric value field + an optional notes textarea at MVP — per-metric custom forms are FEAT-003+ territory). `#create` runs `Submission::Capture` which creates the `Submission` row, marks the prompt `:fulfilled`, and emits `submission.captured`.
4. **Status feedback** — `Accountability::DigestAssembler` updates: a Source with at least one Submission for the current reporting period flips from `:pending_first_submission` to `:on_time`. Future states (`:late` / `:overdue`) are wired but not asserted at MVP.

**Restricted to `submission_method: :form` at MVP.** Sources with `:csv` or `:api_post` selected at the walkthrough get prompts queued normally but the mailer subject and copy are explicit that "your dealership picked CSV upload — we'll be in touch when the adapter is ready." No form is rendered for those methods. Adapter generation is FEAT-003.

**Explicit MVP boundaries:**
- One Submission per (Request, period). Re-clicking the magic-link after submission lands on a "thanks, already submitted" page.
- Magic-links expire 14 days after the prompt's `scheduled_for` (most cadences are monthly; 14 days covers the typical grace window).
- The form is generic at MVP — one numeric field + notes. Per-metric form schemas (e.g., "marketing strategy" needs a multi-line summary, "website leads" needs three numeric channels) ship in FEAT-003.
- No second-chance reminder emails in this task. Late prompts surface on the next weekly digest; the escalation cascade is FEAT-004.

## Specification

**Feature Type**: End-User Feature (touches the Invited Contact persona — internal staff submitter or vendor user — directly via the inbox + a single-page form).

**Primary Persona**: Invited Contact (per `productBrief.md` — "internal staff submitter" or "vendor user", configured at the TASK-001 setup walkthrough).

**Secondary Personas**: Dealership GM (sees status flip on the next weekly digest); Rogue Staff (no operational surface in this task).

**Creative Exploration Needed**: No. The spec defers per-metric form schemas to FEAT-003 by shipping a generic numeric+notes form at MVP — this resolves the only LOW-confidence area.

### Invocation Method

#### Sender — recurring job
- **Location**: `WeeklyDigestJob` peer in `config/recurring.yml` — `SubmissionPromptSenderJob` declared to run **every hour at minute 7** in production. Other environments enqueue manually (or per-test inline).
- **Element**: No human surface — the job runs by schedule.
- **Visibility**: Internal infra; no external trigger.
- **Confidence**: HIGH (mirrors WeeklyDigestJob pattern from TASK-001 Phase 6).
- **Outcome on run**: For each `SubmissionPrompt` with `status: :pending` and `scheduled_for <= Time.current`:
  - Idempotency-marker: update prompt to `status: :sent, sent_at: Time.current`. The Postgres update is the synchronisation point — concurrent workers race; the loser's update is a no-op (`pending → sent` is a one-way transition).
  - If the matching `Source.submission_method == :form`: queue `SubmissionMailer.with(prompt: prompt).prompt_email.deliver_later`.
  - If the matching `Source.submission_method` is `:csv` or `:api_post`: queue `SubmissionMailer.with(prompt: prompt).adapter_pending_email.deliver_later` (parked-state copy).
  - Emit `FlowEvent.record!(event_type: "submission.prompt_sent", tenant:, subject: prompt, payload: { method: ... })`.

#### Invitee — prompt email
- **Location**: Inbox of `Source.configured_by_contact.email`. Subject: `"<Dealership>: time to submit <metric label> for <period>"` (e.g., `"Smith Toyota: time to submit marketing strategy summary for May 2026"`).
- **Element**: Single CTA button — link text **"Submit your data"** — wrapped in a button-styled table cell (email-client safe, same approach as TASK-001 mailers). Falls back to a plain URL in the plain-text alternative.
- **Visibility**: Anyone holding the signed link. Reusable until expiry (14 days post-`scheduled_for`); after submission, the link routes to a "thanks, already submitted" page.
- **From / Reply-To**: per-tenant onboarding address (`onboarding+<token>@inbound.rogue.example`) via the `Threadable` concern. Replies to this email feed the existing `OnboardingMailbox` — currently they'll route to `:unparseable` since the question-thread resolver won't find an outbound message-id; that's acceptable noise at MVP. A dedicated submissions inbox is a follow-up.
- **Confidence**: HIGH.
- **Outcome on click**: Lands on `GET /submissions/:signed_id` rendered by `Submissions::FormsController#show`.

#### Invitee — submission form
- **Location**: `GET /submissions/:signed_id` backed by `Submissions::FormsController#show`. The `:signed_id` is `SubmissionPrompt#signed_id(purpose: :submission_form, expires_in: 14.days)`.
- **Element**:
  - Step 1: heading naming the dealership, metric, and reporting period (`"Smith Toyota — marketing strategy summary for May 2026"`).
  - Form fields: one numeric `value` (label is `Request.metric_key.humanize`) + one optional `notes` textarea (max 2 KB).
  - Submit button labeled **"Submit"**.
- **Visibility**: Only the recipient with the signed link. Single-effective: subsequent visits after submission show the "already submitted" page.
- **Confidence**: MEDIUM on the generic-form choice — explicitly scoped MVP, refined in FEAT-003 when per-metric forms ship.
- **Outcome on submit**: `POST /submissions/:signed_id` → `Submissions::FormsController#create`:
  - `Submission::Capture.call(prompt:, value:, notes:, contact:)` runs in a transaction:
    - Creates a `Submission` row with `tenant`, `request`, `submission_prompt`, `submitted_by_contact`, `value`, `notes`, `period_starting`, `submitted_at`.
    - Updates `submission_prompts.status = :fulfilled, fulfilled_at = Time.current`.
    - Emits `FlowEvent.record!(event_type: "submission.captured", tenant:, subject: submission)`.
  - Renders a one-page thank-you (heading: "Got it." Body: `"We received your <metric> for <period>. Next prompt: <next_due_date>."`).

### Success Criteria

#### Sender — happy path
- **Given**: A `SubmissionPrompt` exists with `status: :pending`, `scheduled_for: 2.hours.ago`, and its Source has `submission_method: :form`.
- **When**: `SubmissionPromptSenderJob.perform_now`.
- **Then**:
  - The prompt's `status` becomes `:sent`, `sent_at` is set.
  - One `ActionMailer::MailDeliveryJob` is enqueued for `SubmissionMailer#prompt_email` with `params[:prompt]`.
  - On worker drain, an email arrives at the contact's address with subject containing the dealership name and the metric label.
  - Email body contains exactly one CTA link to `/submissions/<signed_id>`.
- **Observable within**: 1 minute of job run.

#### Invitee — submit
- **Given**: A SubmissionPrompt is `:sent`, the contact clicks the magic link.
- **When**: They land on `/submissions/<signed_id>`, fill in `value=42500`, click Submit.
- **Then**:
  - One `Submission` row exists with `tenant`, `request`, `submission_prompt`, `submitted_by_contact_id`, `value: 42500`, `notes: nil`, `period_starting`, `submitted_at`.
  - The prompt's `status` becomes `:fulfilled`.
  - A `submission.captured` FlowEvent is recorded.
  - The contact lands on the thank-you page showing the next prompt date.
- **Data persisted**: `submissions` row + `submission_prompts.status='fulfilled'` + `flow_events` event.

#### Sender — idempotent re-run
- **Given**: A prompt was sent in the previous job run (`status: :sent`).
- **When**: `SubmissionPromptSenderJob.perform_now` runs again with no other state change.
- **Then**: No mail is enqueued; the prompt's `sent_at` is unchanged; no new FlowEvent.

#### Submission — idempotent re-submit
- **Given**: A prompt has been submitted (`status: :fulfilled`); the contact clicks the link again.
- **When**: They land on `/submissions/<signed_id>`.
- **Then**: A "Already submitted" page renders (no form). Re-POSTing to the same path returns the same page (no second `Submission` row).

#### Digest — status flip
- **Given**: A Source has one `Submission` for the current period.
- **When**: `Accountability::DigestAssembler.call(tenant:)` is invoked.
- **Then**: That Source's row has `status: :on_time` (was `:pending_first_submission`).

### Acceptance Criteria

#### AC-ENTRY-1: Invitee finds the prompt email
**Priority**: MUST
- **Given**: Sender job ran and the contact has a due prompt for `Source(submission_method: :form)`.
- **When**: They open their inbox.
- **Then**: A single email from the per-tenant onboarding address with subject `"<Dealership>: time to submit <metric label> for <period>"`, body containing a CTA "Submit your data" linking to `/submissions/<signed_id>`, plain-text alt containing the URL.
- **Verification**:
  - [ ] Mailer test asserts subject pattern.
  - [ ] Mailer test asserts From: includes per-tenant `onboarding+<token>@`.
  - [ ] Mailer test asserts exactly one `<a>` linking to `/submissions/...`.
  - [ ] Mailer test asserts plain-text alt also contains the URL.

#### AC-ENTRY-2: Invitee finds the submission form
**Priority**: MUST
- **Given**: A valid `submission_form` signed_id.
- **When**: GET `/submissions/:signed_id`.
- **Then**: Form page renders with the dealership name, metric label, period heading, one numeric `value` field, one `notes` textarea, one Submit button.
- **Verification**:
  - [ ] Request spec on `Submissions::FormsController#show` asserts 200 + visible field labels.

#### AC-HAPPY-1: SubmissionPromptSenderJob sends one mail per pending due prompt
**Priority**: MUST
- **Given**: 3 `SubmissionPrompt` rows: 2 `:pending` with `scheduled_for: 1.hour.ago`, 1 `:pending` with `scheduled_for: 1.day.from_now`.
- **When**: `SubmissionPromptSenderJob.perform_now`.
- **Then**: Exactly 2 mails are enqueued; the future-scheduled prompt remains `:pending`.
- **Verification**:
  - [ ] Job spec asserts mail count + per-prompt status transitions.

#### AC-HAPPY-2: Submission round-trip
**Priority**: MUST
- **Given**: An invitee with a valid magic link and a prompt in `:sent` state.
- **When**: They GET, POST `value=42500, notes="numbers from the May report"`.
- **Then**:
  - One `Submission` row created with the right tenant / request / prompt / contact / value / notes / period.
  - Prompt `:sent → :fulfilled` with `fulfilled_at` set.
  - `submission.captured` FlowEvent recorded.
  - Response body contains "Got it" heading and the next prompt date.
- **Verification**:
  - [ ] Request spec full-loop GET → POST → success page.
  - [ ] Service spec on `Submission::Capture` for transactional integrity.

#### AC-HAPPY-3: Sender idempotency
**Priority**: MUST
- **Given**: A prompt already in `:sent` state.
- **When**: Job re-runs.
- **Then**: No mail enqueued; `sent_at` unchanged.
- **Verification**:
  - [ ] Job spec asserts second-run delta is zero.

#### AC-HAPPY-4: Submission idempotency
**Priority**: MUST
- **Given**: A prompt in `:fulfilled` state; the contact re-clicks the link.
- **When**: GET `/submissions/:signed_id`.
- **Then**: "Already submitted" page renders (no form). Re-POSTing returns the same page; no new Submission row.
- **Verification**:
  - [ ] Request spec asserts the post-fulfilled GET branch + POST no-op.

#### AC-HAPPY-5: Adapter-pending parked-state mail
**Priority**: SHOULD
- **Given**: A pending due prompt whose Source has `submission_method: :csv` (or `:api_post`).
- **When**: Sender job runs.
- **Then**: An `adapter_pending_email` is sent (different subject + copy) instead of `prompt_email`. The prompt status still flips to `:sent` (so it doesn't loop), but no submission form is offered.
- **Verification**:
  - [ ] Mailer test asserts the parked-state subject + copy mentions "we'll be in touch when the adapter is ready."

#### AC-ERROR-1: Magic-link expired
**Priority**: MUST
- **Given**: A `submission_form` signed_id older than 14 days.
- **When**: GET `/submissions/:signed_id`.
- **Then**: 404 with the expired view ("This submission link has expired."). No leakage of whether the prompt exists.
- **Verification**:
  - [ ] Request spec for the expired-token branch.

#### AC-ERROR-2: Invalid form input
**Priority**: MUST
- **Given**: A valid magic-link.
- **When**: POST with `value=` empty or non-numeric.
- **Then**: 422 with the form re-rendered, an error message, and no Submission row created.
- **Verification**:
  - [ ] Request spec for the validation-error branch.

#### AC-ASYNC-1: Digest status flips after submission
**Priority**: MUST
- **Given**: A Source had `:pending_first_submission` status; a Submission is now captured for it (current period).
- **When**: `Accountability::DigestAssembler.call(tenant:)` is invoked.
- **Then**: The corresponding Row has `status: :on_time`.
- **Verification**:
  - [ ] Service spec on `DigestAssembler` for the configured-with-submission branch.

### Scope Boundaries

#### In scope
- `Submission` model + `submissions` migration (tenant_id, request_id, submission_prompt_id, submitted_by_contact_id, value, notes, period_starting, submitted_at, timestamps).
- Status enum extension on `SubmissionPrompt`: add `:fulfilled` to existing `:pending | :sent | :superseded`.
- `SubmissionPrompt#submission_form_signed_id(expires_in: 14.days)` + finder, similar to TASK-001 magic-link helpers.
- `Submission::Capture` service (transactional creation + prompt status flip + FlowEvent emit).
- `SubmissionPromptSenderJob` (Solid Queue, recurring, declared in `config/recurring.yml`). Eligible: `status: :pending AND scheduled_for <= Time.current`. Idempotent via `:pending → :sent` transition.
- `SubmissionMailer#prompt_email` (form path) + `SubmissionMailer#adapter_pending_email` (csv/api_post parked-state path) + html/text views for both. Re-uses the `Threadable` concern.
- `Submissions::FormsController` (`show` + `create`) + form view + thank-you view + already-submitted view + expired view.
- `Accountability::DigestAssembler` extended: `:pending_first_submission` flips to `:on_time` when at least one `Submission` exists for the current period of any `Request` belonging to the Source.
- FlowEvent additions: `submission.prompt_sent`, `submission.captured`, `submission.adapter_pending_sent`.
- Submission factory (`spec/factories/submissions.rb`).

#### Out of scope (explicit)
- Per-metric form schemas (one generic numeric + notes form for all metrics at MVP). FEAT-003.
- AI-assisted CSV / API adapter generation. FEAT-003.
- Second-chance reminder emails for late prompts. FEAT-004 (escalation cascade).
- Submission editing / deletion / amendment. Submissions are append-only at MVP.
- Per-metric validation rules (we accept any non-negative numeric `value` at MVP). FEAT-003 will codify per-metric ranges.
- Multi-period submission (submitting for a period other than the prompted one). FEAT-005.
- Aggregations / charts (the dashboard remains a placeholder until FEAT-003+).

#### Dependencies
- Action Mailbox (already installed in TASK-001).
- Solid Queue + recurring (already wired in TASK-001 for `WeeklyDigestJob`).
- `WeeklyDigestDelivery` idempotency pattern (TASK-001 Phase 6) is the reference for `SubmissionPromptSenderJob` mechanics.
- `Threadable` mailer concern (TASK-001 Phase 3).

#### NFR implications
- **Idempotency** (Guiding Principle 7): both the sender (status transition is the lock) and the form (re-POST is a no-op via prompt status check).
- **Tenant isolation** (Guiding Principle 5): `submissions.tenant_id NOT NULL` with index. `Current.tenant` set in the controller.
- **Audit trail** (TASK-001 lesson): `FlowEvent` emit for every state transition (sent / captured / adapter-pending-sent).
- **Token security**: `submission_form` purpose, 14-day expiry. Re-use after fulfill is allowed (idempotent re-render); after expiry the resend pattern is via the next scheduled prompt, not a self-serve form.

### Confidence Assessment

#### HIGH confidence
- Migration shape (mirrors `submission_prompts` and `flow_events`).
- Recurring job pattern (mirrors `WeeklyDigestJob`).
- Magic-link pattern (mirrors `SubmissionPrompt#signed_id` purpose helpers from TASK-001).
- `Submission::Capture` transactional shape (mirrors `Setup::Completion` from TASK-001).
- Digest status flip logic (one query against `submissions` joined to `requests` filtered by source + period).

#### MEDIUM confidence
- Generic form at MVP — defensible default; the LOW-confidence per-metric form work is explicitly deferred to FEAT-003.
- Reuse of the per-tenant onboarding address for the prompt email — could be a separate `submissions+<token>@` address for clarity in inbox threading. Defaulting to the existing onboarding address keeps DNS/MX requirements identical.

#### LOW confidence
- (None at MVP — the open question on per-metric form schemas is explicitly punted to FEAT-003.)

## Test Strategy

### Approach
- **Emphasis**: balanced — service-class unit tests for `Submission::Capture` and the digest-flip extension, request specs for the form controller (3 GET branches × 2 POST branches), job spec for the sender (4-5 tiers — pending + due, pending + future, sent, fulfilled, csv/api_post fork), mailer specs for both `prompt_email` and `adapter_pending_email`.
- **Test framework**: RSpec + FactoryBot (already established).
- **Target test count**: ~30-45 across all phases.

### File Organization
- **New**:
  - `spec/models/submission_spec.rb`
  - `spec/factories/submissions.rb`
  - `spec/services/submission/capture_spec.rb`
  - `spec/jobs/submission_prompt_sender_job_spec.rb`
  - `spec/mailers/submission_mailer_spec.rb`
  - `spec/requests/submissions/forms_spec.rb`
- **Extend**:
  - `spec/services/accountability/digest_assembler_spec.rb` — add the `:on_time` branch when a Submission exists.

### What NOT to test
- Solid Queue recurring scheduling (covered by Rails 8).
- `signed_id` cryptography (covered by Rails). We test our purpose-scoping, expiry, and the post-fulfilled rebound-to-already-submitted behavior.
- Postgres uniqueness — there's no new unique constraint.

### Per-Phase Test Guidance
- **Phase 1** (foundation): ~6 tests — model factory + validations + association integrity for `Submission`.
- **Phase 2** (sender + mailer): ~14 tests — `SubmissionPromptSenderJob` (5 branches: pending+due, pending+future, sent, fulfilled, adapter-method fork), `SubmissionMailer#prompt_email` (subject, From/Reply-To, html+text alts, single CTA, mention of metric+period), `SubmissionMailer#adapter_pending_email` (parked-state subject + copy).
- **Phase 3** (form + capture): ~14 tests — `Submissions::FormsController` (show: valid/expired/already-fulfilled; create: success/invalid/idempotent re-post), `Submission::Capture` (3 branches: happy / idempotent / validation), `DigestAssembler` extension (`:on_time` when submission exists for the current period).

### E2E Anchor
- `spec/system/invitee_submits_first_data_point_spec.rb` — Capybara walks: visit form via signed_id, fill `value`, submit, see thank-you. Single test that exercises the full GET → POST → render-success path with realistic factories.

## Implementation Roadmap

### Phasing rationale
Three phases, each closing at a green test boundary:
- Phase 1 lays the data substrate.
- Phase 2 ships the recurring sender + the mailer (no UI yet).
- Phase 3 closes the loop with the form + capture + digest flip.

- [x] **Phase 1 — Foundation** *(COMPLETE 2026-05-03)* (closes the model layer)
  - Migration `create_submissions` (tenant_id, request_id, submission_prompt_id, submitted_by_contact_id, value, notes, period_starting, submitted_at).
  - Migration `add_fulfilled_status_to_submission_prompts` (extend the `status` enum's allowed values; add `fulfilled_at` column).
  - `Submission` ActiveRecord model with `belongs_to`s, validations, `for_period` scope.
  - `spec/factories/submissions.rb`.
  - `spec/models/submission_spec.rb`.
  - **Acceptance**: model spec green; migration up/down clean; factory builds a valid record.

- [x] **Phase 2 — Sender job + prompt mailer** *(COMPLETE 2026-05-03)* (closes AC-ENTRY-1, AC-HAPPY-1, AC-HAPPY-3, AC-HAPPY-5)
  - `SubmissionPromptSenderJob` (Solid Queue, recurring). Filter: `status: :pending AND scheduled_for <= Time.current`. For each: status transition `:pending → :sent` first (synchronisation point), then enqueue mailer based on `Source.submission_method`. Emit `FlowEvent.record!`.
  - `SubmissionMailer` (extends `ApplicationMailer`, includes `Threadable`):
    - `prompt_email` — form-method recipients. Subject names dealership + metric + period. Body has the magic-link CTA.
    - `adapter_pending_email` — csv/api_post recipients. Different subject ("we're getting your CSV adapter ready"); body sets expectations and tells them no action is needed yet.
  - Views for both actions (html + text).
  - `SubmissionPrompt#submission_form_signed_id(expires_in: 14.days)` + `find_by_submission_form_signed_id` finder.
  - `config/recurring.yml`: schedule `SubmissionPromptSenderJob` hourly at minute 7.
  - **Acceptance**: job spec covers 5 branches; mailer specs assert subject/headers/body for both actions; FlowEvent counts verified.

- [x] **Phase 3 — Submission form + capture + digest flip** *(COMPLETE 2026-05-03)* (closes AC-ENTRY-2, AC-HAPPY-2, AC-HAPPY-4, AC-ERROR-1, AC-ERROR-2, AC-ASYNC-1)
  - Routes: `get "/submissions/:signed_id" => "submissions/forms#show", as: :submission_form` and `post "/submissions/:signed_id" => "submissions/forms#create"`.
  - `Submissions::FormsController` (`show` + `create`). Show branches: valid + pending → form, valid + fulfilled → already-submitted, expired/invalid → 404 with expired view. Create: invalid input → 422 re-render; valid input → call `Submission::Capture`, redirect to a thank-you action.
  - `Submission::Capture` service — `Result` value-object pattern (matches `Setup::Completion` from TASK-001). Wraps in transaction: `Submission.create!`, `prompt.update!(status: :fulfilled, fulfilled_at: Time.current)`, `FlowEvent.record!(event_type: "submission.captured", subject: submission)`.
  - Views: `show.html.erb` (form), `already_submitted.html.erb`, `created.html.erb`, `expired.html.erb`.
  - `Accountability::DigestAssembler#status_for` extended: when `Source.submission_method.present? AND any Submission exists for any Request belonging to Source AND `submitted_at` falls inside the current period`, return `:on_time` instead of `:pending_first_submission`.
  - System test: `spec/system/invitee_submits_first_data_point_spec.rb`.
  - **Acceptance**: full request-spec walkthrough green; system spec drives end-to-end happy path; digest-assembler spec asserts the status flip.

## Creative Phases

Per Level 3 + the "MEDIUM confidence on the generic-form choice" assessment, **no formal creative phases are flagged**. The MEDIUM-confidence area (per-metric form schemas) is explicitly deferred to FEAT-003 by shipping a generic numeric+notes form. UI/UX exploration is therefore unnecessary at this complexity; revisit when FEAT-003 lands per-metric forms.

## Clarifications

(none captured — spec is self-contained)

## Spec Review

(skipped — Level 3 + low-risk scope)

## Validation Report

(populated post-build by `/rai-validate` if invoked)

## Live-Dogfood-Pending Tracker

(none — feature is fully exercisable on local dev with Letter Opener)

---

## Execution State

**Build Status**: IDLE
**Current Phase**: COMPLETE
**Last Completed**: Archive (2026-05-03) — `memory-bank/archive/archive-TASK-002.md`
**Can Resume**: NO — task closed.

### Completed Steps
- 2026-05-03 — `/rai-roadmap feature create FEAT-002` — feature added to roadmap.md (Level 3, high priority)
- 2026-05-03 — `/rai-plan TASK-002` — task auto-provisioned from FEAT-002, Specification + Test Strategy + Implementation Roadmap drafted, no creative phases flagged
- 2026-05-03 — Phase 1 Foundation complete: 2 migrations, Submission model + factory, 7 specs. Total 314 examples, 0 failures.
- 2026-05-03 — Phase 2 Sender + Mailer complete: SubmissionPromptSenderJob (atomic UPDATE-WHERE idempotency), SubmissionMailer (prompt_email + adapter_pending_email + html/text views), magic-link helpers on SubmissionPrompt, recurring schedule. 19 specs. Total 333.
- 2026-05-03 — Phase 3 Form + Capture + Digest flip complete: Submissions::FormsController, Submissions::Capture service (renamed from Submission:: to avoid Zeitwerk collision), DigestAssembler `:on_time` branch. 20 specs. Total 353. RuboCop 0 offenses.
- 2026-05-03 — Reflection complete: `memory-bank/reflection/reflection-TASK-002.md`. 3 patterns extracted (idempotency amended +1, time-zones amended +1, namespacing created).
- 2026-05-03 — Archive complete: `memory-bank/archive/archive-TASK-002.md`.
