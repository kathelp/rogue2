# Progress Log

Implementation status and phase completion tracking.

---

## TASK-001 — Phase 4: Inbound reply pipeline (2026-05-03, resumed after crash)

- ApplicationMailbox routes `onboarding+...` and bare `onboarding@` (plus-stripped fallback) to `OnboardingMailbox`.
- `OnboardingMailbox` dispatcher: resolves tenant via plus-token (with In-Reply-To/References fallback), gates sender to `Tenant.gm_email_normalized`, persists parser metadata onto `ActionMailbox::InboundEmail`, updates `Tenant.last_gm_reply_at`, and emits `FlowEvent` rows for every branch (reply.parsed, responsibility.created, question.skipped, question.revisited, reply.unparseable, reply.rejected_non_gm_sender, vendor.clarification_requested, vendor.bootstrap_from_clarification).
- `OnboardingReplyParser` (pure service, never raises) with four submodules: `CcOrdering` (wire-order-trusted, warns `:cc_order_uncertain` for known re-orderers), `BodyExtractor` (`email_reply_trimmer` + Nokogiri quote stripping + signature regex; surfaces `:html_only_reply`, `:html_plain_diverged`, `:empty_body`), `SkipDetector` (deterministic single-line regex), `ThreadResolver` (In-Reply-To / References → `tenant_questions.outbound_message_id`). Returns `ParsedReply` value object with intent, primary, fallbacks, question, raw_excerpt (4 KB cap), confidence, warnings.
- `VendorInferenceService` classifies `:internal_staff` / `:vendor_user` / `:unknown` via domain match against `Tenant.gm_email_normalized` then `Vendor.active_vendors.matching_domain`.
- Clarification round-trip: unknown domain emits `vendor_clarification` mailer; GM reply matching `internal` / `vendor: <Name>` re-runs assignment with the disambiguated context (looks up the ambiguous email from the prior `FlowEvent` payload).
- `OnboardingFlow::AdaptivePacing` implements J3: 12h / 24h / 48h tiers and `nil` (silence) at ≥72h. Called by `OnboardingMailbox` to compute next-question wait and the in-thread ack's "next question coming…" copy.
- `OnboardingMailer` extended with `in_thread_ack`, `gm_only_thread_notice`, `vendor_clarification` actions plus html+text views. `OnboardingMailerHelper.humanize_next_question_at` renders relative phrasing.
- Skip + revisit: `SkippedQuestion` written on skip, marked `revisited_at` when GM later assigns on the same thread; the active responsibility is superseded by the new one.
- Source created/found by `(tenant, domain, responsibility_key)` tuple per question.
- Phase 2 touch-up: cleared 2 pre-existing rubocop offenses in `config/routes.rb`.

**Build & Quality**: 242 examples, 0 failures (Phase 4 added 57). RuboCop 0 offenses.

---

## TASK-001 — Phase 5: Invitee setup walkthrough (2026-05-03)

- `OnboardingMailer#invitee_setup_email` — sent to the assigned non-GM contact after a parsed `:assign` reply. Subject `"<Dealership>: data collection assignment"`, From the per-tenant onboarding address, html + plain-text alternative, CTA "Set up data collection" pointing to `/setup/<signed_id>`. Self-assigned (intent `:self_assign`) does not trigger this email — the GM is the contact and already has setup context.
- `Contact#invitee_setup_signed_id(expires_in: 7.days)` and `Contact.find_by_invitee_setup_signed_id` — purpose-scoped magic-link helpers (per `systemPatterns.md` Magic Links pattern).
- `Setup::WalkthroughsController` — single-controller, three-step flow at `/setup/:signed_id`:
  - GET (no `step`) → Step 1 summary (assignment context + Continue link).
  - GET `?step=method` → Step 2 method picker (radio form for `form` / `csv` / `api_post`).
  - PATCH → submits, redirects to `?step=done` (Step 3 confirmation with next-due-date).
  - Resumable: a configured Source short-circuits to Step 3 regardless of the `step` query param.
  - Expired/invalid signed_id → 404 with the expired-page copy (does not leak whether the contact exists).
