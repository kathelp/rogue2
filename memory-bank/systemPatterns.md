# System Patterns

> Initial baseline for the Rogue project — to be refined as patterns emerge from implementation.
> Sub-agents should treat the **Guiding Principles** below as load-bearing; deviations require explicit justification in the planning phase.

## Guiding Principles

These are the non-negotiables. Any plan or implementation that conflicts with one of these must call it out explicitly with reasoning.

1. **Email is a first-class interaction surface.** GM onboarding and ongoing accountability happen primarily over email. Action Mailbox is platform infrastructure, not a peripheral feature. Web UI exists for those who want it but is never the only path for primary personas (GMs, submitters).

2. **Single accountability with named fallbacks.** Every responsibility has exactly one primary accountable party plus an ordered list of fallbacks. The data model and UX both reflect this — never fan out responsibility to "the team" by default.

3. **Raw payload retention is the source of truth.** Every inbound message (ADF-XML, CSV, JSON POST, form submission, GM email reply) is stored verbatim with no expiration before any processing happens. Normalized canonical records carry a back-reference to the raw payload and the adapter version that produced them. This makes adapter mistakes recoverable by replay rather than data loss.

4. **Schema versioning is opt-in per adapter.** Domain canonical schemas are versioned from day one. Adapters pin to a specific schema version. No schema version is retired while any active adapter targets it. This blocks the "we changed the schema, now everything's broken" failure mode.

5. **Tenant isolation is structural, not advisory.** Every domain model that holds tenant data carries `tenant_id` and is queried through tenant-scoped associations. Cross-tenant queries (group rollups, vendor multi-rooftop views) go through explicit Group/Vendor membership checks, not bare scope leaks.

6. **AI-generated artifacts have a named human approver.** Adapters generated from sample payloads must have a human approver recorded; that human is accountable for the data the adapter produces. AI is a productivity layer, not an accountability layer.

7. **Idempotent inbound handling.** Inbound email and HTTP POST handlers archive the raw payload first, then process. Re-delivery of the same payload (Message-ID match for email, idempotency key for HTTP) does not double-process.

## Architecture Patterns

### Rails Monolith (MVP)
- Single Rails 8.1 application, single Postgres 18 database for primary domain (production splits into primary + cache + queue + cable databases per Solid stack convention).
- No service decomposition at MVP. Re-evaluate after first scale event.

### Inbound Email Routing
- **Action Mailbox** dispatches inbound emails based on the `To:` address (regex routing in `application_mailbox.rb`).
- **Two address namespaces**, distinct prefixes/subdomains so routing is unambiguous:
  - **Onboarding threads**: per-tenant address, e.g. `onboarding+<tenant_token>@inbound.rogue.example` — replies route to the OnboardingMailbox, scoped to the tenant.
  - **Lead ingestion**: per-(tenant, source) address, e.g. `lead+<source_token>@inbound.rogue.example` — routes to the LeadIngestMailbox, scoped to the source.
- **Threading**: `In-Reply-To` and `References` headers are parsed and persisted on the InboundEmail record so the conversation graph is queryable.
- **Idempotency**: handle the same Message-ID twice → no-op. Action Mailbox provides this natively; we do not deduplicate at the application layer.

### Outbound Email
- **Action Mailer** for all outbound. One mailer per workflow surface (OnboardingMailer, AccountabilityMailer, EscalationMailer, SubmissionMailer).
- **Sent via Solid Queue** — never inline in a request handler. `deliver_later` is the default; `deliver_now` is reserved for tests.
- **Threading on outbound**: when sending a reply that should be threaded into an existing conversation, set `In-Reply-To` and `References` based on the InboundEmail being replied to. The thread carries provenance.
- **`Threadable` mailer concern** (`app/mailers/concerns/threadable.rb`) is the shared implementation. It provides `onboarding_address(tenant)` (per-tenant `From:`/`Reply-To:` resolution against `Tenant.onboarding_token`), `canonical_subject(tenant, topic, reply: false)` (subject prefix `[<Dealership> Onboarding] <topic>`), and `thread_with(parent_message_id)` (sets `In-Reply-To` + `References`). Currently included by `OnboardingMailer`, `SubmissionMailer`, and `EscalationMailer` — 9 mailer actions across the three.

