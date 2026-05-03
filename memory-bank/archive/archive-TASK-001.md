# Archive: TASK-001 — Tenant + GM Email-First Onboarding

## Metadata

- **Task ID**: TASK-001
- **Roadmap Link**: FEAT-001
- **Complexity**: Level 4 (enterprise / architectural)
- **Started**: 2026-05-03
- **Completed**: 2026-05-03 (compressed multi-phase build session)
- **Final state**: 307 RSpec examples / 0 failures / 0 RuboCop offenses on `feature/FEAT-001-tenant-gm-email-onboarding`
- **Phase commits**: `60f83f6` (P1) → `acf56c0` (P2) → `edb06de` (P3) → `6a3e395` (P4) → `94623f2` (P5) → `241a73e` (P6) → `576fc25` (reflection)
- **Carry-forward**: FEAT-Ops-Cutover (production email ingress + outbound provider + S3 raw-payload archive)

## Executive Summary

TASK-001 delivered the foundational email-first onboarding loop for a new dealer rooftop on Rogue. Rogue staff seed a `Tenant` via an admin form (basic-auth gated, three fields). The GM single-clicks a magic-link to confirm. The system then drives a paced sequence of one-question-at-a-time emails through Action Mailbox / parser / vendor-inference / setup-walkthrough / weekly-digest. The architecture honors the productBrief's "email is the entire UI" thesis — every interactive surface is an email reply or a magic link, with web pages serving only as confirmations or read-only summaries.

The build closed all 20 specified acceptance criteria across six phases (AC-ENTRY-1..4, AC-HAPPY-1..8, AC-ERROR-1..5, AC-ASYNC-1..3, AC-NAV-1..2). The data substrate (12 ActiveRecord models, 12 migrations) is shaped to support every subsequent feature in the roadmap (FEAT-002 lead ingestion, FEAT-003 dashboard, FEAT-004 escalations) without schema rework.

The single most notable run-time event was a Phase 4 mid-build crash: all source files had been written but were uncommitted, and the orchestrator's `Execution State` was stale. The recovery path validated the working pattern — file-first, commit-last, idempotent service classes, RSpec as ground truth — and produced a clean Phase 4 commit with zero rework.

## System Overview

### Purpose

The system implements the productBrief's central bet: dealer GMs are saturated with apps but fluent in email, so the entire onboarding flow is email-driven. A GM never logs in; they just answer questions in their inbox. The platform behind the inbox infers vendors, creates accountability records, dispatches setup links to named contacts, and produces weekly accountability digests.

### Scope (Delivered)

- **Rogue staff seed surface** — `/admin/tenants/new` with three fields (dealership name, GM name, GM email) and HTTP basic auth.
- **GM single-click confirm** — magic-link at `/onboarding/confirmations/:signed_id`, 72-hour expiry, idempotent on second click. Resend-link form with anti-enumeration + per-email rate limit.
- **Paced one-question-at-a-time emails** — first question fires after a humanizing delay (per `Tenant.first_question_delay_minutes`) bumped to the next business-hours window; subsequent questions paced via the J3 adaptive ladder (12h / 24h / 48h / silence ≥72h).
- **Inbound reply parsing** — Action Mailbox routes `onboarding+<token>@inbound.rogue.example` (with bare `onboarding@` fallback for plus-stripping mail filters) to `OnboardingMailbox`. The pure-service `OnboardingReplyParser` returns a typed `ParsedReply` value object across five intents (`assign` / `self_assign` / `skip` / `unparseable` / `clarification_response`) and across mail-client variation (Gmail, Outlook desktop / web / iOS, Apple Mail, mobile clients).
- **Vendor inference** — `VendorInferenceService` classifies an email domain as `:internal_staff` / `:vendor_user` / `:unknown`. Unknown domains trigger a clarification round-trip (`internal` / `vendor: <Name>`); a `vendor: <Name>` reply bootstraps a new `Vendor` row in `pending_review` state.
- **In-thread acknowledgments** — `OnboardingMailer#in_thread_ack` (with `In-Reply-To` and `References` headers via the `Threadable` mailer concern), `gm_only_thread_notice` (when a non-GM emails the thread), and `vendor_clarification` (for unknown domains).
- **Invitee setup walkthrough** — `Setup::WalkthroughsController` at `/setup/:signed_id` with three steps (`summary` → `method picker` → `done`). Resumable via `?step=` query and Source-state short-circuit. Submission method picker offers `form` / `csv` / `api_post`; only `form` is fully wired at MVP (CSV/API adapter generation lands in FEAT-002).
- **Request and SubmissionPrompt provisioning** — On assignment, `OnboardingFlow::RequestProvisioning` reads catalog metric definitions and creates one `Request` per metric on the Source. On walkthrough completion, `OnboardingFlow::SubmissionPromptScheduler` schedules the first `SubmissionPrompt` at the start of the next reporting period in the tenant's time zone.
- **Weekly accountability digest** — `AccountabilityMailer#weekly_digest` ships every Monday at 9am via `WeeklyDigestJob` (Solid Queue, declared in `config/recurring.yml`). Idempotency via `WeeklyDigestDelivery` unique on `(tenant_id, week_starting)`. Always sends — empty-state copy ("No submissions yet — we'll keep this digest going every week so nothing slips") for tenants without responsibilities.
- **Magic-link dashboard placeholder** — `DashboardsController#show` at `/dashboard/:signed_id`, 8-day expiry, read-only summary using the same `DigestAssembler` data as the email.
- **Audit trail** — Every state transition writes a `FlowEvent` row in the same transaction as the domain mutation. Ten event_types defined: `tenant.confirmed`, `tenant.confirmation_resent`, `question.sent`, `reply.parsed`, `responsibility.created`, `question.skipped`, `question.revisited`, `reply.unparseable`, `reply.rejected_non_gm_sender`, `vendor.clarification_requested`, `vendor.bootstrap_from_clarification`, `source.configured`, `digest.sent`.

