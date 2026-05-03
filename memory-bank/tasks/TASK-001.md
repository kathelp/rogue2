# TASK-001: Tenant + GM Email-First Onboarding

**Complexity**: Level 4
**Status**: REFLECTION_COMPLETE
**Roadmap**: FEAT-001
**Branch**: feature/FEAT-001-tenant-gm-email-onboarding
**Worktree**: N/A
**Reflection**: memory-bank/reflection/reflection-TASK-001.md
**Docs Opt-In**: no
**Docs Opt-In Reason**: No Docusaurus tree at `docs/` and feature is operational/internal-platform-foundation; revisit when first end-user-facing capability ships.
**Marketing Opt-In**: no
**Marketing Opt-In Reason**: No marketing schema at `db/seeds/marketing/` and feature is platform infrastructure (no customer-facing landing-page surface); revisit when first GA-able capability ships.

## Task Description

End-to-end email-first onboarding for a new dealer rooftop.

**Seeding** (Rogue staff): create a Tenant with three fields — dealership name, GM name, GM email. Rogue sends the GM a single-click confirmation email. This is the only manual step on Rogue's side and the only click required of the GM in the entire onboarding.

**GM self-onboarding via email**: After confirm, the GM receives a paced sequence of single-question emails — one responsibility at a time, spaced over days — phrased in business vocabulary ("Who controls your marketing strategy?", "Who manages your dealer website?"). Each email states three reply conventions explicitly:

- First CC = primary accountable party
- Subsequent CCs = fallbacks (order matters)
- No-CC reply = GM self-assigns
- Body text `skip` = defer the responsibility

Each parsed reply triggers:

1. **Vendor inference** against the canonical (pre-seeded) Vendor roster — internal staff vs. vendor resolution from email domain.
2. **Source and Request creation** for the (Tenant, Domain, Vendor?) tuple covering that responsibility's data points, with platform-default cadences per metric.
3. **In-thread acknowledgment** to the GM (welcome message, names the CC'd parties, sets expectations).
4. **Setup-email magic link** dispatched to each named contact, introducing them to their assignment and routing them to a web walkthrough where they pick submission method (form / CSV / API POST) and approve any AI-generated adapter mapping.

**GM accountability — delivered to inbox**:

- Weekly digest summarizing all configured responsibilities, their status, recent submissions, and anything that's lapsed.
- Real-time emails on consequential events — escalations, persistent failures, missed first submissions — naming specific people.
- A magic-link web view of the accountability dashboard exists for GMs who want to drill in but is never required.

**Rolling onboarding**: New question emails are initiated when a new domain (sales, service) launches and applies to the rooftop, or when the question catalog adds questions to a domain the dealer has already covered. The GM can revisit a skipped or assigned responsibility by replying to the original thread or emailing a tenant-specific dedicated address.

**Foundational scope**: This task establishes the data model (Tenant, Source, Request, Responsibility, Vendor, Question Catalog), the Action Mailbox routing and reply-parser pipeline, the question-pacing scheduler, and digest delivery — the foundation every other feature builds on.

**Explicit MVP boundaries** (per productBrief Out of Scope):

- Sales and service domain question catalogs deferred — marketing only at MVP.
- Dealer Group creation/assignment is Rogue-staff-managed, not part of this task.
- BYOK / per-tenant encryption keys deferred — single platform-wide key.
- Tenant co-approval for vendor-authored adapters is not built.

## Specification

**Feature Type**: End-User Feature (foundational platform flow — touches Rogue Staff, Dealership GM, and Invited Contact personas in a single end-to-end loop).

**Primary Persona**: Dealership GM (per `productBrief.md` Key Personas — first row of Primary Users; the email-only onboarding flow is bet on this persona being saturated with apps but fluent in email).

**Secondary Personas**:
- Rogue Staff (seeds the Tenant — only manual operational step on Rogue's side).
- Invited Contact, two flavors:
  - Internal staff submitter (email domain matches Tenant's; will end up as a Tenant Submitter).
  - Vendor user (email domain matches a canonical Vendor record; will end up as a Vendor Submitter scoped to that rooftop).

**Creative Exploration Needed**: Yes — flagged items below carry **LOW** confidence and explicitly require `/rai-creative` resolution.

1. **Tenant seed surface** (Rails admin controller vs. rake task vs. minimal Hotwire form) — productBrief calls this "the only manual step on Rogue's side" but does not specify the surface.
2. **Action Mailbox addressing scheme** — `onboarding+<tenant_token>@inbound.rogue.example` is the working assumption (per `systemPatterns.md`), but plus-addressing vs. per-tenant subdomain vs. dedicated MX has implications for production ingress provider selection.
3. **Reply parser algorithm** — signature stripping heuristic, `skip` detection (must not false-positive on signatures or quoted bodies), CC ordering normalization across mail clients (Gmail, Outlook, Apple Mail rewrite headers differently), and attachment handling.
4. **Question Catalog data model** — is each question a row in a `questions` table or is the catalog a code-defined Ruby module versioned with the app? Has knock-on effects for "rolling onboarding" (productBrief Open Question 1).
5. **Question pacing scheduler** — fixed 24h delay between questions vs. adaptive pacing based on GM responsiveness (e.g., accelerate when GM replies promptly, back off when they go quiet).
6. **Vendor roster seed strategy** — productBrief says "pre-seeded with a substantial roster of common automotive vendors before launch"; "substantial" is undefined, source-of-truth is undefined, maintenance cadence is undefined.
7. **First-question delivery delay after confirm** — productBrief implies questions are paced "over days"; whether the *first* question fires immediately on confirm or after a humanizing delay (e.g., 1 hour) is a UX decision.
8. **In-thread ack format and subject-line conventions** — preserving threading across mail clients while remaining human-readable.

### Invocation Method

#### Rogue Staff — Tenant Seed
- **Location**: `POST /admin/tenants` backed by `Admin::TenantsController#create` (with a `GET /admin/tenants/new` form view). Mounted under `/admin` namespace.
- **Element**: Minimal Hotwire form with three fields — `dealership_name`, `gm_name`, `gm_email` — and a single "Seed tenant" submit button.
- **Visibility**: Gated by `http_basic_authenticate_with` against an env-driven allowlist (`ROGUE_ADMIN_USERNAME` / `ROGUE_ADMIN_PASSWORD`) for MVP. `Admin::BaseController` carries the auth concern so the namespace can grow without re-implementing auth.
- **Justification for choice**: A controller (vs. rake task) gives us a) a real URL we can hand to the small Rogue ops team without shell access, b) something to put system tests against, and c) a natural seam to upgrade to a proper internal admin SSO when ops grows. Rake tasks remain available as `bin/rails rogue:tenants:seed[name,gm_name,gm_email]` for scripted scenarios (and used by tests).
- **Confidence**: **LOW** — productBrief is silent on the surface; this is a defensible default and will be revisited in `/rai-creative` Architecture Design.
- **Outcome on submit**: `Tenant` row created with `status: "pending_confirm"`, `confirmation_sent_at: <now>`. `OnboardingMailer.with(tenant: tenant).confirmation_email.deliver_later` enqueued via Solid Queue. Flash message: `"Seeded Smith Toyota — confirmation email queued for jane@smithtoyota.com."`. Redirect to `GET /admin/tenants/:id` showing seed audit info (status, confirmation_sent_at, link to resend).

#### GM — Single-Click Confirm
- **Location**: `GET /onboarding/confirm/:signed_id` backed by `Onboarding::ConfirmationsController#show`. The `:signed_id` is a Rails `Tenant#signed_id(purpose: :gm_confirm, expires_in: 72.hours)`.
- **Element**: A single anchor in the body of the confirmation email — link text **"Confirm and start onboarding"** — wrapped in a button-styled table cell (email-client safe).
- **Visibility**: Anyone holding the signed link. Single-use (controller checks `confirmed_at` and short-circuits to a "you've already confirmed" page). 72-hour expiry; GM can request a new link from the same controller via `POST /onboarding/confirm/resend?email=...`.
- **Confidence**: HIGH (matches `systemPatterns.md` Magic Links pattern verbatim).
- **Outcome on click**:
  - `Tenant.status` transitions `pending_confirm → confirmed`. `Tenant.confirmed_at = <now>`.
  - GM lands on a one-line page: `"You're confirmed. Watch your inbox for our first question."` (template: `app/views/onboarding/confirmations/show.html.erb`).
  - `OnboardingFlow::EnqueueFirstQuestionJob.perform_later(tenant_id: tenant.id)` is enqueued, which queues `OnboardingMailer.question_email` for the first un-asked question in the marketing catalog. First-question delay configurable per `Tenant.first_question_delay_minutes` (default `0` for MVP — flagged for creative review).