### Per-Severity Mailer Templates
- When a single mailer action emits visibly different copy across severities/states, render via `<%= render partial: @severity.to_s %>` (or equivalent state slug) rather than an inline `case` block. Each severity gets its own pair of `_<severity>.html.erb` + `_<severity>.text.erb` partials. Example: `EscalationMailer#escalation_email` renders `_due_soon` / `_overdue` / `_fallback_fanout` / `_gm_nudge`. Diffs of copy changes review one partial; a growing `case` is harder to scan.
- **Mailers don't auto-load helpers** — Action Controller does, Action Mailer doesn't. Declare `helper :name` (or `helper SomeHelper`) at the top of a mailer when its views need helpers from `app/helpers/`. (Worth a custom `lib/tasks` lint if helper-less mailers grow.)

### Idempotency Strategies
Every external entry point that meets traffic the system doesn't fully control needs an explicit idempotency strategy. We use three patterns, picked by the lifecycle of the work unit:
- **Marker-table pattern** — when no natural marker exists on a domain row, insert a dedicated row first (with a unique constraint), then perform the side effect. `RecordNotUnique` is the no-op signal. Example: `WeeklyDigestDelivery` unique on `(tenant_id, week_starting)` for the weekly digest.
- **Status-column UPDATE-WHERE pattern** — when the natural marker IS the domain row, use `where(id:, status: <expected>).update_all(status: <next>, ...)` as the synchronisation point. `affected_rows == 0` means another worker already took the work. Example: `SubmissionPromptSenderJob`'s `:pending → :sent` transition.
- **Append-only event log pattern** — when the work unit is a multi-step state machine (escalation ladder, multi-stage approval), use the FlowEvent log as the source of truth. The detector reads "what's the highest-recorded step for this prompt?" and dispatches the next step, recording its own FlowEvent before the side effect. Example: `OnboardingFlow::EscalationCascade` reads `escalation.*` events; `EscalationDetectorJob` writes the next event before queueing the mailer.

### Audit Trail (FlowEvent log)
- Every domain mutation that crosses a system boundary (HTTP / inbound email / scheduled job / outbound mail) writes a `FlowEvent` row inside the same transaction. The audit log and the mutation are atomically committed-or-rolled-back together.
- 13+ event types in current use across onboarding (`tenant.confirmed`, `question.sent`, `reply.parsed`, `responsibility.created`, `question.skipped`, `question.revisited`, `reply.unparseable`, `reply.rejected_non_gm_sender`, `vendor.clarification_requested`, `vendor.bootstrap_from_clarification`), submissions (`submission.prompt_sent`, `submission.captured`, `source.configured`), digest (`digest.sent`), and escalation (`escalation.due_soon`, `escalation.overdue`, `escalation.fallback_fanout`, `escalation.gm_nudge`).
- Diagnostic queries are one filter: `FlowEvent.where(tenant: ..., event_type: ...)`. The pattern intentionally substitutes for a separate "audit service."

### Background Work
- **Solid Queue** for all asynchronous work: paced question sending, weekly accountability digests, escalation cascades, AI adapter generation, recurring submission prompts.
- **Recurring jobs** declared in `config/recurring.yml` (Rails 8 native scheduler). Examples: weekly digest, due-date scanner, overdue escalation.
- **Idempotent jobs** by default — every job assumes it may be retried after partial completion.

### Magic Links
- **Rails `signed_id`** (built into ActiveRecord) for all magic-link tokens. Scope each token by purpose (`:gm_confirm`, `:invitee_setup`, `:submission_prompt`, `:dashboard_drilldown`).
- **Short expiry** for confirm/setup tokens (24-72h); longer for recurring submission prompts (one cadence period).
- **Single-use where it matters**: confirmation tokens consumed on first click; submission/dashboard tokens are reusable until expiry.