### Scope (Out)

Per productBrief Out-of-Scope and the task plan, the following are explicitly NOT in TASK-001:
- Sales / Service question catalogs (only marketing populated; sales/service are catalog versions to come).
- AI-assisted adapter generation for `csv` / `api_post` submission methods (the walkthrough captures the choice but does not generate adapters yet — FEAT-002).
- ADF-XML and HTTP POST lead ingestion (FEAT-002).
- Recurring submission prompt sender + magic-link prompt UI (FEAT-002+ — this task schedules the prompts; sender ships later).
- Graduated escalation cascade (framework hooks live on `Request`; the escalation engine is a follow-up).
- Dealer Group creation/assignment (out-of-band Rogue staff process).
- BYOK / per-tenant encryption keys (single platform-wide key per productBrief).
- Tenant co-approval for vendor-authored adapters.
- Password + 2FA flows (magic-link only at MVP).
- **Production inbound provider, outbound provider, S3 raw-payload archive** — carried forward to FEAT-Ops-Cutover.

### Key Capabilities

- One-screen Rogue ops surface for new dealer onboarding.
- Email-only GM experience after the initial single-click confirm.
- Multi-mail-client robustness (parser tested against 5+ header layouts × 4 intents).
- End-to-end idempotency at every external entry point (HTTP / inbound email / scheduled job).
- Per-purpose magic-link tokens with appropriate expiries (`gm_confirm` 72h, `invitee_setup` 7d, `dashboard_drilldown` 8d).
- Atomic audit trail (FlowEvent + raw `ActionMailbox::InboundEmail` retention).
- Recurring weekly digest with hard-constraint idempotency.

## Architecture

### Overview

The system is a Rails 8 application built around three pillars:

1. **The data substrate** (Phase 1): 12 ActiveRecord models — `Tenant`, `Vendor`, `Contact`, `TenantQuestion`, `Responsibility`, `Source`, `Request`, `SubmissionPrompt`, `SkippedQuestion`, `FlowEvent`, `WeeklyDigestDelivery`, plus `Current` (ActiveSupport::CurrentAttributes). Question Catalog is a hybrid: code-defined templates (`Rogue::QuestionCatalog::Marketing::V1`) materialize as DB rows on first confirm.
2. **The email pipeline**: Outbound via `OnboardingMailer` / `AccountabilityMailer` with the `Threadable` concern setting `In-Reply-To`, `References`, and per-tenant onboarding addresses (`onboarding+<token>@inbound.rogue.example`). Inbound via Action Mailbox routing → `OnboardingMailbox` thin dispatcher → pure-service `OnboardingReplyParser` (CcOrdering / BodyExtractor / SkipDetector / ThreadResolver submodules) → `VendorInferenceService` → domain mutation + `FlowEvent` emit + outbound ack.
3. **The accountability layer**: `WeeklyDigestJob` (recurring, idempotent on `(tenant_id, week_starting)`) → `AccountabilityMailer#weekly_digest` → `Accountability::DigestAssembler` (pure value-object service) producing `Digest`/`Row` Structs that the email and dashboard share.

### Component Map