- `Setup::Completion` service — wraps Source update + Request provisioning + SubmissionPrompt scheduling + FlowEvent recording in a single transaction. Returns a `Result` struct so the controller branches cleanly on bad input.
- `OnboardingFlow::RequestProvisioning` — reads the catalog metric list for the question's `key` and `find_or_create`s one `Request` per metric on the Source. Idempotent.
- `OnboardingFlow::SubmissionPromptScheduler` — for each Request on the Source, schedules a pending `SubmissionPrompt` for the start of the next reporting period in the tenant's time zone (weekly → next Monday 00:00 local; monthly → 1st of next month; quarterly → 1st of next calendar quarter; semi_annual / annual analogously). Idempotent on `(tenant, request, status: :pending)`.
- `Rogue::QuestionCatalog::Marketing::V1.metrics_for(key:)` — returns the metric list for a question key (empty array if unknown).
- `OnboardingMailbox#handle_assignment` extended: after creating the Source and before marking the question answered, calls `RequestProvisioning` and (when `:assign`, not `:self_assign`) queues `invitee_setup_email`. This also addresses the Phase-4 gap where AC-HAPPY-3 spec language called for Request rows but Phase 4 only created the Source.

**Build & Quality**: 279 examples, 0 failures (Phase 5 added 37). RuboCop 0 offenses.

---

## TASK-001 — Phase 6: Weekly digest + dashboard placeholder (2026-05-03)

- `AccountabilityMailer#weekly_digest` — sent to `Tenant.gm_email`. Subject `"<Dealership> — weekly accountability digest"`. Body: per-responsibility table (responsibility, owner, status, next due) plus a single "Open dashboard" CTA. Empty-state copy ("No submissions yet — we'll keep this digest going every week so nothing slips") for tenants with no active responsibilities.
- `Accountability::DigestAssembler` service — pure: returns a `Digest` value object with one `Row` per active Responsibility. Statuses: `:pending_setup` (Source unconfigured), `:pending_first_submission` (Source configured but no submissions), and the future-state values (`:on_time`, `:late`, `:overdue`) wired through but unused at MVP. `next_due_at` reads the earliest pending SubmissionPrompt for the Source.
- `WeeklyDigestJob` (Solid Queue, declared in `config/recurring.yml` to run Mondays at 9am) — iterates eligible tenants (`status IN (confirmed, active) AND confirmed_at <= 7.days.ago`), inserts a `WeeklyDigestDelivery` row first (unique on `(tenant_id, week_starting)`) and only delivers the mailer on insert success. Records `digest.sent` FlowEvent. Idempotent across re-runs and across concurrent workers (the unique constraint is the synchronisation point — `RecordNotUnique` is rescued and treated as a no-op).
- `WeeklyDigestDelivery` model + migration `20260503180611_create_weekly_digest_deliveries` — stores `tenant_id`, `week_starting` (date), `delivered_at`, with a unique index on `(tenant_id, week_starting)`.
- `Tenant#dashboard_signed_id(expires_in: 8.days)` and `Tenant.find_by_dashboard_signed_id` — purpose-scoped helpers (`:dashboard_drilldown`). 8-day expiry so the next digest's link supersedes the prior one with one day of overlap.
- `DashboardsController#show` at `/dashboard/:signed_id` — read-only placeholder. Renders the same `DigestAssembler` data as the email (per-row table). Bad/expired token → 404 with the expired view (no leakage of whether the tenant exists).

**Build & Quality**: 307 examples, 0 failures (Phase 6 added 28). RuboCop 0 offenses.

---

## TASK-001 — BUILD_COMPLETE summary (2026-05-03)

All 6 phases complete on `feature/FEAT-001-tenant-gm-email-onboarding`:

- Phase 1: data model + question catalog + vendor seed (89 examples).
- Phase 2: tenant seed + GM confirm (147 examples cumulative; +58).
- Phase 3: first question email + adaptive scheduling (185 examples cumulative; +38).
- Phase 4: inbound reply pipeline + parser + vendor inference + adaptive pacing + ack mailers (242 examples cumulative; +57).
- Phase 5: invitee setup walkthrough + Request provisioning + SubmissionPrompt scheduler (279 examples cumulative; +37).
- Phase 6: weekly digest + dashboard placeholder + recurring job (307 examples cumulative; +28).

**Final**: 307 examples, 0 failures. RuboCop 0 offenses.

Closed acceptance criteria: AC-ENTRY-1, AC-ENTRY-2, AC-ENTRY-3, AC-ENTRY-4; AC-HAPPY-1 through AC-HAPPY-8; AC-ERROR-1 through AC-ERROR-5; AC-ASYNC-1 through AC-ASYNC-3; AC-NAV-1, AC-NAV-2.