### Tenant Scoping
- Every tenant-scoped model has a `tenant_id` foreign key with a NOT NULL constraint and an index.
- Default ActiveRecord scope is **NOT** automatically tenant-scoped (avoid the surprise-leak failure mode of `default_scope`). Instead, prefer explicit `Current.tenant`-aware queries via `Tenant.find(...).requests`.
- A `Current` attribute (ActiveSupport::CurrentAttributes) carries the tenant for the duration of a request or job.

### Encryption
- Rails 7+ `encrypts` for PII fields (customer email + phone on leads at MVP).
- Use `deterministic: true` only where exact-match queries are required (e.g., dedup by customer email).
- Single platform-wide key at MVP (per productBrief Out-of-Scope). Per-tenant keys deferred.

### Lineage
- Every normalized record has a `raw_payload_id` (FK to the InboundEmail or stored payload) and an `adapter_version_id` (FK to the AdapterVersion that produced it).
- Adapter approvers are recorded with their organization (`tenant` or `vendor`) and timestamp.

## Conventions

### Code Style
- **Rubocop omakase** (Rails 8 default). Treat the omakase config as the project standard until a deviation is justified in this file.
- Brakeman + bundler-audit run in CI (when CI exists). Until then, run before merging meaningful changes.

### Models
- One responsibility per model. Avoid god-objects (no `User` that's both Tenant Admin and Vendor Submitter and Dealer Group rep — use distinct membership models).
- Validations on persistence boundaries; database constraints on every NOT NULL / FK / unique invariant. Prefer DB-level constraints over Ruby-only checks for invariants the system depends on.

### Controllers
- Slim controllers — domain logic lives in services or in models. Controllers handle HTTP shape (params parsing, status codes, redirects) and authorization.
- Magic-link controllers verify the signed token before any state mutation.

### Mailers + Mailboxes
- Mailbox classes are thin parsers + dispatchers. The actual reply-parsing algorithm (CC order, no-CC self-assign, `skip` detection, signature stripping) lives in a service class so it can be tested without the Action Mailbox harness.
- Mailers carry no business logic — they format what's handed to them.

### Tests
- **Test framework**: **RSpec** (resolved 2026-05-03 in FEAT-001 Phase 1). The rai-build command commits to RSpec as the sole framework, so we adopted it project-wide. Test files live under `spec/` mirroring `app/`; runner is `bundle exec rspec`; lint is `bundle exec rubocop`. FactoryBot for fixtures, `shoulda-matchers` for Rails-specific matchers.
- **System tests for the email-first flow** are essential — Action Mailbox provides a `receive_inbound_email_from_*` helper for asserting end-to-end behavior. Use it.
- **Test pyramid**: unit (model + service) tests are the bulk; controller tests for routing/auth; system tests for the full GM-email-onboarding round-trip and lead-ingestion round-trip.

### Database
- Migrations are reversible. Avoid `change_column` without `up`/`down` when the change isn't trivially invertible.
- Indexes on every FK and on every column used in a `where` query in hot paths.
- `created_at` / `updated_at` on every model. `discarded_at` (soft-delete) only when an explicit reason exists; default to hard delete unless retention is a requirement.

### Naming
- Models in `PascalCase`, files in `snake_case`. Stick to Rails conventions. Resist clever abbreviations (`Tenant`, not `Tnt`).
- Action Mailbox routing tokens: opaque base58 or signed_id. Never expose primary keys in inbound email addresses.

## Open Decisions (capture here when made)

- ~~Test framework: Minitest vs RSpec~~ — **RESOLVED 2026-05-03 (FEAT-001 P1): RSpec.**
- Inbound email provider (production): Postmark vs Mailgun vs SendGrid.
- Outbound email provider: same as inbound, or split.
- SMS provider: Twilio is default unless cost or compliance pushes elsewhere.
- AI provider for adapter generation: defer until FEAT-002 (lead ingestion adapter scaffold).