```
                                  ┌─────────────────────────────────┐
                                  │        Rogue Ops Staff          │
                                  │  /admin/tenants/new (basic auth)│
                                  └────────────┬────────────────────┘
                                               │
                                               ▼
                              ┌────────────────────────────────────┐
                              │ Admin::TenantsController           │
                              │  → Tenant::Seeder                  │
                              │  → OnboardingMailer.confirmation_  │
                              │     email.deliver_later            │
                              └────────────┬───────────────────────┘
                                           │
                                           ▼
                                ┌─────────────────────┐
                                │   GM's Inbox        │
                                │  (single CTA →      │
                                │   /onboarding/      │
                                │   confirmations/    │
                                │   :signed_id)       │
                                └──────────┬──────────┘
                                           │
                                           ▼
              ┌────────────────────────────────────────────────────────┐
              │ Onboarding::ConfirmationsController#show               │
              │  → Tenant#confirm! (idempotent)                        │
              │    → QuestionCatalog::Marketing::V1.materialize_for    │
              │  → FlowEvent.record!                                   │
              │  → OnboardingFlow::EnqueueFirstQuestionJob             │
              │    → next_business_window envelope                     │
              │    → OnboardingMailer.question_email                   │
              └────────────┬───────────────────────────────────────────┘
                           │ (paced via AdaptivePacing on subsequent)
                           ▼
              ┌────────────────────────────────────────────────────────┐
              │ GM replies / CCs the responsible party                 │
              │  → onboarding+<token>@inbound.rogue.example            │
              └────────────┬───────────────────────────────────────────┘
                           │
                           ▼
   ┌──────────────────────────────────────────────────────────────────────────┐
   │ ApplicationMailbox routing  → OnboardingMailbox                          │
   │   resolve_tenant (plus-token + In-Reply-To/References fallback)          │
   │   verify_gm_sender (gm_only_thread_notice on mismatch + bounced!)        │
   │   ┌──────────────────────────────────────────────────────────┐           │
   │   │ OnboardingReplyParser.call → ParsedReply value object    │           │
   │   │   CcOrdering · BodyExtractor · SkipDetector · ThreadRes  │           │
   │   │   intent ∈ {assign, self_assign, skip, unparseable,      │           │
   │   │              clarification_response}                     │           │
   │   └──────────────────────────────────────────────────────────┘           │
   │   ┌──────────────────────────────────────────────────────────┐           │
   │   │ VendorInferenceService.call → Result                     │           │
   │   │   :internal_staff | :vendor_user | :unknown              │           │
   │   └──────────────────────────────────────────────────────────┘           │
   │                                                                          │
   │   handle_assignment / handle_skip / handle_clarification /               │
   │   handle_unparseable / handle_unknown_vendor                             │
   │     → Responsibility / Source / Request creation                         │
   │     → FlowEvent.record!                                                  │
   │     → OnboardingMailer.in_thread_ack / vendor_clarification              │
   │     → OnboardingMailer.invitee_setup_email (assign only)                 │
   │     → OnboardingFlow::EnqueueNextQuestionJob (AdaptivePacing wait)       │
   └──────────────────────────────────────────────────────────────────────────┘
                                                  │
                                                  ▼
              ┌────────────────────────────────────────────────────────┐
              │ Invitee's Inbox  → /setup/<contact_signed_id>          │
              │  Setup::WalkthroughsController                         │
              │   show: summary | method picker | done (?step=)        │
              │   update: Setup::Completion.call                       │
              │     → Source.configured (method, configured_at, by)    │
              │     → OnboardingFlow::RequestProvisioning              │
              │     → OnboardingFlow::SubmissionPromptScheduler        │
              │     → FlowEvent.record!                                │
              └────────────────────────────────────────────────────────┘

           ┌──────────────────────────────────────────────────────────┐
           │ WeeklyDigestJob  (Mondays 9am, Solid Queue recurring)    │
           │  → eligibility filter (confirmed + age ≥ 7d)             │
           │  → WeeklyDigestDelivery.create! (unique: idempotency)    │
           │  → AccountabilityMailer.weekly_digest                    │
           │    → Accountability::DigestAssembler → Digest/Rows       │
           │  → FlowEvent.record!                                     │
           └──────────────────────────────────────────────────────────┘
                                                  │
                                                  ▼
           ┌──────────────────────────────────────────────────────────┐
           │ GM clicks "Open dashboard" → /dashboard/<tenant_signed>  │
           │  DashboardsController#show (read-only; same DigestData)  │
           └──────────────────────────────────────────────────────────┘
```

### Data Flow Highlights

- **Outbound message-id determinism**. `OnboardingFlow::EnqueueFirstQuestionJob` pre-generates `<onboarding-q-{tenant_id}-{question_id}-{hex}@inbound.rogue.example>` and persists it to `tenant_questions.outbound_message_id` BEFORE delivery. Inbound `In-Reply-To` resolution then has no race against delivery completion.
- **FlowEvent atomicity**. Every domain mutation (`Responsibility.create!`, `Source.update!`, `question.update!(status: :answered)`, etc.) is wrapped in the same transaction as a `FlowEvent.record!` — the audit log is committed-or-rolled-back together with the data.
- **Idempotency synchronisation**. The unique index on `weekly_digest_deliveries.(tenant_id, week_starting)` is the cross-process synchronisation primitive for the weekly digest. `RecordNotUnique` is the no-op signal; no Redis or advisory lock is needed.
- **Tenant isolation**. Every model except canonical `Vendor` carries `tenant_id NOT NULL` with index. `Current.tenant` is set on every mailbox process and confirmation controller path.

### Integration Points