#### GM — Question Email Reply (the primary ongoing surface)
- **Location**: Replies addressed to the per-tenant onboarding address `onboarding+<tenant_token>@inbound.rogue.example`. Routed via Action Mailbox (`config/application_mailbox.rb`) to `OnboardingMailbox`. The `<tenant_token>` is `Tenant#onboarding_token` (a non-signed opaque base58 column persisted at create time; never exposes the primary key, never derived from PII).
- **Element**: GM hits "Reply" in their email client. The original question email's `From:` and `Reply-To:` are both set to the per-tenant onboarding address so all common clients route the reply correctly. The email body explicitly states the three reply conventions (first CC = primary, additional CCs = fallbacks, no CC = self-assign, body `skip` = defer).
- **Visibility**: Only the GM's email address (`Tenant.gm_email`, normalized) can author replies on the thread. Replies from other senders trigger `OnboardingMailer.gm_only_thread_notice` to the actual sender, archived to the InboundEmail record but not processed for assignments.
- **Confidence**: MEDIUM on the addressing scheme (LOW deferred to creative for the subdomain-vs-plus-addressing decision); HIGH on the gating semantics.
- **Outcome on reply**:
  - `ActionMailbox::InboundEmail` row created (raw RFC 822 source retained — Guiding Principle 3, idempotent on Message-ID — Guiding Principle 7).
  - `OnboardingMailbox#process` invokes `OnboardingReplyParser` (service class) to extract: sender, ordered CC list, body intent (`assign | self_assign | skip | unparseable`), and the question being answered (resolved via `In-Reply-To` / `References` lookup against the outbound `Message-ID` on the question email).
  - `VendorInferenceService` classifies each parsed contact (internal staff if domain matches Tenant; vendor if domain matches a canonical `Vendor`; unknown otherwise — triggers in-thread clarification).
  - `Source` row created/linked for the (Tenant, Domain=marketing, Vendor?) tuple covering the question's responsibility.
  - `Responsibility` row created with `primary_contact_id` and ordered `fallback_contact_ids` (jsonb array preserving CC order). One `Request` row per metric the responsibility covers, each with the platform-default cadence for that metric.
  - `OnboardingMailer.invitee_setup_email` sent to each named contact (deduplicated by normalized email).
  - `OnboardingMailer.in_thread_ack` sent back on the same thread (`In-Reply-To` and `References` set so it threads in the GM's client).
  - `OnboardingFlow::EnqueueNextQuestionJob.perform_later(tenant_id:, after: tenant.next_question_delay_hours.hours)` queued (default 24h; configurable per Tenant — flagged for creative).

#### Invited Contact — Setup Magic Link
- **Location**: `GET /setup/:signed_id` backed by `Setup::WalkthroughsController#show`. The `:signed_id` is `Contact#signed_id(purpose: :invitee_setup, expires_in: 7.days)`.
- **Element**: Link in the setup email — link text **"Set up data collection"**.
- **Visibility**: Only the recipient with the signed link. Reusable until expiry (the walkthrough is multi-step; reusing the link to resume is expected). After all walkthrough steps complete, the link redirects to the dashboard magic link (still token-gated, no login required).
- **Confidence**: HIGH on flow shape; MEDIUM on whether the walkthrough can fit in a single page or needs Turbo Frames step navigation (creative call).
- **Outcome on landing**:
  - Step 1: assigned responsibility summary (e.g., "Smith Toyota asked you to provide marketing strategy reporting on a monthly cadence"). Cadence is editable by Tenant Admins (the GM only — invitees cannot, per productBrief).
  - Step 2: submission method picker — radio buttons for `form | csv | api_post`. **Important MVP carve-out**: only `form` produces a fully-configured `Source` at MVP. Selecting `csv` or `api_post` records the intent on the `Source` and parks the contact at a "we'll be in touch when adapter creation is available" state. Adapter generation lands in FEAT-002.
  - Step 3: confirmation — "You're set up. We'll prompt you to submit your first <metric> report on <due_date>." A `SubmissionPrompt` row is scheduled per the cadence (recurring magic-link prompt — actual prompt delivery is in FEAT-002+, but the schedule is established here so the prompt scheduler has data to operate on once it lands).

### Success Criteria

#### Rogue Staff — Tenant Seeded
- **Given**: Rogue Staff is logged into `/admin/tenants/new` (basic auth passed).
- **When**: They submit `dealership_name="Smith Toyota"`, `gm_name="Jane Smith"`, `gm_email="jane@smithtoyota.com"` and click "Seed tenant".
- **Then**:
  - `Tenant` row exists with `status="pending_confirm"`, `dealership_name="Smith Toyota"`, `gm_name="Jane Smith"`, `gm_email="jane@smithtoyota.com"`, `onboarding_token` populated, `confirmation_sent_at` set.
  - Solid Queue holds an enqueued `ActionMailer::MailDeliveryJob` for `OnboardingMailer#confirmation_email`.
  - Flash: `"Seeded Smith Toyota — confirmation email queued for jane@smithtoyota.com."`
  - On worker drain, an email arrives at `jane@smithtoyota.com` with subject `"Welcome to Rogue — confirm to begin"`.
  - Email body contains exactly one CTA link to `/onboarding/confirm/<signed_id>` with link text "Confirm and start onboarding".
- **Observable within**: 1 minute of submit (queue enqueue + worker delivery, dev provider Letter Opener / `:test` adapter).

#### GM — Confirmation
- **Given**: GM has received the confirmation email (Tenant in `pending_confirm`).
- **When**: GM clicks "Confirm and start onboarding".
- **Then**:
  - `Tenant.status="confirmed"`, `Tenant.confirmed_at=<now>` (transitionally idempotent — second click shows "already confirmed" page, does not re-enqueue).
  - GM lands on a single-page response: heading `"You're confirmed."`, body `"Watch your inbox for our first question."`
  - `OnboardingFlow::EnqueueFirstQuestionJob` performs and enqueues `OnboardingMailer#question_email` for the first marketing-catalog question (delivery delayed by `Tenant.first_question_delay_minutes`, default 0 at MVP; revisit in creative).
- **Data persisted**: `tenants.status='confirmed'`, `tenants.confirmed_at IS NOT NULL`. The `OnboardingFlow` audit trail records `confirmed` as the latest event with timestamp and request IP.

#### GM — Question Email + Reply Round Trip
- **Given**: GM has confirmed; the first question email "Who controls your marketing strategy?" (subject `"[Smith Toyota Onboarding] Who controls your marketing strategy?"`) has arrived from `onboarding+<tenant_token>@inbound.rogue.example`.
- **When**: GM replies, CCing `alex@smithtoyota.com` (their internal CMO). Reply body is `"That's Alex, our CMO."` plus a normal email signature.
- **Then**:
  - `ActionMailbox::InboundEmail` row persisted with full RFC 822 source retained indefinitely (Guiding Principle 3).
  - `OnboardingReplyParser` returns `intent: :assign`, `primary: "alex@smithtoyota.com"`, `fallbacks: []`, `question_id: <resolved>`.
  - `VendorInferenceService` classifies `alex@smithtoyota.com` as `internal_staff` (domain matches Tenant's `gm_email` domain `smithtoyota.com`).
  - `Source` row created: `tenant=Smith Toyota`, `domain=:marketing`, `vendor_id=NULL`, `responsibility="marketing_strategy"`.
  - `Responsibility` row created with `primary_contact_email="alex@smithtoyota.com"`, `fallback_contact_emails=[]`.
  - One `Request` row per default metric covered by the marketing-strategy responsibility (e.g., monthly strategy summary), each with platform-default cadence.
  - Setup email queued to `alex@smithtoyota.com` with subject `"Smith Toyota: data collection assignment"` and a `/setup/<signed_id>` link.
  - In-thread ack queued back to GM with `In-Reply-To` and `References` set so it threads in Gmail/Outlook/Apple Mail. Subject prefix `Re: `, body: `"Got it — Alex (alex@smithtoyota.com) is on the hook for marketing strategy. They'll receive setup instructions shortly. Next question coming in 24h."`
  - `OnboardingFlow::EnqueueNextQuestionJob` enqueued with `wait: 24.hours`.
- **Observable within**: 5 minutes of GM's reply arriving at the inbound endpoint (Action Mailbox conductor in dev; production ingress in prod).

#### Invited Contact — Setup
- **Given**: Alex received the setup email at `alex@smithtoyota.com`.
- **When**: Alex clicks "Set up data collection".
- **Then**:
  - Lands on `/setup/<signed_id>`.
  - Step 1 shows: `"Smith Toyota asked you to provide marketing strategy reporting on a monthly cadence."`
  - Step 2 shows three radio options (`form`, `csv`, `api_post`); Alex picks `form`.
  - Step 3 shows: `"You're set up. We'll prompt you to submit your first marketing strategy report on <due_date>."`
- **Data persisted**: `Source.submission_method="form"`, `Source.configured_at=<now>`, `Source.configured_by_contact_id=<alex.id>`. First `SubmissionPrompt` scheduled with `scheduled_for` = the start of the next reporting period's grace window.

#### GM — Weekly Accountability Digest (one cycle)
- **Given**: Tenant `confirmed`, ≥1 `Source` configured, ≥7 days since previous digest (or since `confirmed_at` for the first digest).
- **When**: `WeeklyDigestJob` (declared in `config/recurring.yml`) runs.
- **Then**:
  - Email arrives at `Tenant.gm_email` with subject `"Smith Toyota — weekly accountability digest"`.
  - Body contains a row per `Responsibility` with: responsibility name, primary owner email, current status (`pending_first_submission | on_time | late | overdue`), last submission timestamp (or `—`), next due date.
  - Body contains a single CTA: `"Open dashboard"` linking to `/dashboard/<signed_id>` (Tenant signed_id, purpose `:dashboard_drilldown`, expires in 8 days so the next digest's link supersedes this one).
  - Empty-state copy is explicit: if no submissions have happened yet, the digest still ships and says so (NFR: digest is reliable cadence even when there's no data).

### Acceptance Criteria

Each AC uses Given/When/Then with explicit MUST/SHOULD/COULD priority and a Verification checklist (unit / integration / system / E2E). System tests use Rails' Action Mailbox `receive_inbound_email_from_*` helpers per `systemPatterns.md`.

#### AC-ENTRY-1: Rogue Staff finds the Tenant seed surface
**Priority**: MUST
- **Given**: Rogue staff member has `ROGUE_ADMIN_USERNAME` / `ROGUE_ADMIN_PASSWORD` credentials.
- **When**: They navigate to `/admin/tenants/new`.
- **Then**: They see a form with three labeled fields (Dealership name, GM name, GM email) and a "Seed tenant" submit button.
- **Verification**:
  - [ ] Route exists in `config/routes.rb` under `namespace :admin`.
  - [ ] `Admin::TenantsController#new` renders the form with all three fields.
  - [ ] Without basic auth, request returns 401.
  - [ ] System test: visits `/admin/tenants/new` with credentials, asserts the form fields and submit button.

#### AC-ENTRY-2: GM finds the confirmation link in their email
**Priority**: MUST
- **Given**: GM was just seeded and the confirmation email has been delivered.
- **When**: GM opens the email.
- **Then**: They see a clear single CTA "Confirm and start onboarding" linking to `/onboarding/confirm/<signed_id>`.
- **Verification**:
  - [ ] Mailer test asserts subject `"Welcome to Rogue — confirm to begin"`.
  - [ ] Mailer test asserts exactly one `<a>` linking to a `/onboarding/confirm/...` URL.
  - [ ] Mailer test asserts plain-text alternative also contains the URL (accessibility).

#### AC-ENTRY-3: GM finds the question email and understands reply conventions
**Priority**: MUST
- **Given**: GM is `confirmed`; first question email has been delivered.
- **When**: GM opens the email.
- **Then**: Body explicitly states the four conventions (first CC primary, more CCs fallbacks, no CC self-assign, `skip` defers). `From:` and `Reply-To:` both set to `onboarding+<tenant_token>@inbound.rogue.example`.
- **Verification**:
  - [ ] Mailer test asserts the convention block appears verbatim in the body.
  - [ ] Mailer test asserts `From:` and `Reply-To:` headers.
  - [ ] Mailer test asserts subject contains the dealership name and the question text.

#### AC-ENTRY-4: Invited contact finds the setup link
**Priority**: MUST
- **Given**: GM has named a contact via reply.
- **When**: The contact opens the setup email.
- **Then**: They see one CTA "Set up data collection" linking to `/setup/<signed_id>`.
- **Verification**:
  - [ ] Mailer test asserts subject `"Smith Toyota: data collection assignment"`.
  - [ ] Mailer test asserts CTA URL pattern.

#### AC-HAPPY-1: Rogue Staff seeds a Tenant successfully
**Priority**: MUST
- **Given**: Rogue staff at `/admin/tenants/new`.
- **When**: They submit valid name/GM/email.
- **Then**:
  1. `Tenant` row created with `status="pending_confirm"` and unique `onboarding_token`.
  2. `OnboardingMailer#confirmation_email` enqueued via Solid Queue.
  3. Confirmation email delivered to GM email.
- **Verification**:
  - [ ] Model test: factory + create produces correct defaults.
  - [ ] Controller/system test: full submission round-trip including flash message.
  - [ ] Job test: confirmation mail enqueued exactly once.

#### AC-HAPPY-2: GM confirms successfully and triggers first question
**Priority**: MUST
- **Given**: Tenant is `pending_confirm` with valid signed_id link.
- **When**: GM clicks confirm.
- **Then**:
  1. Tenant transitions to `confirmed` with `confirmed_at` set.
  2. `EnqueueFirstQuestionJob` enqueued.
  3. First question email delivered.
- **Verification**:
  - [ ] System test walks through receive-email → click confirm → see confirmation page.
  - [ ] Job test: first question enqueue + mail delivery.

#### AC-HAPPY-3: GM reply with one CC produces correct downstream artifacts
**Priority**: MUST
- **Given**: GM has the question "Who controls your marketing strategy?" in their inbox.
- **When**: GM replies, CCing one address (`alex@smithtoyota.com`).
- **Then**:
  - `ActionMailbox::InboundEmail` archived (raw RFC 822 source retained).
  - `Responsibility` created: primary `alex@smithtoyota.com`, fallbacks `[]`.
  - `Source` linked to (Tenant, marketing, vendor=null).
  - One in-thread ack to GM, one setup email to Alex.
  - Next-question job enqueued with 24h delay.
- **Verification**:
  - [ ] Action Mailbox system test using `receive_inbound_email_from_mail` with a fixture reply.
  - [ ] Service test on `OnboardingReplyParser` with multiple mail-client signature variants.
  - [ ] Service test on `VendorInferenceService` for internal-domain match.
  - [ ] Mailer tests for both outbound emails, asserting `In-Reply-To` / `References` on the ack.

#### AC-HAPPY-4: GM reply with multiple CCs preserves order
**Priority**: MUST
- **Given**: As AC-HAPPY-3, but GM CCs `alex@smithtoyota.com, taylor@smithtoyota.com, casey@smithtoyota.com` (in that order).
- **When**: Reply is parsed.
- **Then**: `Responsibility.primary_contact_email = "alex@smithtoyota.com"`; `Responsibility.fallback_contact_emails = ["taylor@smithtoyota.com", "casey@smithtoyota.com"]` in that exact order.
- **Verification**:
  - [ ] Parser unit test asserting `primary` / `fallbacks` ordering across at least 5 mail-client header layouts (Gmail, Outlook desktop, Outlook web, Apple Mail, mobile).
  - [ ] System test asserting persisted ordering.

#### AC-HAPPY-5: GM reply with no CC self-assigns the GM
**Priority**: MUST
- **Given**: GM replies to the question with no CCs and a body like `"That's me."`.
- **When**: Reply is parsed.
- **Then**: `Responsibility.primary_contact_email = Tenant.gm_email`; no setup email sent (GM is already the contact); in-thread ack confirms self-assignment.
- **Verification**:
  - [ ] Parser test for `intent: :self_assign`.
  - [ ] System test: assert no `OnboardingMailer#invitee_setup_email` was enqueued.

#### AC-HAPPY-6: GM reply with body `skip` defers
**Priority**: MUST
- **Given**: GM replies with body containing `skip` (case-insensitive, on its own line, not inside a quoted block or signature).
- **When**: Reply is parsed.
- **Then**: A `SkippedQuestion` row records the (tenant, question) pair; no `Responsibility` created; in-thread ack acknowledges the skip and tells the GM how to revisit; next question enqueued.
- **Verification**:
  - [ ] Parser test for `intent: :skip` and the false-positive guard (a body that contains `skip` only inside a signature or a quoted reply must NOT be treated as a skip).
  - [ ] System test asserting database state and ack copy.

#### AC-HAPPY-7: Invited contact completes the setup walkthrough
**Priority**: MUST
- **Given**: Contact has a valid `/setup/<signed_id>` link.
- **When**: They complete steps 1–3, picking submission method `form` and confirming the cadence.
- **Then**: `Source.submission_method="form"`, `Source.configured_at` set, contact sees the success state with the next due date.
- **Verification**:
  - [ ] System test driving the walkthrough end-to-end with Capybara.
  - [ ] Model test on `Source` configuration transition.

#### AC-HAPPY-8: Weekly digest delivers with correct content
**Priority**: MUST
- **Given**: Tenant has been `confirmed` ≥7 days, has ≥1 configured `Responsibility`.
- **When**: `WeeklyDigestJob` runs.
- **Then**: Email delivered with subject `"<Dealership> — weekly accountability digest"`, body listing every responsibility with status, and a single dashboard CTA.
- **Verification**:
  - [ ] Mailer/preview test on the digest with mixed statuses.
  - [ ] Job test: digest sent exactly once per Tenant per cycle (idempotent on re-run within the same week).

#### AC-ERROR-1: Confirmation token invalid/expired/already-used
**Priority**: MUST
- **Given**: GM clicks a confirmation link.
- **When**: The token is invalid, expired, or already consumed.
- **Then**:
  - User sees a specific page: invalid/expired → `"This confirmation link is no longer valid."` with a "Send me a new link" form (POST to `/onboarding/confirm/resend`); already used → `"You've already confirmed Smith Toyota."` with a link to the dashboard magic-link request form.
  - No state mutation on Tenant.
- **Verification**:
  - [ ] Controller test for each of the three branches.
  - [ ] System test for resend-link round trip.

#### AC-ERROR-2: GM reply from a non-GM sender
**Priority**: MUST
- **Given**: A non-GM email address replies on the onboarding thread (or someone else hits the address directly).
- **When**: Action Mailbox routes the reply.
- **Then**:
  - `OnboardingMailer.gm_only_thread_notice` sent back to the actual sender: `"This thread is for the Smith Toyota GM only. If you're trying to reach Rogue, please contact <support>."`
  - No `Responsibility` mutations.
  - InboundEmail row archived (still retained per Guiding Principle 3).
- **Verification**:
  - [ ] Action Mailbox test with a forged-sender fixture.
  - [ ] Mailer test on the notice copy.

#### AC-ERROR-3: GM reply unparseable (no CC, no `skip`, no actionable content)
**Priority**: MUST
- **Given**: GM replies with body `"sounds good"` and no CCs.
- **When**: Reply is parsed.
- **Then**: Parser returns `intent: :unparseable`. In-thread ack to GM: `"We couldn't parse your reply. To assign someone, reply with them in CC. To take this on yourself, reply with no CC and the word 'me'. To defer, reply with 'skip'."` Original question is NOT marked answered; next-question job NOT enqueued.
- **Verification**:
  - [ ] Parser test for `:unparseable`.
  - [ ] System test asserting ack copy and that the question remains pending.

#### AC-ERROR-4: Vendor inference can't classify a CC'd domain
**Priority**: MUST
- **Given**: GM CCs `alex@unknownvendor.com` (domain neither matches Tenant nor any canonical Vendor).
- **When**: Reply is parsed.
- **Then**:
  - Responsibility creation is **deferred** (no `Source` / `Setup email` yet).
  - In-thread question to GM: `"We don't recognize unknownvendor.com. Is Alex internal staff or a vendor we should add to the platform? Reply with 'internal' or 'vendor: <Vendor Name>' to continue."`
  - Subsequent GM clarification reply re-runs vendor inference with the disambiguation; on `vendor: <name>` a new canonical `Vendor` is created and the rest of the flow proceeds.
- **Verification**:
  - [ ] Service test on `VendorInferenceService` for unknown-domain branch.
  - [ ] Action Mailbox system test for the clarification round trip.

#### AC-ERROR-5: Setup magic link expired
**Priority**: MUST
- **Given**: Invitee clicks a `/setup/<signed_id>` link >7 days after issue.
- **When**: Controller verifies token.
- **Then**: User sees `"This setup link has expired."` with a "Send me a new link" form. Token verification failure does not leak whether the underlying contact exists.
- **Verification**:
  - [ ] Controller test for expired-token branch.
  - [ ] System test for resend round trip.

#### AC-ASYNC-1: GM is notified that their reply was processed (in-thread ack)
**Priority**: MUST
- **Given**: GM replied with a parseable assignment.
- **When**: `OnboardingMailbox` finishes processing.
- **Then**: GM receives an in-thread ack within 5 minutes naming the responsibility, the primary owner, and saying when the next question is coming.
- **Verification**:
  - [ ] System test asserting ack delivery and threading headers.

#### AC-ASYNC-2: Invited contact knows when their first prompt is coming
**Priority**: MUST
- **Given**: Invitee just completed setup.
- **When**: Walkthrough success page renders.
- **Then**: Page shows a specific next-prompt date derived from the cadence (not "soon" or "you'll hear from us").
- **Verification**:
  - [ ] System test asserting the rendered date matches `SubmissionPrompt.scheduled_for`.

#### AC-ASYNC-3: GM gets the weekly digest on schedule even with no submissions
**Priority**: MUST
- **Given**: Tenant has been `confirmed` ≥7 days but no submissions have occurred yet.
- **When**: `WeeklyDigestJob` fires.
- **Then**: Digest still ships with empty-state copy (`"No submissions yet — first one due <date>."`); next digest scheduled for +7 days.
- **Verification**:
  - [ ] Job test with no-submission fixture.

#### AC-NAV-1: GM can revisit a previously-skipped responsibility via the original thread
**Priority**: SHOULD
- **Given**: GM previously replied `skip` to a responsibility.
- **When**: GM replies again on the same thread (or to the per-tenant onboarding address) with a CC, naming a contact.
- **Then**: The skipped responsibility is reopened and processed as a normal assignment reply. `SkippedQuestion` row is marked `revisited_at: <now>`.
- **Verification**:
  - [ ] Action Mailbox system test for the skip → revisit round trip.

#### AC-NAV-2: GM uses the dashboard magic link to reach the web view; link expires
**Priority**: SHOULD
- **Given**: GM clicks the "Open dashboard" link in any digest.
- **When**: They land on `/dashboard/<signed_id>`.
- **Then**: They see a read-only summary (server-rendered ERB; rich dashboard is FEAT-003+). Token expires within 8 days (so the next digest's link supersedes it).
- **Verification**:
  - [ ] Controller test for expired-token redirect.
  - [ ] System test for the read-only view.

### Scope Boundaries

#### In scope
- `Tenant` model with status state machine (`seeded → pending_confirm → confirmed → active`) and `onboarding_token` (opaque, indexed, unique).
- `Vendor` canonical model and pre-seeded roster (size flagged for creative; structure includes `name`, `domains[]`, `categories[]`, `created_by`).
- `Contact` model representing a person tied to a Tenant via one or more `Responsibility` rows; classification (`internal_staff | vendor_user | unknown`).
- `Domain` enum (only `:marketing` populated at MVP).
- `Question` catalog (model or code-defined module — see flagged creative item) for the marketing domain.
- `Responsibility` model: primary contact + ordered fallback list, linked to one `Question`, owns one or more `Request` rows.
- `Source` model for (tenant, domain, vendor?) tuple, with `submission_method`.
- `Request` model for individual metric collection cadences (defaults per metric).
- `SubmissionPrompt` schedule rows (sender lives in FEAT-002+ but the schedule data lands here).
- `SkippedQuestion` model.
- `Admin::TenantsController` (seed surface) and `Admin::BaseController` (basic auth concern).
- `Onboarding::ConfirmationsController` (single-click confirm + resend).
- `Setup::WalkthroughsController` (3-step invitee walkthrough).
- `DashboardsController` (read-only magic-link view — placeholder rich UI).
- `OnboardingMailer` — `confirmation_email`, `question_email`, `in_thread_ack`, `invitee_setup_email`, `gm_only_thread_notice`, `vendor_clarification`.
- `AccountabilityMailer` — `weekly_digest`.
- `OnboardingMailbox` — Action Mailbox class routing `/^onboarding\+/` from `inbound.rogue.example`.
- `OnboardingReplyParser` service (CC ordering, no-CC self-assign, `skip` detection with signature/quote guard).
- `VendorInferenceService` (domain → internal/vendor/unknown classification).
- `OnboardingFlow::EnqueueFirstQuestionJob`, `OnboardingFlow::EnqueueNextQuestionJob`, `WeeklyDigestJob` declared in `config/recurring.yml`.
- Action Mailbox installation (`bin/rails action_mailbox:install`, migrations applied).
- `application_mailbox.rb` routing rule for `/^onboarding\+.+@inbound\./`.
- Letter Opener (or `:test` adapter) for outbound mail in development.
- `Current.tenant` (`ActiveSupport::CurrentAttributes`) carrying tenant scope through controllers, jobs, and mailers per `systemPatterns.md`.

#### Out of scope (explicit)
- Sales / Service question catalogs and their flows (productBrief OOS).
- AI-assisted adapter generation for `csv` / `api_post` submission methods (lands in FEAT-002 — the walkthrough captures the choice but does not yet generate an adapter).
- ADF-XML and HTTP POST lead ingestion + per-(tenant, source) inbound addresses (FEAT-002).
- The actual recurring submission prompt sender + magic-link prompt UI (FEAT-002+; we schedule the prompts here, deliver them later).
- The graduated escalation cascade (due-soon → due-today → overdue → fallback fan-out → no-fallback GM nudge) — framework hooks land here (status fields on `Request`) but the escalation engine is a follow-up.
- Dealer Group creation and assignment (Rogue staff out-of-band; not in this task).
- BYOK / per-tenant encryption keys (single platform-wide key per productBrief OOS).
- Tenant co-approval for vendor-authored adapters (productBrief OOS).
- Password + 2FA flow (productBrief calls it opt-in; magic link only at MVP).
- Group Membership permission catalog (architectural seam exists; permissions deferred).
- Production inbound email ingress (Postmark / Mailgun / SendGrid choice — dev uses the Action Mailbox conductor).
- Production outbound email provider (`:test` / Letter Opener in dev).
- Object-storage S3-class raw-payload archive (Active Storage local disk in dev — the schema seam exists, but indefinite-retention in S3 is deferred to production cutover).
- Customer email + phone PII encryption (relevant to leads; no customer leads in this feature).

#### Dependencies
- `bin/rails action_mailbox:install`, `action_mailbox:install:migrations`, `db:migrate` must run as the first build step.
- Solid Queue migrations applied (already part of Rails 8 default; verify on first build).
- `ROGUE_ADMIN_USERNAME` / `ROGUE_ADMIN_PASSWORD` env vars wired in `.env` / `Rails.application.credentials` (per CLAUDE.md "Config in Environment").
- Outbound mail delivery method set per environment (`:letter_opener` in dev, `:test` in test, production deferred).
- Inbound mail in dev via the Action Mailbox conductor at `/rails/conductor/action_mailbox/inbound_emails`.
- Test framework decision (Minitest vs RSpec) made in build phase 1 per `systemPatterns.md` Open Decisions.

#### NFR implications
- **Idempotency** (Guiding Principle 7): every inbound message dedupes on `Message-ID`. Action Mailbox handles this natively.
- **Raw payload retention** (Guiding Principle 3): every `ActionMailbox::InboundEmail` retained indefinitely with full RFC 822 source. Active Storage is the dev backing; S3-class is production (deferred).
- **Single accountability** (Guiding Principle 2): `Responsibility` has exactly one `primary_contact_id` and an ordered `fallback_contact_emails` list — never a many-to-many "team" relation.
- **Tenant isolation** (Guiding Principle 5): every model except `Vendor`, `Question`, and `Domain` carries `tenant_id NOT NULL` with index. No `default_scope`; `Current.tenant` carried through.
- **Reply parser robustness**: signature blocks, quoted reply bodies, multi-language signatures, and HTML-only mail clients must not produce false-positive `skip` matches or wrong CC ordering. Parser must be testable in isolation (service class, not mixed into the Mailbox).
- **Recurring-job resilience**: digest is "this week's data," not "exactly 168h since last digest." Late processing must not double-send; idempotency key on `(tenant_id, week_starting)`.
- **Token security**: signed_ids are scoped per purpose (`:gm_confirm`, `:invitee_setup`, `:dashboard_drilldown`); never reusable across purposes. Confirmation tokens single-use (state-checked); setup and dashboard tokens reusable until expiry.
- **Observability** (CLAUDE.md): structured logging via `Rails.logger.tagged(tenant: ..., flow: :onboarding)`; OpenTelemetry deferred per `techContext.md`. Inbound and outbound email events must be greppable by `tenant_id` and `message_id`.

### Confidence Assessment

#### HIGH confidence (clear from productBrief or `systemPatterns.md`; no exploration needed)
- Magic-link approach (`signed_id` per purpose) and short-vs-long expiry split.
- Tenant status state machine.
- Reply intent taxonomy (assign / self_assign / skip / unparseable).
- Single accountability data shape (primary + ordered fallbacks).
- Scope boundaries vs. FEAT-002+.
- `OnboardingMailbox` / `OnboardingReplyParser` / `VendorInferenceService` separation per `systemPatterns.md` (Mailbox is thin parser/dispatcher).
- Outbound threading via `In-Reply-To` / `References`.
- `Current.tenant` scoping.

#### MEDIUM confidence (defensible default, but reasonable alternatives exist; revisit if creative reveals better)
- Tenant seed surface as a Rails admin controller with HTTP basic auth (vs. rake task only). Default chosen above.
- Setup walkthrough as a 3-step Turbo-Frame flow (vs. a single-page form). Default chosen above.
- Dashboard magic-link expiry of 8 days (so it laps the next digest by 1 day).
- `next_question_delay_hours` default of 24h — productBrief says "spaced over days" so 24h is in-band, but 48h or adaptive may be better.
- `Question` catalog represented as a model + seed file (vs. a code-defined module). Default to model so we can ship a CRUD admin without an app deploy.
- Empty-state digest copy (always send vs. suppress when nothing has happened). Default to always send for habit formation.
- `gm_only_thread_notice` as the response when a non-GM emails the thread (vs. silent drop). Default is to respond so people don't think Rogue is broken.

#### LOW confidence (needs `/rai-creative` exploration before build)
- **Action Mailbox addressing scheme**: plus-addressing on `inbound.rogue.example` vs. per-tenant subdomain (e.g., `<tenant_slug>.inbound.rogue.example`) vs. dedicated MX per Tenant. Has direct implications for production email-ingress provider and DNS strategy. → *Architecture Design*.
- **Reply parser algorithm**: signature stripping (Talon-like heuristics, EmailReplyTrimmer-like, or a custom DSL), `skip` detection with quote/signature guards, attachment handling, multi-part HTML/plain reconciliation, mail-client header variations. → *Algorithm Design*.
- **Question Catalog data model**: row-per-question DB-backed catalog (with a seed file and an admin) vs. code-defined Ruby module versioned with the app vs. a hybrid (code-defined templates, DB row when activated for a Tenant). Affects "rolling onboarding" (productBrief Open Question 1). → *Architecture Design + Data Model Design*.
- **Question pacing scheduler**: fixed 24h delay vs. adaptive based on GM responsiveness (e.g., shorten when GM replies quickly; back off after no reply for 48h). → *User Journey Design*.
- **Vendor roster seed**: source of canonical-vendor data (manual curated CSV? scraped from <known industry resource>? bootstrap from first 100 inbound replies?), how big "substantial" is, who maintains it post-launch. → *Architecture Design + Data Model Design*.
- **Tenant seed surface**: admin controller (default chosen) vs. rake task vs. minimal Hotwire form for non-engineer Rogue staff. → *User Journey Design*.
- **First-question delivery delay after confirm**: 0min (immediate, simplest) vs. ~1h (humanizing) vs. wait-until-next-business-hour (most considerate, most complex). → *User Journey Design*.
- **In-thread ack subject and threading discipline**: how to keep threading reliable across Gmail / Outlook / Apple Mail when the GM may strip/edit the subject. → *Algorithm Design*.

## Test Strategy

### Approach
- **Emphasis**: balanced — heavy on **service-class unit tests** (parser, vendor inference are isolated, deterministic logic with high test value) and **system tests** (Action Mailbox round-trips and Capybara walkthroughs are the only way to verify the email-first user journey end-to-end).
- **Test framework**: **RSpec** (resolved 2026-05-03 in P1; see `systemPatterns.md` Open Decisions). FactoryBot for fixtures, shoulda-matchers for Rails matchers, Capybara for system specs.
- **Target test count**: ~90-120 across all phases. Justified for a multi-component foundational feature: 9 service classes/models with non-trivial behavior, 4 controllers, 2 mailers (with 7+ actions across them), 1 mailbox, 3 jobs, plus end-to-end flows.

### File Organization
- **New test files** (RSpec — `*_spec.rb` under `spec/`):
  - `spec/models/tenant_spec.rb` — state machine, signed_id purposes, gm_email normalization, onboarding_token uniqueness
  - `spec/models/vendor_spec.rb` — domain matching, canonical-vendor invariants
  - `spec/models/responsibility_spec.rb` — primary + ordered fallbacks invariant
  - `spec/models/source_spec.rb` — submission_method states
  - `spec/models/contact_spec.rb` — internal/vendor/unknown classification persistence
  - `spec/models/question_spec.rb` (or `spec/lib/rogue/question_catalog_spec.rb` if code-defined per creative)
  - `spec/services/onboarding_reply_parser_spec.rb` — heaviest unit-test target; 5+ mail-client fixture variants × 4 intents
  - `spec/services/vendor_inference_service_spec.rb` — internal/vendor/unknown branches + edge cases
  - `spec/controllers/admin/tenants_controller_spec.rb` — basic-auth gating, seed happy path, resend
  - `spec/controllers/onboarding/confirmations_controller_spec.rb` — happy / expired / already-used / resend
  - `spec/controllers/setup/walkthroughs_controller_spec.rb` — happy / expired / 3-step navigation
  - `spec/controllers/dashboards_controller_spec.rb` — happy / expired
  - `spec/mailers/onboarding_mailer_spec.rb` — every mailer action, subjects, headers, bodies, plain-text alt
  - `spec/mailers/accountability_mailer_spec.rb` — digest with mixed statuses + empty-state
  - `spec/mailboxes/onboarding_mailbox_spec.rb` — routing, idempotency, GM-only gating
  - `spec/jobs/enqueue_first_question_job_spec.rb`
  - `spec/jobs/enqueue_next_question_job_spec.rb`
  - `spec/jobs/weekly_digest_job_spec.rb` — recurring resilience, idempotency on `(tenant_id, week_starting)`
  - `spec/system/admin_seed_tenant_spec.rb`
  - `spec/system/gm_confirm_and_first_question_spec.rb`
  - `spec/system/gm_reply_assigns_responsibility_spec.rb`
  - `spec/system/invitee_setup_walkthrough_spec.rb`
  - `spec/system/weekly_digest_spec.rb`
- **Extend existing**: nothing — fresh app.

### What NOT to Test
- **Action Mailbox internal routing logic** — covered by Rails framework tests; we test our routing rules and our `process` methods.
- **`signed_id` token cryptography** — covered by Rails. We test our purpose-scoping, expiry, and single-use semantics.
- **Postgres uniqueness constraint enforcement** — covered by Rails. We test our model validations and that the migrations declare the right constraints.
- **Letter Opener delivery mechanics** — covered by the gem. We test that our mailer methods enqueue with the correct subject, headers, and body.
- **Stimulus / Turbo behavior** at MVP — minimal JS surface; we assert rendered HTML with Capybara, not Stimulus controller logic.
- **Solid Queue worker plumbing** — covered by Rails 8. We test that our jobs enqueue with the right args / wait / queue and perform their work correctly when run inline.

### Per-Phase Test Guidance
- **Phase 1** (foundation): ~15 tests — model factories, validations, state machine on `Tenant`, association integrity, `Current.tenant` scoping helper, `signed_id` per-purpose round-trips.
- **Phase 2** (seed + confirm): ~12 tests — `Admin::TenantsController` happy/auth/error, `ConfirmationsController` happy/expired/already-used/resend, `OnboardingMailer#confirmation_email` content and headers, system test for full seed → email → confirm.
- **Phase 3** (first question email): ~8 tests — `OnboardingMailer#question_email` (subject, From, Reply-To, conventions block, plain-text alt, threading-friendly Message-ID), `EnqueueFirstQuestionJob`, system test confirming the question email arrives after confirm.
- **Phase 4** (inbound reply pipeline): ~30 tests — heaviest phase. `OnboardingReplyParser` across 5+ mail-client header variants × 4 intents = 20+; `VendorInferenceService` 3 branches × 2 edge cases = 6; `OnboardingMailbox` routing + Message-ID idempotency = 4; system tests for AC-HAPPY-3/4/5/6 + AC-ERROR-2/3/4 + AC-NAV-1.
- **Phase 5** (invitee setup): ~15 tests — `invitee_setup_email`, `Setup::WalkthroughsController` (3 steps + invalid/expired token branches), `in_thread_ack` threading headers asserted, system test for full walkthrough.
- **Phase 6** (digest + dashboard): ~10 tests — `AccountabilityMailer#weekly_digest` with mixed statuses + empty state, `WeeklyDigestJob` (idempotent on `(tenant_id, week_starting)`), `DashboardsController` happy/expired, system test for digest delivery.

### E2E Anchors (the "feature actually works" gates)
- **`spec/system/gm_email_first_onboarding_full_loop_spec.rb`** — single test that walks: seed via `/admin/tenants/new` → assert confirmation email delivered → click confirm → assert first question email delivered → simulate inbound reply via `receive_inbound_email_from_mail` → assert in-thread ack and setup email delivered → click setup link → complete walkthrough → assert digest scheduled. This is the integration gate.
- **`spec/system/gm_skip_then_revisit_spec.rb`** — covers AC-NAV-1 (skip → later assignment).
- **`spec/system/gm_unknown_vendor_clarification_spec.rb`** — covers AC-ERROR-4 (vendor disambiguation round-trip).

## Implementation Roadmap

### Phasing rationale
The feature splits into 6 build phases that each end at a testable, demonstrable boundary. Phase 1 lays the data substrate; phases 2–3 deliver the GM-confirm → first-question slice; phase 4 is the heaviest (inbound parsing); phases 5–6 close the invitee and accountability loops.

- [x] **Phase 1 — Foundation** *(COMPLETE 2026-05-03)*
  - Action Mailbox already installed from prior setup step.
  - RSpec framework resolved: RSpec + FactoryBot + shoulda-matchers.
  - 11 migrations: `tenants`, `vendors`, `contacts`, `tenant_questions`, `responsibilities`, `sources`, `requests`, `submission_prompts`, `skipped_questions`, `flow_events`, and Action Mailbox parser column extension.
  - Models: `Tenant`, `Vendor`, `Contact`, `TenantQuestion`, `Responsibility`, `Source`, `Request`, `SubmissionPrompt`, `SkippedQuestion`, `FlowEvent`, `Current`.
  - Question Catalog: `lib/rogue/question_catalog/marketing/v1.rb` (6 marketing questions, `materialize_for` idempotent method).
  - Vendor seed CSV (20 entries) + `Rogue::Seeds::VendorsLoader`.
  - 9 FactoryBot factory files.
  - 7 RSpec spec files (models + lib). **89 examples, 0 failures.**
  - Rubocop: 0 offenses.

- [x] **Phase 2 — Tenant seed + GM confirm** *(COMPLETE 2026-05-03)* (closes AC-ENTRY-1, AC-ENTRY-2, AC-HAPPY-1, AC-HAPPY-2, AC-ERROR-1)
  - `Admin::BaseController` (HTTP basic auth concern, env-driven creds).
  - `Admin::TenantsController` (`new`, `create`, `show` showing seed audit info; `resend_confirmation` action).
  - `OnboardingMailer#confirmation_email` (subject, exact body copy with single CTA, plain-text alternative).
  - `Onboarding::ConfirmationsController` (`show` for click-through, `resend` POST). Token via `Tenant#signed_id(purpose: :gm_confirm, expires_in: 72.hours)`.
  - View: `app/views/onboarding/confirmations/show.html.erb` (one-line confirmation page).
  - **Acceptance**: system test from seed → email arrives → confirm click → DB state correct. Resend round-trip works.

- [x] **Phase 3 — First question email** *(COMPLETE 2026-05-03)* (closes AC-ENTRY-3)
  - Question Catalog seed for the marketing domain (whatever data model creative selects).
  - `OnboardingMailer#question_email` with `From:` and `Reply-To:` set to the per-tenant onboarding address; body explicitly states the four reply conventions; subject pattern `[<Dealership> Onboarding] <question text>`.
  - `OnboardingFlow::EnqueueFirstQuestionJob` (chained off the confirm action).
  - **Acceptance**: question email arrives after confirm with the correct headers, body convention block, and a Message-ID that the inbound side can resolve back to the question.

- [x] **Phase 4 — Inbound reply pipeline** *(COMPLETE 2026-05-03)* (closes AC-HAPPY-3, AC-HAPPY-4, AC-HAPPY-5, AC-HAPPY-6, AC-ERROR-2, AC-ERROR-3, AC-ERROR-4, AC-NAV-1)
  - `application_mailbox.rb` rule: `routing /^onboarding\+/i => :onboarding`.
  - `OnboardingMailbox#process` thin dispatcher (mail-client agnostic; defers to parser).
  - `OnboardingReplyParser` service (CC ordering, no-CC self-assign, `skip` detection with quote/signature guards). **Algorithm details land in creative.**
  - `VendorInferenceService` (`internal_staff` / `vendor_user` / `unknown`).
  - Vendor roster seed (initial small set per creative; fully populated at later cutover).
  - `OnboardingMailer#in_thread_ack`, `OnboardingMailer#gm_only_thread_notice`, `OnboardingMailer#vendor_clarification`.
  - `OnboardingFlow::EnqueueNextQuestionJob` (24h default delay; per-Tenant override).
  - `Responsibility` / `Source` / `Request` creation logic. `SkippedQuestion` write path + revisit handling.
  - **Acceptance**: system tests pass across the 8 listed ACs, including a multi-mail-client parser fixture set covering Gmail, Outlook desktop, Outlook web, Apple Mail, and a mobile client.

- [x] **Phase 5 — Invitee setup walkthrough** *(COMPLETE 2026-05-03)* (closes AC-ENTRY-4, AC-HAPPY-7, AC-ERROR-5, AC-ASYNC-1, AC-ASYNC-2)
  - `OnboardingMailer#invitee_setup_email` (subject, CTA, plain-text alt).
  - `Setup::WalkthroughsController` (3-step: summary → method picker → confirmation). Token via `Contact#signed_id(purpose: :invitee_setup, expires_in: 7.days)`. Resumable: same token returns to current step.
  - `SubmissionPrompt` schedule writer (the actual prompt sender lands in FEAT-002+; the schedule rows land here so the future scheduler has data).
  - **Acceptance**: full walkthrough system test from setup-email click to "you're set up" confirmation; in-thread ack threading headers verified to thread correctly in fixture mail-client output.

- [x] **Phase 6 — Weekly digest + dashboard placeholder** *(COMPLETE 2026-05-03)* (closes AC-HAPPY-8, AC-ASYNC-3, AC-NAV-2)
  - `AccountabilityMailer#weekly_digest` (subject, body with row per Responsibility, single dashboard CTA, empty-state copy).
  - `WeeklyDigestJob` declared in `config/recurring.yml`. Idempotency key on `(tenant_id, week_starting)`.
  - `DashboardsController#show` (read-only placeholder — list of responsibilities and statuses; rich dashboard is FEAT-003+). Token via `Tenant#signed_id(purpose: :dashboard_drilldown, expires_in: 8.days)`.
  - **Acceptance**: digest delivers across mixed-status and empty fixtures; dashboard renders with valid token, redirects on expiry.

### Live-Dogfood-Pending items (added to the Tracker section)
- Production inbound email ingress provider selection + DNS — deferred to operational cutover.
- Production outbound email provider selection — deferred to operational cutover.
- Indefinite raw-payload archive in S3-class storage — deferred to operational cutover (Active Storage local disk in dev meets the schema seam).

## Creative Phases

Per Level 4 requirements (and the LOW-confidence items in the Specification), three creative phases are required before build:

- [x] **Architecture Design** → complete (2026-05-03) → `memory-bank/creative/TASK-001-architecture.md`
  - **Scope**: Action Mailbox addressing scheme (plus-addressing on `inbound.rogue.example` vs. per-tenant subdomain vs. dedicated MX); Question Catalog data model (DB-backed model vs. code-defined module vs. hybrid); Vendor roster seed strategy (source, size, maintenance cadence); audit-event/lineage shape (one log table vs. per-domain audit rows).
  - **Why now**: each of these is load-bearing for Phase 1 (data model) and Phase 4 (inbound routing). Building Phase 1 without these decisions risks costly rewrites.
  - **Output target**: `memory-bank/creative/TASK-001-architecture.md`.

- [x] **User Journey Design** → complete (2026-05-03) → `memory-bank/creative/TASK-001-user-journey.md`
  - **Scope**: Tenant seed surface (controller default chosen, but validate against actual ops user; rake task fallback shape); first-question delivery delay after confirm (0min vs. ~1h vs. business-hour-aware); question pacing scheduler (fixed 24h vs. adaptive based on GM responsiveness); empty-state digest behavior; resend-link UX for expired confirmation/setup tokens.
  - **Why now**: drives Phase 2 / Phase 3 copy and timing, plus the recurring scheduler in Phase 6.
  - **Output target**: `memory-bank/creative/TASK-001-user-journey.md`.

- [x] **Algorithm Design** → complete (2026-05-03) → `memory-bank/creative/TASK-001-algorithm.md`
  - **Scope**: Reply parser algorithm — CC ordering normalization across mail clients (Gmail, Outlook desktop, Outlook web, Apple Mail, mobile); signature stripping heuristic (Talon-like vs. EmailReplyTrimmer-like vs. custom); `skip` detection with false-positive guards against quote blocks and signatures; multi-part HTML/plain reconciliation; attachment handling. In-thread ack threading discipline (subject conventions, `In-Reply-To` / `References` chain hygiene, threading across clients when subjects are edited).
  - **Why now**: Phase 4 cannot ship reliably without a defined parser algorithm. Mail-client variation is the highest-risk technical area in this feature.
  - **Output target**: `memory-bank/creative/TASK-001-algorithm.md`.

UI/UX Design is **not** flagged at this stage. The web surfaces (admin seed form, confirmation page, setup walkthrough, dashboard placeholder) are minimal and template-driven; revisit if the User Journey creative phase reveals UX complexity worth dedicated design exploration.

## Clarifications

<!--
  Populated by /rai-clarify TASK-001 (optional, post-plan).
-->

## Spec Review

<!--
  Populated by /rai-spec-review TASK-001 (optional, post-plan).
-->

## Validation Report

<!--
  Populated by /rai-validate TASK-001 (optional, post-build, pre-reflect).
-->

## Live-Dogfood-Pending Tracker

| Item | Phase | Owner | Target | Resolution |
|------|-------|-------|--------|------------|
| Production inbound email ingress provider + DNS (Postmark / Mailgun / SendGrid choice; production receive of an actual ADF-XML or onboarding reply) | 4 | user | operational cutover | PENDING |
| Production outbound email provider selection + warmup (real GM inbox delivery, threading verified in real Gmail/Outlook accounts) | 2,3,4,5,6 | user | operational cutover | PENDING |
| Indefinite raw-payload archive in S3-class storage (Active Storage local disk in dev meets schema seam; production storage class + retention policy) | 4 | user | operational cutover | PENDING |

---

## Execution State

**Build Status**: IDLE
**Current Phase**: REFLECT → ARCHIVE
**Last Completed**: Reflection (2026-05-03) — `memory-bank/reflection/reflection-TASK-001.md`
**Can Resume**: NO — reflection complete; next is `/rai-archive TASK-001`

### Active Sub-Agents
(none)

### Completed Steps
- 2026-05-03 — `/rai-roadmap feature create` → FEAT-001 created at Level 4
- 2026-05-03 — `/rai-plan` Step 0.1 — TASK-001 auto-provisioned from FEAT-001
- 2026-05-03 — `/rai-plan` Step 3 — Spec Writer Agent (Opus) produced `## Specification`
- 2026-05-03 — `/rai-plan` Step 3.2 — specification reviewed and approved
- 2026-05-03 — `/rai-plan` Step 3.5 — Docs Opt-In set to `no` (no Docusaurus tree, platform infra)
- 2026-05-03 — `/rai-plan` Step 3.6 — Marketing Opt-In set to `no` (no marketing schema, platform infra)
- 2026-05-03 — `/rai-plan` Step 5 — Test Strategy + Implementation Roadmap (6 phases) + Creative Phases (Architecture / User Journey / Algorithm) written
- 2026-05-03 — `/rai-plan` Step 6 — validation gate passed; status `PLANNING_COMPLETE`
- 2026-05-03 — `/rai-creative TASK-001` — three creative phases complete in parallel:
  - Architecture (A1-A4): plus-addressing inbox, hybrid Question Catalog, ~200-entry curated Vendor CSV + auto-promotion, outbox-pattern `flow_events` table
  - User Journey (J1-J5): controller + rake seed, 1h first-question delay, adaptive 12h/24h/48h pacing with weekday business-hour envelope, always-send stage-aware digest, self-serve resend with rate limit + anti-enumeration
  - Algorithm (L1-L2): `email_reply_trimmer` + Nokogiri + custom signature regex parser; `Threadable` mailer mixin; deterministic skip regex; 32-fixture mail-client corpus

### Completed Steps (continued)
- 2026-05-03 — Phase 1 Foundation complete: 11 migrations, 11 models (incl. Current), Question Catalog V1, vendor seed CSV + loader, 9 factories, 7 spec files, 89 examples green, 0 rubocop offenses.
- 2026-05-03 — Phase 2 Tenant seed + GM confirm complete: Admin::BaseController, Admin::TenantsController, Onboarding::ConfirmationsController, Tenant::Seeder service, OnboardingMailer#confirmation_email, all views, rake task, 5 spec files (58 new examples). Total: 147 examples, 0 failures, 0 rubocop offenses.
- 2026-05-03 — Phase 3 First question email complete: Threadable concern, OnboardingMailer#question_email, question_email views (html+text), OnboardingFlow::Scheduling service, OnboardingFlow::EnqueueFirstQuestionJob, OnboardingFlow::EnqueueNextQuestionJob, Tenant#confirm! wired to materialize_for, controller TODO unwired. 5 spec files (38 new examples). Total: 185 examples, 0 failures, 0 rubocop offenses.
- 2026-05-03 — Phase 4 Inbound reply pipeline complete (resumed after crash): ApplicationMailbox onboarding+ routing (with onboarding@ fallback), OnboardingMailbox dispatcher (tenant resolution via plus-token + In-Reply-To fallback, GM-only sender gating, Message-ID idempotency via Action Mailbox), OnboardingReplyParser (CcOrdering / BodyExtractor / SkipDetector / ThreadResolver modules; email_reply_trimmer + Nokogiri quote stripping; deterministic skip regex; raw_excerpt 4 KB cap), VendorInferenceService (internal_staff/vendor_user/unknown), OnboardingFlow::AdaptivePacing (12h/24h/48h/silence per J3), OnboardingMailer#in_thread_ack / #gm_only_thread_notice / #vendor_clarification with html+text views, OnboardingMailerHelper#humanize_next_question_at, FlowEvent records for reply.parsed, responsibility.created, question.skipped, question.revisited, reply.unparseable, reply.rejected_non_gm_sender, vendor.clarification_requested, vendor.bootstrap_from_clarification. Touch-up: cleared 2 pre-existing rubocop offenses in config/routes.rb. 4 new spec files (mailbox + 3 service specs) + onboarding_mailer_spec extended. **Total: 242 examples, 0 failures, 0 rubocop offenses.**
- 2026-05-03 — Phase 5 Invitee setup walkthrough complete: OnboardingMailer#invitee_setup_email + html/text views, Setup::WalkthroughsController (3-step show/update at /setup/:signed_id, resumable, expired-page on bad/old token), Setup::Completion service, OnboardingFlow::RequestProvisioning (creates Request rows from catalog metrics), OnboardingFlow::SubmissionPromptScheduler (next-period start in tenant TZ for weekly/monthly/quarterly/semi_annual/annual cadences), Contact#invitee_setup_signed_id helpers, Rogue::QuestionCatalog::Marketing::V1.metrics_for, OnboardingMailbox wired to send invitee_setup_email and provision Requests on assignment. 6 new/extended spec files (mailer extended; setup walkthrough request specs; 3 new service specs; catalog spec extended; mailbox spec extended). **Total: 279 examples, 0 failures, 0 rubocop offenses.**
- 2026-05-03 — Phase 6 Weekly digest + dashboard placeholder complete: AccountabilityMailer#weekly_digest with html+text views (per-row responsibility status table + Open Dashboard CTA + empty-state copy), WeeklyDigestJob (eligibility filter on `confirmed_at <= 7.days.ago`, idempotency via WeeklyDigestDelivery unique on `(tenant_id, week_starting)`, FlowEvent emit on send), Accountability::DigestAssembler service (Row + Digest value objects; pending_setup vs pending_first_submission status), DashboardsController#show at /dashboard/:signed_id (read-only summary; expired view on bad/old token), Tenant#dashboard_signed_id helpers (8-day expiry), config/recurring.yml schedules WeeklyDigestJob Mondays 9am, migration 20260503180611 creates weekly_digest_deliveries table. 5 new spec files (mailer + job + dashboard request + assembler service + delivery model). **Total: 307 examples, 0 failures, 0 rubocop offenses.**
- 2026-05-03 — Reflection complete: `memory-bank/reflection/reflection-TASK-001.md`. Two-dimensional Level 4 evaluation (task quality + ecosystem). 4 patterns extracted into `agent-rules/_learned/`: idempotency, time-zones, service-shape, audit-trail. Status REFLECTION_COMPLETE.

### Next
- `/rai-archive TASK-001` — mandatory for Level 4. Will commit reflection + memory-bank updates and PR `feature/FEAT-001-tenant-gm-email-onboarding` → `main`.