**Next**: `/rai-reflect TASK-001` (mandatory for Level 4), then `/rai-archive TASK-001`.

---

## TASK-001 — Reflection (2026-05-03)

- **Document**: `memory-bank/reflection/reflection-TASK-001.md`
- **Dimensions evaluated**: Task implementation quality (architecture, technical successes/challenges, process) + Claude Code ecosystem (commands, workflow, context, tools, sub-agents, memory bank, scalability)
- **Patterns extracted to `agent-rules/_learned/`** (4 new files; consolidate-first cap is 10):
  - `idempotency.md` — recurring jobs and inbound handlers establish idempotency via marker rows before side effects
  - `time-zones.md` — derive zone from tenant/TimeWithZone, never `Time.zone`, in tenant-scoped code
  - `service-shape.md` — pure services return typed Struct value objects with `keyword_init`
  - `audit-trail.md` — `FlowEvent.record!` inside the same transaction as the domain mutation; no separate audit service
- **Status**: REFLECTION_COMPLETE
- **Next**: `/rai-archive TASK-001` (mandatory for Level 4) — PR `feature/FEAT-001-tenant-gm-email-onboarding` → `main`.

---

## Task Archive: TASK-001

**Task**: Tenant + GM Email-First Onboarding
**Status**: ✅ ARCHIVED
**Date**: 2026-05-03
**Archive**: `memory-bank/archive/archive-TASK-001.md`
**Carry-forward**: FEAT-Ops-Cutover (production email ingress + outbound provider + S3 raw-payload archive — pending QA / prod environment)

---

## TASK-002 — Submission Prompt Sender (FEAT-002, Level 3, 2026-05-03)

Phase summary:
- Phase 1: 7 specs (Submission model + 2 migrations + factory). Total 314.
- Phase 2: 19 specs (SubmissionPromptSenderJob + SubmissionMailer + magic-link helpers + recurring schedule). Total 333.
- Phase 3: 20 specs (Submissions::FormsController + Submissions::Capture + DigestAssembler `:on_time` flip). Total 353.

**Build & Quality**: 353 examples, 0 failures (FEAT-002 added 46 specs over the FEAT-001 baseline of 307). RuboCop 0 offenses.

Reflection captured 3 patterns: idempotency (amended; `pending → sent` UPDATE-WHERE pattern), time-zones (amended; period-derivation reinforcement), namespacing (created; plural service module names to avoid Zeitwerk model collisions).

## Task Archive: TASK-002

**Task**: Submission Prompt Sender
**Status**: ✅ ARCHIVED
**Date**: 2026-05-03
**Archive**: `memory-bank/archive/archive-TASK-002.md`

---

## TASK-003 — Escalation Cascade (FEAT-004, Level 3, 2026-05-03)

Phase summary:
- Phase 1: 9 specs (OnboardingFlow::EscalationCascade pure-function classifier). Total 362.
- Phase 2: 15 specs (EscalationDetectorJob + EscalationMailer with severity-driven branching). Total 377.
- Phase 3: 2 new specs (DigestAssembler `:late` / `:overdue` branches). Total 379.

**Build & Quality**: 379 examples, 0 failures (FEAT-004 added 26 specs). RuboCop 0 offenses.

Reflection captured 2 patterns: idempotency (amended; FlowEvent log as state-machine source of truth) and time-zones (amended; mix Date and Time math intentionally). Both **promoted** to `medium` priority — promotion threshold (3 evidence rows) reached.

## Task Archive: TASK-003

**Task**: Escalation Cascade
**Status**: ✅ ARCHIVED
**Date**: 2026-05-03
**Archive**: `memory-bank/archive/archive-TASK-003.md`

---

## TASK-004 — Escalation Refinements (FEAT-005, Level 2, 2026-05-08)

Single-phase build. Three additive refinements to FEAT-004:
- Per-tenant grace window overrides (4 new optional `tenants` columns; cascade reads tenant first, falls back to module defaults).
- Per-severity body partials (one shared template + 4 partials × 2 formats; replaced inline `case @severity` block).
- Status badges (`AccountabilityHelper#status_badge` returns inline-styled spans; wired into digest email + dashboard).

**Build & Quality**: 394 examples, 0 failures (FEAT-005 added 15 specs). RuboCop 0 offenses.

## Task Archive: TASK-004