- **Action Mailbox** (Rails framework) — inbound mail ingestion, raw-payload retention, Message-ID dedup. Conductor at `/rails/conductor/action_mailbox/inbound_emails` for dev.
- **Solid Queue** (Rails 8 default) — outbound mail delivery, recurring jobs (declared in `config/recurring.yml`).
- **Letter Opener** (dev) / `:test` adapter (test) — outbound mail in non-prod environments.
- **Active Storage** — raw-payload archive for `ActionMailbox::InboundEmail`. Local-disk in dev; S3 cutover deferred to FEAT-Ops-Cutover.
- **Production inbound and outbound email providers** — deferred to FEAT-Ops-Cutover.

## Design Decisions

### A1 — Action Mailbox addressing scheme

- **Decision**: Plus-addressing on `onboarding+<token>@inbound.rogue.example`, with a bare-`onboarding@` fallback in `application_mailbox.rb` for mail filters that strip plus addressing on the way in.
- **Rationale**: Single MX record, no per-tenant DNS, fastest path to multi-tenant routing. The `<token>` is `Tenant.onboarding_token` — opaque base58, never PII-derived, never the primary key.
- **Alternatives considered**: per-tenant subdomain (`<slug>.inbound.rogue.example`) — rejected for DNS overhead at scale; dedicated MX per tenant — rejected as massively over-engineered for MVP.
- **Reference**: `memory-bank/creative/TASK-001-architecture.md`.

### A2 — Question Catalog data model

- **Decision**: Hybrid — code-defined catalog modules (`Rogue::QuestionCatalog::Marketing::V1`) materialize on first confirm into `tenant_questions` rows pinned to a `catalog_version`.
- **Rationale**: Code defines the canonical templates (versioned with the app, reviewable in PRs). DB rows let us track per-tenant per-version status without re-introducing the catalog into the runtime path.
- **Alternatives considered**: pure DB-backed (with admin) — rejected for catalog-evolution friction (every catalog change is a deploy + seed); pure code-defined module — rejected because per-tenant per-question state has nowhere to live.
- **Reference**: `memory-bank/creative/TASK-001-architecture.md`.

### A3 — Vendor roster strategy

- **Decision**: Curated CSV seed (~200 entries at first cut; 20 in v0) loaded by `Rogue::Seeds::VendorsLoader.load_csv`, with auto-promotion of `pending_review` vendors after manual review.
- **Rationale**: Avoids the bootstrap-from-inbound-replies problem (vendors in the database before any GM ever replies) while leaving an explicit creation path for unknown domains via the `vendor: <Name>` clarification flow.
- **Alternatives considered**: scrape from a known industry resource — rejected for licensing and currency concerns; bootstrap-from-replies only — rejected because it fails the first-time UX (every GM gets a clarification email).
- **Reference**: `memory-bank/creative/TASK-001-architecture.md`.

### A4 — Audit-event/lineage shape

- **Decision**: Single `flow_events` table — outbox-style event log keyed on `(tenant, event_type, occurred_at)`, with `subject_*` polymorphic reference and `payload` JSONB for context.
- **Rationale**: One write path is easy to reason about; cross-event queries ("everything that happened to this tenant" / "every parser exception in the last hour") are one SQL filter. Putting the event write inside the same transaction as the domain mutation gives atomicity for free.
- **Alternatives considered**: per-domain audit tables — rejected for query overhead; structured logs only — rejected because logs are operational, not durable.
- **Reference**: `memory-bank/creative/TASK-001-architecture.md`.

### J1 — Tenant seed surface

- **Decision**: Rails admin controller (`Admin::TenantsController#new`) gated by HTTP basic auth (env-driven creds), with a parallel rake task (`bin/rails rogue:tenants:seed`) for scripted scenarios.
- **Rationale**: Real URL Rogue ops can navigate to without shell access; basic auth is a defensible MVP gate; rake task is the testing/CI path.
- **Reference**: `memory-bank/creative/TASK-001-user-journey.md`.

### J2 — First-question delivery delay

- **Decision**: ~1 hour after confirm (configurable per tenant via `Tenant.first_question_delay_minutes`), bumped to the next business-hours window (Mon-Fri 9:30am-6pm in tenant TZ).
- **Rationale**: Humanizing pause; immediate-fire feels robotic. Business-hours envelope avoids 3am-Saturday delivery on a confirm that happened Friday at 11pm.
- **Reference**: `memory-bank/creative/TASK-001-user-journey.md`.

### J3 — Adaptive question pacing

