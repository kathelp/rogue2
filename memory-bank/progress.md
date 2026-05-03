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