**Task**: Escalation Refinements
**Status**: ✅ ARCHIVED
**Date**: 2026-05-08
**Archive**: `memory-bank/archive/archive-TASK-004.md`

---

## TASK-007 — gm_nudge CCs responsibility chain (Level 1, 2026-05-09)

Single-file scope. The `gm_nudge` rung of the escalation cascade now CCs every responsible party (active Responsibility's `primary_contact` + `fallback_contact_emails`); other rungs unchanged. Cascade emits `primary_email` in the gm_nudge `NextAction` payload sourced from the active Responsibility (not `source.configured_by_contact`); mailer's new `cc_for` helper dedups and filters the recipient. Merged into `main` via `c34674c`.

**Build & Quality**: 398 examples, 0 failures.

## Task Archive: TASK-007

**Task**: gm_nudge CCs responsibility chain
**Status**: ✅ ARCHIVED
**Date**: 2026-05-10
**Archive**: `memory-bank/archive/archive-TASK-007.md`

---

## TASK-009 — Phase 0: Contacts::PhoneNormalizer::Result struct (FEAT-006 FE pass, Level 3, 2026-05-10)

Resolved forward debt from TASK-008 archive. `Contacts::PhoneNormalizer.call` now returns `Result = Struct.new(:normalized, :valid?, keyword_init: true)` exactly per the FEAT-006 architecture doc — `.normalized` is the E.164 string when valid, nil otherwise; `.valid?` is the predicate the upcoming `Setup::WalkthroughsController#update` identity branch will branch on. No callers exist yet; isolated contract change.

Spec rewritten against the struct (`.normalized` + `.valid?`). Net spec count: was 10, now 13 (split the single blank-input it-block into three separate specs for nil/empty/whitespace + added a struct-type assertion). No production code beyond the normalizer touched. Architecture doc shape matches implementation exactly — no doc edit needed.

**Build & Quality**: 424 examples, 0 failures. `rubyfmt --check` exits 0 globally.

## TASK-009 — Phase 1: Identity step controller + view + ancillary edits (2026-05-10)

The FE surface for FEAT-006 is now live. CC'd contacts arrive at `/setup/<signed_id>` and now land on a Step 1 of 4 identity form (per UI/UX Sub-Decision 2: single-column inline-CSS, three required fields, aria-described errors above each input, phone hint always visible). On successful PATCH the controller writes `Contact.update! + FlowEvent.record!(event_type: "contact.verified")` atomically and redirects to `step=summary`. Failures rerender with 422, per-field error text + `aria-invalid`, and preserve submitted values (first/last from `@contact.assign_attributes`, raw phone from `@phone_attempt` because the `:phone` column is encrypted non-deterministically and can't accept the pre-normalized string).

Implementation:
- New `app/views/setup/walkthroughs/identity.html.erb` — verbatim per UI/UX Sub-Decision 2.
- `Setup::WalkthroughsController` extended: `template_for_step` returns `:identity` when `@contact.unverified?` (after the configured-source resume short-circuit); `update` branches on `params.key?(:contact)` into `handle_identity_update` vs the existing `handle_source_update`.
- `Contact#unverified?` instance predicate added (`!verified?`) to mirror the existing `verified?` and the `:unverified` scope.
- View renumbering: `summary.html.erb` → "Step 2 of 4"; `method_picker.html.erb` → "Step 3 of 4".
- `done.html.erb` greets by first name: `You're set up, <FirstName>.`
- `summary.html.erb` empty-responsibility else-branch refreshed with "Your details are saved, X" acknowledgment; Continue link wrapped in `<% if @responsibility %>` so post-identity contacts without an active assignment don't see a button that leads to a dead end.

Spec changes:
- `walkthroughs_spec.rb`: 18 new request specs (33 total, was 15). The existing top-level `let(:contact)` switched to `:verified` trait so the pre-identity tests still exercise the post-identity flow; a new `describe "Identity step (FEAT-006 FE pass)"` block creates an unverified contact for the new flow coverage.
- Existing FEAT-001 full-loop system spec (`gm_email_first_onboarding_full_loop_spec.rb`) updated to walk the identity step (Alex fills in name + phone before reaching the assignment summary).