- **Decision**: Reply within 1h → next question in 12h; within 24h → 24h; within 72h → 48h; silence ≥72h → no next question scheduled (recover via the GM's next reply or an explicit re-engagement flow). Implemented in `OnboardingFlow::AdaptivePacing`.
- **Rationale**: Mirrors the GM's engagement signal — when they reply quickly, they're in the headspace and we can cadence faster; when they go quiet, we don't pile on.
- **Reference**: `memory-bank/creative/TASK-001-user-journey.md`.

### J4 — Empty-state digest

- **Decision**: Always send. Empty-state copy ("No submissions yet — we'll keep this digest going every week so nothing slips") preserves the cadence so the digest doesn't disappear during the silent ramp-up.
- **Rationale**: Habit formation; predictable cadence is more valuable than not-sending-when-empty.
- **Reference**: `memory-bank/creative/TASK-001-user-journey.md`.

### J5 — Resend-link UX

- **Decision**: Self-serve resend at `/onboarding/confirmations/resend` with anti-enumeration (always renders the same success page) and a per-email rate limit (3/hour, Solid Cache backed).
- **Rationale**: Anti-enumeration prevents the resend form from being a confirmation oracle for "is this email a Rogue tenant?" The rate limit prevents the form from being an outbound spam vector.
- **Reference**: `memory-bank/creative/TASK-001-user-journey.md`.

### L1 — Reply parser algorithm

- **Decision**: `EmailReplyTrimmer` for quote stripping, Nokogiri for HTML quote-block removal (`.gmail_quote`, `.OutlookMessageHeader`, `blockquote`, `[type='cite']`, `divRplyFwdMsg`), custom regex for trailing signatures (`^-- $`, "Sent from my iPhone", etc.). CC ordering trusts wire order with a `:cc_order_uncertain` warning when known re-orderers (Outlook Web, Outlook iOS) are detected via User-Agent / X-Mailer. Skip detection is a deterministic single-token-on-its-own-line regex applied AFTER quote/signature stripping.
- **Rationale**: Composable submodules (`CcOrdering`, `BodyExtractor`, `SkipDetector`, `ThreadResolver`) each testable in isolation. Pure functions on Mail::Message; no DB, no callbacks.
- **Reference**: `memory-bank/creative/TASK-001-algorithm.md`.

### L2 — In-thread threading discipline

- **Decision**: `Threadable` mailer concern provides `onboarding_address(tenant)`, `canonical_subject(tenant, topic, reply: false)`, and `thread_with(parent_message_id)`. Outbound replies set `In-Reply-To` and `References` headers; subjects follow `[<Dealership> Onboarding] <topic>` with optional `Re: ` prefix. Pre-generated outbound Message-IDs are stored on `tenant_questions.outbound_message_id` so inbound `In-Reply-To` resolution is deterministic.
- **Rationale**: Threading is a major UX concern in email clients. Setting headers correctly + persisting the outbound Message-ID makes the inbound side trivially resolvable.
- **Reference**: `memory-bank/creative/TASK-001-algorithm.md`.

## Implementation

### Phases

| Phase | Outcome | Specs cumulative |
|-------|---------|------------------|
| 1 — Foundation | 11 migrations, 11 models + `Current`, Question Catalog V1, vendor seed CSV + loader, 9 factories, 7 spec files | 89 |
| 2 — Tenant seed + GM confirm | `Admin::BaseController` + `TenantsController`, `Onboarding::ConfirmationsController` (with resend + anti-enumeration + rate limit), `OnboardingMailer#confirmation_email`, all views, rake task | 147 (+58) |
| 3 — First question email | `Threadable` concern, `OnboardingMailer#question_email` with explicit Message-ID, `OnboardingFlow::Scheduling` business-hours envelope, `EnqueueFirstQuestionJob` + `EnqueueNextQuestionJob`, `Tenant#confirm!` wires `materialize_for` | 185 (+38) |
| 4 — Inbound reply pipeline | `ApplicationMailbox` routing, `OnboardingMailbox` dispatcher, `OnboardingReplyParser` with four submodules, `VendorInferenceService`, `OnboardingFlow::AdaptivePacing`, three new mailer actions (`in_thread_ack` / `gm_only_thread_notice` / `vendor_clarification`) + html/text views | 242 (+57) |
| 5 — Invitee setup walkthrough | `OnboardingMailer#invitee_setup_email`, `Setup::WalkthroughsController`, `Setup::Completion` service, `OnboardingFlow::RequestProvisioning`, `OnboardingFlow::SubmissionPromptScheduler`, `Contact#invitee_setup_signed_id` helpers, `metrics_for` on the catalog | 279 (+37) |
| 6 — Weekly digest + dashboard placeholder | `AccountabilityMailer#weekly_digest`, `Accountability::DigestAssembler`, `WeeklyDigestJob` (recurring), `WeeklyDigestDelivery` model + migration, `Tenant#dashboard_signed_id`, `DashboardsController#show`, `config/recurring.yml` schedule | 307 (+28) |

### Key Components

- **Models**: `Tenant`, `Vendor`, `Contact`, `TenantQuestion`, `Responsibility`, `Source`, `Request`, `SubmissionPrompt`, `SkippedQuestion`, `FlowEvent`, `WeeklyDigestDelivery`, plus `Current` (CurrentAttributes).
- **Controllers**: `Admin::BaseController`, `Admin::TenantsController`, `Onboarding::ConfirmationsController`, `Setup::WalkthroughsController`, `DashboardsController`.
- **Mailers**: `OnboardingMailer` (six actions), `AccountabilityMailer` (one action). Mailer concern: `Threadable`. Mailer helper: `OnboardingMailerHelper`.
- **Mailbox**: `OnboardingMailbox` (thin dispatcher).
- **Services**: `OnboardingReplyParser` (with four nested submodules), `VendorInferenceService`, `OnboardingFlow::Scheduling`, `OnboardingFlow::AdaptivePacing`, `OnboardingFlow::RequestProvisioning`, `OnboardingFlow::SubmissionPromptScheduler`, `Setup::Completion`, `Accountability::DigestAssembler`, `Tenant::Seeder`.
- **Jobs**: `OnboardingFlow::EnqueueFirstQuestionJob`, `OnboardingFlow::EnqueueNextQuestionJob`, `WeeklyDigestJob`.
- **Library**: `Rogue::QuestionCatalog::Marketing::V1`, `Rogue::Seeds::VendorsLoader`.
- **Configuration**: `config/recurring.yml` (WeeklyDigestJob Mondays 9am + Solid Queue cleanup).

### Technical Specifications

- **Token security**. Per-purpose `signed_id`s: `:gm_confirm` (72h, single-use via state check), `:invitee_setup` (7d, reusable until expiry), `:dashboard_drilldown` (8d so the next digest's link supersedes by 1 day).
- **Encryption**. `Tenant.gm_email` and `Contact.email` use `encrypts ..., deterministic: true` (single platform key per productBrief OOS — BYOK deferred).
- **Tenant isolation**. Every non-canonical model carries `tenant_id NOT NULL` with index. `Current.tenant` is set on every mailbox/controller entry.
- **Idempotency anchors**. `Action Mailbox` Message-ID dedup (native), `Vendor.bootstrap!` (find_or_initialize by name), `Contact.find_or_create_for_email`, `RequestProvisioning.find_or_create_by!(source, metric_key)`, `SubmissionPromptScheduler.find_or_create_by!(tenant, request, status: :pending)`, `WeeklyDigestDelivery` unique on `(tenant_id, week_starting)`.
- **Time-zone discipline**. All scheduling in tenant-local TZ (`tenant.time_zone`, default `America/New_York`). `OnboardingFlow::Scheduling.next_business_window` (Mon-Fri 9:30am-6pm tenant-local). `OnboardingFlow::SubmissionPromptScheduler` constructs next-period dates via `now.time_zone.local(...)` (lesson from a Phase 6 quarterly-bug fix — see Lessons Learned).

## Testing

### Strategy

- **Test framework**: RSpec + FactoryBot + shoulda-matchers + Capybara. Resolved 2026-05-03 in Phase 1. Lint: RuboCop.
- **Distribution**: heavy on service-class unit tests (parser, vendor inference, scheduler — pure functions, deterministic, high test value), system / request specs for inbound and HTTP surfaces (Action Mailbox round-trips and Capybara walkthroughs are the only way to verify the email-first user journey end to end), mailer specs for every outbound message asserting subject / headers / body / plain-text alt.

### Results

| Test Type | Count | Pass Rate |
|-----------|-------|-----------|
| Model | ~40 | 100% |
| Service | ~110 | 100% |
| Mailer | ~40 | 100% |
| Mailbox | ~10 | 100% |
| Job | ~15 | 100% |
| Request | ~50 | 100% |
| Lib (catalog) | ~15 | 100% |
| System (Capybara) | ~5 | 100% |
| Other | ~22 | 100% |
| **Total** | **307** | **100%** |

(Counts approximate; actual breakdown is in `.claude-logs/rspec-phase6-green-2.log`.)

### Coverage

- Coverage by component (qualitative):
  - **Parser**: heaviest unit test target — 28 branches across 5+ mail-client header layouts × 4 intents + edge cases (attachments, raw_excerpt cap, signature stripping, quote-block false-positive guards, plain-vs-HTML divergence warning, clock-skew handling).
  - **Vendor inference**: 3 classification branches × case-insensitivity + archived-vendor exclusion = 5 branches.
  - **Mailbox dispatcher**: routing + per-intent integration tests covering AC-HAPPY-3/4/5/6, AC-ERROR-2/3/4, AC-NAV-1, plus Message-ID idempotency.
  - **Adaptive pacing**: 4 ladder tiers + clock-skew clamp + nil-sent-at default.
  - **SubmissionPrompt scheduler**: monthly / quarterly / idempotent / multi-Request.
  - **Walkthrough**: GET (3 step branches + expired) + PATCH (success / parked-state / invalid / expired).
  - **Weekly digest job**: eligibility filter + idempotency on re-run + empty-state delivery.

### What was NOT tested (intentionally)

- Action Mailbox internal routing logic (covered by Rails framework).
- `signed_id` cryptography (covered by Rails). We test our purpose-scoping, expiry, and single-use semantics.
- Postgres uniqueness constraint enforcement (covered by Rails). We test our model validations and that migrations declare the right constraints.
- Letter Opener delivery mechanics (covered by the gem). We test that mailers enqueue with the correct subject, headers, body.
- Stimulus / Turbo behavior at MVP (no JS surface). We assert rendered HTML.
- Solid Queue worker plumbing (covered by Rails 8). We test that jobs enqueue with the right args / wait / queue and perform their work correctly when run inline.

## Deployment

### Procedures (current state — local dev only)

- **Migrations**: 12 migrations under `db/migrate/`, including Action Mailbox install (`bin/rails action_mailbox:install` + `db:migrate`). All applied via standard `bin/rails db:migrate`.
- **Configuration**: `Rails.application.credentials.inbound_email_domain` overrides the default `inbound.rogue.example` (used by the `Threadable` concern and `OnboardingFlow::EnqueueFirstQuestionJob`'s Message-ID generator). `ROGUE_ADMIN_USERNAME` / `ROGUE_ADMIN_PASSWORD` env vars gate `/admin/*` routes.
- **Outbound mail**: `:letter_opener` in dev, `:test` in test. Production provider deferred to FEAT-Ops-Cutover.
- **Inbound mail**: Action Mailbox conductor at `/rails/conductor/action_mailbox/inbound_emails` for dev. Production ingress provider deferred to FEAT-Ops-Cutover.
- **Recurring jobs**: `config/recurring.yml` schedules `WeeklyDigestJob` Mondays 9am in production. Other environments enqueue manually if needed.
- **Active Storage**: local-disk in dev. S3 cutover deferred to FEAT-Ops-Cutover.

### Production deployment readiness

**Not deployment-ready**. The following must complete before real-GM dogfood:

1. Inbound provider (Postmark / Mailgun / SendGrid) chosen, MX configured, webhook wired.
2. Outbound provider chosen, IP/domain warmed up, threading verified in real Gmail / Outlook / Apple Mail.
3. Active Storage flipped to S3 (or chosen storage class) with retention policy applied.

All three are tracked in **FEAT-Ops-Cutover** (added to the roadmap in this archive).

### Rollback

- **Schema**: each migration has a `change` block that supports `db:rollback`. Reversible.
- **Feature flags**: none — the feature is a single foundational unit. Rollback strategy is `git revert` of the relevant phase commit (or the whole feature merge commit) followed by `db:rollback`.
- **Data**: `tenants`, `tenant_questions`, etc. carry no destructive operations on rollback. `flow_events` and `action_mailbox_inbound_emails` retain history.

## Maintenance

### Monitoring

(All deferred to FEAT-Ops-Cutover and beyond. Ground rules from CLAUDE.md observability standards apply once cutover lands: structured JSON logs, OpenTelemetry traces, log levels via env, no `console.log` / `puts` in prod paths.)

Key things to monitor at cutover:
- **Inbound parse success rate** — `flow_events.event_type='reply.parsed'` with `payload->>'confidence' = 'low'` is the diagnostic for parser drift.
- **Vendor clarification rate** — `flow_events.event_type='vendor.clarification_requested'` should trend toward zero as the seed roster matures.
- **Digest delivery cadence** — `weekly_digest_deliveries` row count per week should equal eligible-tenant count.
- **GM silence** — `tenants.in_onboarding_silence(threshold: 7.days)` is the re-engagement queue (no recurring job dispatches against it yet — that's a follow-up).

### Common Issues (anticipated)

| Issue | Resolution |
|-------|------------|
| GM reply not parsed (intent: unparseable) | Inspect `ActionMailbox::InboundEmail` raw RFC 822 source. Check `flow_events.event_type='reply.unparseable'` payload warnings. Common causes: HTML-only mail clients with non-standard quote markup; mail-client signature variants not yet covered. |
| Vendor clarification email goes out for a domain that should be internal | Check `tenants.gm_email_normalized` matches the domain — the inference is `email_domain == gm_domain`. If GM email and contact email are the same domain but the contact is unknown, that's a bug. |
| Question email lands outside business hours | `OnboardingFlow::Scheduling.next_business_window` evaluates with `tenant.time_zone`. Verify the tenant's `time_zone` column is set correctly (default `America/New_York`). |
| Digest sends twice in one week | Check `weekly_digest_deliveries.(tenant_id, week_starting)` — the unique constraint should prevent this. If it happened, it's a bug in `WeeklyDigestJob#send_digest_for` (the marker insert should be the synchronisation point). |
| Magic-link expired view appears on a fresh link | Check the link's purpose-scoping (`gm_confirm` / `invitee_setup` / `dashboard_drilldown`) — purposes are not interchangeable. Check the expiry param matches the controller's finder expectations. |

### Operational Procedures

- **Adding a new vendor**: edit `db/seeds/vendors.csv` and re-run `Rogue::Seeds::VendorsLoader.load_csv`. `Vendor.bootstrap!` is idempotent on `name`. For runtime additions via the clarification flow, `vendor: <Name>` replies create `pending_review` rows that staff promote to `active`.
- **Adding a new question to the marketing catalog**: bump the catalog version (e.g., `Rogue::QuestionCatalog::Marketing::V2`), copy + extend `QUESTIONS`, and update the `Tenant.question_catalog_version` default. New tenants get the new catalog; existing tenants need an explicit `materialize_for` re-run if they should pick up the additions (rolling-onboarding question — see productBrief Open Question 1).
- **Adding a new domain (sales / service)**: extend the `domain` enum on `tenant_questions` and `sources`, add a new `Rogue::QuestionCatalog::Sales::V1` module, decide pacing.
- **Manually retrying a failed parse**: re-route the `ActionMailbox::InboundEmail` via the conductor.
- **Manually triggering a digest**: `WeeklyDigestJob.perform_now` (after deleting the relevant `WeeklyDigestDelivery` row if testing same-week behavior).

## Lessons Learned

Reference: `memory-bank/reflection/reflection-TASK-001.md`. Highlights:

- **The recoverable-build cadence works.** Spec → implement → lint → memory-bank → commit. Working tree is the source of truth; `Execution State` is supplementary. The Phase 4 mid-build crash recovered cleanly because there was no half-commit to reconcile.
- **Pure value-object services scale.** Mailbox / Mailer / Job / Controller layers stay thin and dispatch on Struct values; specs cover the values, not I/O.
- **Idempotency-by-default removes whole bug classes.** Every external entry point uses `find_or_create_by!` or a unique constraint as the synchronisation point.
- **Don't construct timestamps from `Time.zone` in tenant-scoped code.** Derive zone from the tenant. (Phase 6 quarterly-scheduler bug.)
- **System tests for inbound flows should assert every downstream artifact.** Phase 4's AC-HAPPY-3 spec didn't check Request creation; Phase 5 surfaced the gap.
- **`Source has_many :responsibilities` is currently a phantom association.** Tracked as a high-priority cleanup item.

Four learnings were extracted into `memory-bank/agent-rules/_learned/`: `idempotency.md`, `time-zones.md`, `service-shape.md`, `audit-trail.md`.

## References

- **Reflection**: `memory-bank/reflection/reflection-TASK-001.md`
- **Architecture decisions**: `memory-bank/creative/TASK-001-architecture.md` (A1-A4)
- **User-journey decisions**: `memory-bank/creative/TASK-001-user-journey.md` (J1-J5)
- **Algorithm decisions**: `memory-bank/creative/TASK-001-algorithm.md` (L1-L2)
- **Plan + roadmap**: `memory-bank/tasks/TASK-001.md`
- **Build phase log**: `memory-bank/progress.md`
- **Roadmap entry**: `memory-bank/roadmap.md` → FEAT-001
- **Carry-forward**: `memory-bank/roadmap.md` → FEAT-Ops-Cutover
- **Phase commits**: `60f83f6` (P1), `acf56c0` (P2), `edb06de` (P3), `6a3e395` (P4), `94623f2` (P5), `241a73e` (P6), `576fc25` (reflection)

## Future Considerations

### Carry-forward (in flight)

- **FEAT-Ops-Cutover** — the three operational-cutover items deferred from this task's Live-Dogfood-Pending Tracker. Pending QA / production environment availability.

### Action items (from the reflection)

**High priority**
- Replace phantom `Source has_many :responsibilities` with a real `source_id` FK on `responsibilities` (or remove the association declaration).
- Add `spec/system/gm_email_first_onboarding_full_loop_spec.rb` as the end-to-end integration gate (was named in the test plan but didn't ship).

**Medium priority**
- Per-(Contact, Responsibility) signed token for setup walkthroughs so multi-assignment contacts get distinct setup URLs.
- Delete unused `Tenant#next_question_cadence_gap`; route everything through `OnboardingFlow::AdaptivePacing` to avoid duplicated J3 ladder logic.
- Document recurring-job test/dev-environment behavior in `techContext.md` (currently only declared for production).

**Low priority**
- Custom RuboCop cop banning `Time.zone.local` inside tenant-scoped code (would have prevented the quarterly-scheduler bug).
- Generic shared example for `has_many` association FK resolution (would have caught the `Source has_many :responsibilities` phantom).

### Strategic platform considerations

- The `OnboardingFlow::AdaptivePacing` ladder + business-hours envelope is the pattern every paced communication will use. Generalize when FEAT-002 lands its prompt sender.
- The `flow_events` audit table is the foundation for an eventual real-time accountability dashboard. The current `DashboardsController` is the read-only stub.
- The vendor seed + clarification round-trip is the model for any "canonical-thing-with-occasional-runtime-additions" pattern. Likely reusable for OEM compliance, integration partners, and similar.
