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