Surprises:
- Rails HTML-escapes the apostrophe in `"can't be blank"` to `&#39;`. First test pass failed on three blank-field assertions matching the un-escaped string. Tightened those assertions to check the `id="<field>-error"` element plus a regex `/Field name.{0,20}blank/` that's agnostic to the entity encoding. Cleaner than escaping the test strings.
- `Contact` had a `verified?` instance predicate + `:verified`/`:unverified` scopes from TASK-008, but no `unverified?` instance predicate. Added it (one-liner) rather than uglying up the controller with `!@contact.verified?`.

**Build & Quality**: **442 examples, 0 failures** (18 added in this phase). `rubyfmt --check` exits 0 globally.

## TASK-009 — Phase 2: OnboardingMailer#invitee_setup_email edits (2026-05-10)

Setup-invitation email subject and both body templates rewritten per UI/UX Sub-Decision 1. Subject changed from `"<Dealership>: data collection assignment"` to `"<Dealership>: set up your details and how you'll send data"` — honest about the three-step ask (name + phone + method) and consistent with the existing colon-separator subject pattern. Both `invitee_setup_email.html.erb` and `.text.erb` replaced verbatim from the doc:
- Heading unchanged: `You've been added to <Dealership>'s data setup`.
- Body softened from "named you as the person to handle this" → "asked you to handle this" (less formal, more recognizable to a busy person).
- Expectation-setting sentence: "It takes about a minute. You'll confirm your name and phone number, then pick how you want to send data." (was: "To finish setup (about a minute), click below").
- CTA: "Set up your assignment" (was: "Set up data collection") — matches the in-app step label.
- Reassurance footer: "No password or account needed — just your name, phone, and a submission preference."

Two parallel specs (mailbox + system) updated because they look the email up by subject substring. The mailer spec gained four assertions (CTA copy, ~1-minute language in HTML and text, "name and phone" framing in both parts).

Manually rendered via `bin/rails runner` to eyeball output — text body matches the doc verbatim, and the dev-only conductor reply link (from TASK-006) auto-fills the new subject correctly into the action_mailbox conductor URL.

**Build & Quality**: **444 examples, 0 failures** (2 added in this phase). `rubyfmt --check` exits 0 globally.

## TASK-009 — Phase 3: System E2E spec (AC-INTEGRATION-1, 2026-05-11)

One Capybara-driven system spec stitches the FEAT-006 round-trip together: GM reply → mailbox promotes Alex unverified → Alex completes identity → escalation cascade re-evaluates and stops filtering him. The spec drives a real inbound email through `OnboardingMailbox#handle_assignment` (creating Alex's Contact + Responsibility + Source + queued setup email), synthesizes a parallel `marketing_budget` responsibility that names Alex as a fallback, asserts `EscalationCascade.send(:fallback_emails_for, prompt)` excludes Alex pre-verification, reads the setup URL out of the real queued mailer delivery, drives Capybara through `/setup/<signed_id>` filling first/last/phone, lands on Step 2 of 4, and asserts the same `fallback_emails_for` call now includes Alex. A FlowEvent audit-trail assertion confirms `contact.verified` landed atomically.

Why this design: the FEAT-001 full-loop system spec already exercises mailbox → setup email → identity → method picker → done as the GM's primary-CC path. This spec focuses on the unique value-add of AC-INTEGRATION-1: proving the gating *consequence* — same cascade call, same data, different verification state, different outcome. Synthesizing the parallel `marketing_budget` responsibility was the cleanest way to put Alex in a fallback chain without re-driving an unrelated inbound email; the mailbox-driven primary-CC path is still exercised at the top of the spec so "mailbox creates unverified Contact" stays in the integration surface.

Using `EscalationCascade.send(:fallback_emails_for, ...)` to call the private method is a deliberate test-only peek — the AC explicitly names that method as the assertion target, and driving the cascade all the way to `fallback_fanout` or `gm_nudge` to read the recipient/payload would require seeding multiple FlowEvent rows just to set up cascade rung state. Direct peek is cleaner and the contract being checked is exactly what the AC describes.

**Build & Quality**: **445 examples, 0 failures** (1 added in this phase). `rubyfmt --check` exits 0 globally.

**TASK-009 status: BUILD_COMPLETE. All 4 phases (0, 1, 2, 3) shipped on `feature/FEAT-006-self-verification-fe`. Ready for `/rai-reflect`.**



---

## Task Archive: TASK-010

**Task**: Separate deliverable from question prompt in QUESTIONS catalog
**Status**: ARCHIVED
**Date**: 2026-05-12
**Archive**: `memory-bank/archive/archive-TASK-010.md`

---
