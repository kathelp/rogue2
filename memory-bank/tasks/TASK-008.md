# TASK-008: Cc'd Contact Self-Verification

**Complexity**: Level 3 (inherited from FEAT-006)
**Status**: ARCHIVED 2026-05-09
**Archive**: memory-bank/archive/archive-TASK-008.md
**Roadmap**: FEAT-006
**Branch**: feature/FEAT-006-ccd-contact-self-verification
**Worktree**: N/A
**Docs Opt-In**: no
**Docs Opt-In Reason**: no Docusaurus tree at docs/
**Marketing Opt-In**: no
**Marketing Opt-In Reason**: no marketing schema at db/seeds/marketing/

## Task Description

When new users are onboarded from being cc'd on an email, we should ask them to enter their first name, last name, and phone number to complete their account verification.

Today, contacts promoted into the system via a GM CC arrive with little more than an email address. This feature closes that gap by giving the contact a self-service step to fill in their identity and phone before they're treated as a fully-onboarded responsibility holder.

**Decided** (per /rai-roadmap update on 2026-05-09):
- Verification status is *derived* from field presence — a contact is "unverified" while any of `first_name`, `last_name`, or `phone` is blank, and "verified" once all three are populated.
- No separate `verified_at` timestamp or state machine. The columns are the source of truth.

**Open design questions** (to resolve in `/rai-creative` or `/rai-clarify`):
1. **Trigger** — verification email with signed-link landing page, inline prompt on the next setup-email click-through, or both?
2. **Gating semantics** — what specifically changes for an unverified contact? Candidate gates: pause submission prompts, suppress escalation fanout to them, hold them out of the GM's weekly digest until verified, mark them visually in admin views.
3. **Schema** — split the existing `Contact#name` into `first_name` / `last_name`, or keep `name` and add the new fields alongside?
4. **Phone handling** — validation/normalization (E.164 for future Twilio use).
5. **Re-prompt cadence** — what happens if the contact ignores the verification email; expire the link? Escalate to the GM?

Note: Rogue's onboarding model treats `Contact` as the persona record; `Responsibility` is the accountability assignment. Verification belongs on `Contact`.

## Specification

**Feature Type**: End-User Feature
**Primary Persona**: CC'd Contact — a responsibility holder who arrived in the system via a GM's CC reply. They have an email address and possibly a `display_name` parsed from the From header, but no first name, last name, or phone on record. They will receive submission prompt emails and escalation emails once onboarded; this feature gives them the self-service step to complete their identity before those flows depend on them.
**Creative Exploration Needed**: Yes — five open questions (see "Creative Exploration Needed" section below). Invocation method, gating semantics, schema shape, phone handling, and re-prompt cadence are all LOW confidence pending `/rai-creative`.

### Invocation Method

- **Location**: TBD — either (a) a dedicated verification email sent immediately after contact promotion in `OnboardingMailbox#handle_assignment`, or (b) an inline prompt layered into the existing invitee setup walkthrough at `Setup::WalkthroughsController` (`/setup/:signed_id`), or (c) both. The trigger question is OPEN.
- **Element**: TBD — likely a signed-link button in an email (mirroring the `submission_form_url` pattern in `SubmissionMailer#prompt_email`) leading to a new no-login verification form page (mirroring `Submissions::FormsController`). Exact element and copy TBD in `/rai-creative`.
- **Visibility**: Email-delivered (push). Not a navigable web surface — the contact receives the link; they don't discover it.
- **Navigation**: Contact receives email → clicks signed link → lands on verification form at a new route (e.g., `/contacts/:signed_id/verify`) → submits first name, last name, phone → sees confirmation. Exact route and controller TBD.
- **Confidence**: LOW — trigger mechanism, route structure, and whether verification is a standalone flow vs. integrated into setup walkthrough all require creative decision. The signed-link no-login *pattern* is HIGH confidence (established in `Contact#invitee_setup_signed_id` + `SubmissionPrompt#submission_form_signed_id` + `Submissions::FormsController`).

### Success Criteria

- **User sees**: A confirmation page (or inline confirmation state) indicating their information has been saved and they are now verified. Exact copy TBD in `/rai-creative`.
- **Verifiable at**: The `Contact` record for their email — all three of `first_name`, `last_name`, and `phone` are non-blank after a successful submission. `contact.verified?` returns `true`.
- **Data persisted**: `contacts` table — three new columns to be added (exact column names and their relationship to the existing `display_name` column are TBD per Schema question; see Creative Exploration below). The columns are the source of truth for verification status; no separate `verified_at` or state machine.
- **Observable within**: Immediate — synchronous form POST, same as `Submissions::FormsController#create`.

### Acceptance Criteria

#### AC-ENTRY-1: CC'd contact receives verification invitation
**Priority**: MUST
**Given** a GM reply is parsed by `OnboardingMailbox#handle_assignment` with intent `:assign`, creating a new `Contact` record via `Contact.find_or_create_for_email`
**When** the contact has no prior verification data (all three identity fields are blank)
**Then** the system sends a verification invitation to the contact's email address containing a signed link unique to that contact, and a `FlowEvent` is recorded for the invitation dispatch (event type TBD in `/rai-creative`, e.g., `contact.verification_invited`)

*Note: The exact trigger timing (immediate vs. deferred vs. layered into setup email) is OPEN — `/rai-creative` decides. This AC describes the outcome regardless of trigger mechanism.*

#### AC-HAPPY-1: Contact completes verification
**Priority**: MUST
**Given** a contact with a valid, unexpired verification signed link
**When** they submit:
  1. A non-blank `first_name`
  2. A non-blank `last_name`
  3. A valid phone number (format TBD per Phone Handling question)
**Then**:
  - The `Contact` record is updated with the three fields
  - `contact.verified?` returns `true` (all three fields now present)
  - The contact sees a confirmation page
  - A `FlowEvent` is recorded (event type TBD, e.g., `contact.verified`)
  - The signed link remains usable for re-access but re-submission is idempotent (no double-write side effects)

#### AC-ERROR-1: Contact recovers from invalid input
**Priority**: MUST
**Given** a contact at the verification form with a valid signed link
**When** they submit with any of:
  - A blank `first_name` or `last_name`
  - A missing or malformed phone number
**Then**:
  - The form re-renders with inline field-level error messages (HTTP 422, same pattern as `Submissions::FormsController#create` re-rendering `:show`)
  - The `Contact` record is NOT updated
  - The contact can correct their input and resubmit

#### AC-GATING-1: System behavior changes based on verification state
**Priority**: MUST
**Given** a `Contact` that is unverified (one or more of `first_name`, `last_name`, `phone` is blank)
**When** the system performs an action that depends on the contact being fully onboarded (exact actions TBD)
**Then** the system applies the decided gate (e.g., skips escalation fanout to this contact, suppresses submission prompts, excludes from digest rows, marks as pending in admin views)

*This AC is a PLACEHOLDER — the specific gating behavior requires `/rai-creative` to resolve Question 2 (Gating Semantics). Candidate gates are: (a) suppress escalation fanout in `OnboardingFlow::EscalationCascade` when the fallback email matches an unverified contact, (b) hold submission prompts for unverified contacts, (c) mark rows in `Accountability::DigestAssembler` as `:pending_verification` status, (d) visual flag in admin views. All four candidates are implementable without schema changes beyond the three new contact columns.*

#### AC-LINK-1: Signed link is tamper-resistant and purpose-scoped
**Priority**: MUST
**Given** a verification URL for contact A
**When** the signed_id in the URL is tampered with, expired, or substituted with a different contact's signed_id
**Then**:
  - The controller renders an expired/invalid page (HTTP 404, no information leakage about whether the contact exists)
  - No `Contact` record is modified

*Implementation note: This AC is HIGH confidence — follow the exact pattern established by `Contact#invitee_setup_signed_id` (purpose: `:invitee_setup`) and `SubmissionPrompt#submission_form_signed_id` (purpose: `:submission_form`). Add a new purpose-scoped helper, e.g., `Contact#verification_signed_id(expires_in:)` with purpose `:contact_verification`, and `Contact.find_by_verification_signed_id(signed_id)`. Controller `before_action` calls `find_by_verification_signed_id` and renders `:expired` on nil, mirroring `Submissions::FormsController#load_prompt`.*

### Scope Boundaries

**In scope:**
- Three new columns on the `contacts` table (`first_name`, `last_name`, `phone` — exact shape TBD per Schema question)
- A `verified?` predicate on `Contact` derived from field presence (no state machine)
- A verification invitation email (new mailer action, likely on a new `Contacts::VerificationMailer` or added to `OnboardingMailer`) with a per-contact signed link
- A no-login verification form controller + views (new, modeled on `Submissions::FormsController`)
- New route(s) for the verification form (modeled on `/submissions/:signed_id`)
- FlowEvents for invitation dispatch and successful verification
- Integration into the CC-contact-promotion path (`OnboardingMailbox#handle_assignment`) to trigger the invitation
- Gating behavior (exact behavior TBD) applied at decided system boundaries
- Factory traits for `verified` / `unverified` contacts in `spec/factories/contacts.rb`

**Out of scope:**
- Password + 2FA flows — verification is magic-link only, consistent with the platform's access model
- GM-initiated verification (the GM does not manually trigger or approve contact verification)
- Verified contact editing their own profile post-verification (not a portal; one-time self-service step)
- SMS delivery of the verification link (SMS provider not yet wired; email-only at MVP)
- Retroactive verification of contacts created before this feature ships (migration/backfill strategy deferred)
- Admin UI for viewing or overriding contact verification status (the three columns are sufficient for ops-level inspection via Rails console at MVP)
- Re-prompt cadence automation (if scoped out in `/rai-creative` Question 5)
- AI-assisted name parsing from `display_name` — contact fills in manually

**Dependencies:**
- FEAT-001 / TASK-001 (completed): `Contact` model, `Responsibility` model, `OnboardingMailbox#handle_assignment` — the entry point where verification should be triggered
- FEAT-002 / TASK-002 (completed): `Submissions::FormsController` — the signed-link no-login controller pattern to emulate
- FEAT-004 / TASK-003 (completed): `OnboardingFlow::EscalationCascade` — may need gating hooks
- `Accountability::DigestAssembler` — may need a new `:pending_verification` status row

**NFR implications:**
- **Security**: The verification signed link must use `signed_id` with a per-purpose scope (`:contact_verification`) so it cannot be substituted with a `submission_form` or `invitee_setup` token. Expiry TBD (24-72h is consistent with other one-time tokens). No information leakage on invalid tokens.
- **Encryption**: `Contact.email` is already encrypted with `encrypts :email, deterministic: true`. The new `phone` column may require encryption at rest (`encrypts :phone`) given it is PII — to be decided in `/rai-creative` Architecture Design phase. `first_name` and `last_name` are not explicitly called out as PII-encrypted fields in the productBrief MVP scope, but the decision should be made explicitly.
- **Idempotency**: A contact clicking the verification link multiple times must be safe. The form POST should be idempotent — re-submitting the same values is a no-op; re-submitting new values updates the record (last-write-wins is acceptable for a self-service identity form).
- **Tenant isolation**: `Contact` already carries `tenant_id NOT NULL`. The verification controller must scope the contact lookup to the correct tenant (enforced via signed_id — the record is looked up by its signed_id, which is tenant-scoped by association).
- **Audit trail**: `FlowEvent.record!` must be called inside the same transaction as the `Contact` update, per the project's FlowEvent atomicity rule.

### Creative Exploration Needed

The following five questions are genuinely OPEN. All five must be resolved in `/rai-creative` before implementation phases can be finalized:

**Question 1 — Trigger (LOW confidence)**
How does the contact receive the verification invitation?
- Option A: Dedicated verification email sent immediately after `Contact.find_or_create_for_email` in `OnboardingMailbox#handle_assignment` (new mailer action, new job).
- Option B: Inline prompt embedded in the existing `invitee_setup_email` (no new email; verification is a step in the setup walkthrough at `Setup::WalkthroughsController`).
- Option C: Both — setup email first, then a follow-up verification email if they complete setup but skip verification.
- Design question: Does verification precede or follow the setup walkthrough? The walkthrough configures the Source (submission method); verification fills in the Contact's identity. They are logically independent but sequencing matters for UX.

**Question 2 — Gating semantics (LOW confidence)**
What specific system behaviors change while a contact is unverified?
- Candidate A: Suppress escalation fanout — `OnboardingFlow::EscalationCascade` skips fallback contacts whose email matches an unverified `Contact`. Impact: `EscalationCascade.fallback_emails_for` needs to filter against verified contacts.
- Candidate B: Hold submission prompts — `SubmissionPromptSenderJob` skips sending prompts to contacts whose `Contact` record is unverified. Impact: changes the sender's eligibility filter.
- Candidate C: Digest status — `Accountability::DigestAssembler` emits a new `:pending_verification` status for responsibilities whose primary contact is unverified. Impact: new status slug, new digest partial.
- Candidate D: Visual flag only — no behavioral gate; unverified contacts are flagged in admin views but all emails still flow. Impact: minimal code, minimal user value.
- Multiple candidates can be combined. Scope and priority must be decided before Phase 4 can be planned.

**Question 3 — Schema (LOW confidence, but codebase has clear evidence)**
The current `contacts` table has `display_name` (nullable string) — there is no `name` column. The task description and roadmap both mention "splitting `Contact#name` into `first_name` / `last_name`" but the actual column is `display_name`.
- Option A: Add `first_name`, `last_name`, `phone` as three new columns alongside the existing `display_name`. Keep `display_name` for display purposes (e.g., rendered in emails). This is the lowest-risk migration path.
- Option B: Rename `display_name` to `name` (if it was intended as a name field) and then add `first_name`, `last_name`, `phone`. More disruptive; requires a column rename migration.
- Option C: Treat `display_name` as the legacy parsed-from-header field; `first_name` + `last_name` are the verified identity fields. They coexist and `display_name` is superseded once verification completes.
- `/rai-creative` must decide column names and the relationship between `display_name` and the new fields. The schema question is HIGH priority because it gates Phase 1.

**Question 4 — Phone validation and normalization (LOW confidence)**
What format does the phone field accept and store?
- Option A: Store as-is (free-form string), validate only that it's non-blank.
- Option B: Normalize to E.164 (`+1XXXXXXXXXX`) using the `phonelib` gem (already in common use for Twilio-bound systems; not yet in the Gemfile). Required if the phone field will be used for Twilio SMS in a future feature.
- Option C: Accept a liberal format but normalize on write using a before-validation callback.
- The productBrief calls out Twilio as the likely SMS provider. E.164 normalization now would prevent a future migration. `/rai-creative` should decide format and whether `phonelib` is added to the Gemfile.

**Question 5 — Re-prompt cadence (LOW confidence)**
What happens if the contact ignores the verification invitation?
- Option A: The link expires (24-72h) and nothing further happens — unverified contacts stay in limbo.
- Option B: A new signed link is generated and re-sent after N days (recurring job, similar pattern to the escalation cascade).
- Option C: Escalate to the GM — after N days of no verification, the GM is notified (new FlowEvent + mailer action).
- Option D: No re-prompt at MVP; address with rolling onboarding tooling later.
- This decision affects whether Phase 5 is in scope at all. `/rai-creative` should size the re-prompt work before the implementation roadmap is finalized.

---

## Test Strategy

### Approach
- **Emphasis**: backend-only (model, service PORO, service-level gating). No request specs, no mailer specs, no system specs in this cycle — those land in the deferred FE pass.
- **Target test count**: 8–11 total.

### File Organization
**New test files:**
- `spec/services/contacts/phone_normalizer_spec.rb` — US E.164 normalizer happy + invalid-format + edge-case tests

**Extend existing:**
- `spec/models/contact_spec.rb` — `#verified?` true/false matrix (3 fields × empty/present), `:verified` / `:unverified` scopes, encryption round-trip on `:phone`
- `spec/factories/contacts.rb` — `:verified` / `:unverified` traits (drives the matrix)
- `spec/services/onboarding_flow/escalation_cascade_spec.rb` — Phase 3 gating: unverified Contact email is filtered out of `fallback_emails_for`; verified Contact stays in; unknown raw email passes through; sender chooses next eligible fallback

### What NOT to Test (this cycle)
- View rendering, form posts, controller branches — DEFERRED to FE pass
- Mailer subject/body content — DEFERRED to FE pass
- System E2E flow — DEFERRED to FE pass
- ActionMailer delivery internals (SMTP, threading) — out of scope; covered by FEAT-001
- `signed_id` cryptographic correctness — Rails framework concern; we reuse existing `:invitee_setup` purpose
- Admin UI for verification status — out of scope per Scope Boundaries

### Per-Phase Test Guidance
- **Phase 1 (schema + model)**: ~4 tests — `verified?` matrix, scopes, phone encryption round-trip, factory traits exercise
- **Phase 2 (PhoneNormalizer)**: ~4 tests — happy E.164, invalid format returns nil, leading +1, common formatting variants
- **Phase 3 (cascade gating)**: ~3 tests — unverified filtered, verified passes, unknown raw email passes through

## Implementation Roadmap

**Scope cut (2026-05-09, user directive):** All front-end work (views, mailer template bodies, system tests) is **DEFERRED** to a later design pass. This cycle ships the backend foundation only — schema, model, encryption, phone normalizer, and the cascade gating logic. The contact won't have a working identity form yet; once it lands, the backend is ready to receive the form's payload.

### Active phases (this cycle)

- [x] **Phase 1: Schema + Contact model** — COMPLETE 2026-05-09 (commit af9c745). 401 specs pass; rubyfmt --check exits 0 globally.
  - Migration `RemoveDisplayNameFromContactsAndAddIdentityFields`: drops `display_name` (specify column type on `remove_column` so the migration is reversible); adds `first_name :string`, `last_name :string`, `phone :string` (all nullable — an unverified contact is a valid record).
  - `Contact#verified?` predicate (`first_name.present? && last_name.present? && phone.present?`); add `:verified` / `:unverified` scopes.
  - `encrypts :phone` (NON-deterministic per architecture doc; names stay unencrypted at MVP).
  - **No** model-level presence validations on the new columns. Presence is enforced at the future identity-form controller, not on every `Contact.find_or_create_for_email` call.
  - Update `spec/factories/contacts.rb` with `:verified` / `:unverified` traits.

- [x] **Phase 2: `Contacts::PhoneNormalizer` PORO** — COMPLETE 2026-05-09 (commit 9a01d5d). 10/10 phone normalizer specs pass.

- [x] **Phase 3: Escalation cascade gating** — COMPLETE 2026-05-09 (commit 3af0344). 16/16 cascade specs pass; 414 total specs green; rubyfmt --check exits 0 globally.

### Deferred phases (front-end design pass — separate task or follow-up cycle)

- [ ] [DEFERRED-FE] **Setup walkthrough identity step** — controller branch in `Setup::WalkthroughsController#template_for_step`, new `identity.html.erb` view, identity PATCH action, step-counter updates on `summary.html.erb` + `method_picker.html.erb`, empty-responsibility else-branch on `summary.html.erb`. All UI/UX decisions are documented in `memory-bank/creative/TASK-008-uiux.md` and remain valid.
- [ ] [DEFERRED-FE] **Edited `OnboardingMailer#invitee_setup_email`** — subject + HTML/text body copy per UI/UX doc. Optional `contact.invited_for_setup` FlowEvent in `OnboardingMailbox#handle_assignment`.
- [ ] [DEFERRED-FE] **System test + polish** — E2E spec covering GM reply → CC promotion → invitation → identity step → cascade gating activates. Letter-opener verification of email copy.

### Cross-phase invariants (apply to both active and deferred phases)
- Audit-trail rule: every Contact mutation wraps the FlowEvent write in the same transaction.
- Idempotency rule: future identity-form re-submit must be safe (last-write-wins; no double-FlowEvent — guard with presence check or `find_or_create_by` on the event).
- Tenant isolation: future controller path inherits signed-link tenant scoping via existing `Setup::WalkthroughsController` patterns. No additional scoping needed.

## Creative Phases

All three phases are REQUIRED before `/rai-build` can start. Run them in this order:

- [x] **Architecture Design** → COMPLETE (memory-bank/creative/TASK-008-architecture.md)
- [x] **User Journey Design** → COMPLETE (memory-bank/creative/TASK-008-user-journey.md)
- [x] **UI/UX Design** → COMPLETE (memory-bank/creative/TASK-008-uiux.md)

## Clarifications

<!--
  Populated by /rai-clarify TASK-008 (optional, post-plan).
-->

## Spec Review

<!--
  Populated by /rai-spec-review TASK-008 (optional, post-plan).
-->

## Validation Report

<!--
  Populated by /rai-validate TASK-008 (optional, post-build, pre-reflect).
-->

## Live-Dogfood-Pending Tracker

| Item | Phase | Owner | Target | Resolution |
|------|-------|-------|--------|------------|
| Setup walkthrough identity step (controller + view) | DEFERRED-FE | user | future FE design task | RESOLVED — parked at archive (2026-05-09); UI/UX spec preserved at `memory-bank/creative/TASK-008-uiux.md` |
| Edited `invitee_setup_email` subject + body copy | DEFERRED-FE | user | future FE design task | RESOLVED — parked at archive (2026-05-09); copy spec preserved in UI/UX creative doc |
| End-to-end system spec (GM reply → CC promotion → identity step → cascade gating) | DEFERRED-FE | user | future FE design task | RESOLVED — parked at archive (2026-05-09); to be authored alongside the FE work |
| Letter-opener manual verification of edited email | DEFERRED-FE | user | future FE design task | RESOLVED — parked at archive (2026-05-09); applies once email body edits land |

---

## Execution State

**Build Status**: REFLECT_COMPLETE
**Current Phase**: REFLECT
**Current Step**: Step 3 — Reflection Agent — COMPLETE
**Step Started**: 2026-05-09
**Can Resume**: YES

### Active Sub-Agents
- Reflection Agent (general-purpose, sonnet): COMPLETE → memory-bank/reflection/reflection-TASK-008.md

**Note:** All 3 active backend phases complete. The 3 deferred FE phases stay in the Live-Dogfood-Pending Tracker for a separate design pass.

### Active Sub-Agents
- Architecture Design (general-purpose, opus): COMPLETE → memory-bank/creative/TASK-008-architecture.md
  - Q3 Schema: DROP `display_name`, add canonical `first_name`/`last_name`/`phone`
  - Q2 Gating: Suppress escalation fanout to unverified (Candidate A only — submission prompts still flow)
  - Q4 Phone: In-house `Contacts::PhoneNormalizer` (US E.164) + non-deterministic encryption on `phone`
- User Journey Design (general-purpose, opus): COMPLETE → memory-bank/creative/TASK-008-user-journey.md
  - Q1 Trigger: Inline in existing setup walkthrough (Option B — no new mailer/controller; identity becomes Step 1 of 4)
  - Q5 Re-prompt: None at MVP (Option D — piggybacks on 7-day setup link expiry; gm_nudge cascade handles silence)
- UI/UX Design (general-purpose, sonnet): COMPLETE → memory-bank/creative/TASK-008-uiux.md
  - Email: subject + both body templates edited (honest "name + phone + method" framing)
  - Layout: single-column inline-CSS identity form (Step 1 of 4), mirrors summary.html.erb
  - Errors: field-level @errors hash + aria-describedby, no flash banner
  - Phone: explained as future-SMS, explicit no-marketing promise
  - Terminal: empty-responsibility else-clause updated with first-name ack + suppressed Continue link

### Completed Steps
- Step 0: Parsed FEAT-006, resolved to new task TASK-008
- Step 0.1: Created task file from template, registered in tasks.md, linked in roadmap.md
- Step 0.2: Phase Gate passed (task registered)
- Step 0.5: Agent rules present in `_learned/` but no index file. Skipped inline indexing in auto mode — Spec Writer reads rules directly.
- Step 1: New planning session
- Step 2: Roadmap link verified (FEAT-006)
- Step 3: Spec Writer Agent (Sonnet) drafted full Specification section with 5 ACs and 5 LOW-confidence creative questions
- Step 3.2: Spec auto-approved (auto mode; LOW confidence flags propagated to Creative Phases)
- Step 3.3: Creative phases REQUIRED — Architecture, User Journey, UI/UX
- Step 3.4: Specification finalized in task file; redundant placeholder `## User Journey Definition` removed
- Step 3.5: Docs Opt-In = no (no Docusaurus tree)
- Step 3.6: Marketing Opt-In = no (no marketing schema)
- Step 4: Codebase analysis incorporated by Spec Writer (cited `Submissions::FormsController`, `Contact#invitee_setup_signed_id`, `OnboardingMailbox#handle_assignment`, etc.)
- Step 5: Implementation Roadmap (6 phases, dependency-flagged), Test Strategy (14–20 tests, file-mapped, per-phase counts), Creative Phases (3 required, ordered) all populated
- Step 6: Validation Gate — concreteness checkboxes intentionally fail (multiple TBD fields) → routed to Creative Phase per Validation Gate rule
- /rai-creative Step 1: Read TASK-008 context (Level 3, all three creative phases required)
- /rai-creative Step 2: Confirmed `memory-bank/creative/` exists
- /rai-creative Step 3 — Wave 1 (parallel): Architecture (Opus) + User Journey (Opus). Both COMPLETE. Real tension surfaced and resolved (gating Candidate A only — submission prompts still flow, so no deadlock with Q5=D).
- /rai-creative Step 3 — Wave 2 (sequential): UI/UX (Sonnet) with both predecessor docs as input. COMPLETE. Surprising codebase finding: project uses inline CSS, not Tailwind — Phase 6 polish updated accordingly.
- /rai-creative Step 4: All three output files validated (memory-bank/creative/TASK-008-*.md)
- /rai-creative Step 5: Implementation Roadmap reconciled with locked decisions (Phase 5 dropped, Phase 2 reframed as setup-walkthrough extension, Phase 6 inline-CSS not Tailwind). Test Strategy refined to 12–16 tests with concrete file targets.
- 2026-05-09 user directive: scope cut — all FE work deferred to a separate design pass. Roadmap refactored to 3 active backend phases (schema/model, PhoneNormalizer, cascade gating); 3 deferred FE phases tracked in Live-Dogfood-Pending Tracker. Test Strategy reduced to 8–11 backend-only tests.
- /rai-build Phase 1 (2026-05-09): branch `feature/FEAT-006-ccd-contact-self-verification` created from main; planning + creative committed (6a12ddb); migration `RemoveDisplayNameFromContactsAndAddIdentityFields` ran (drop `display_name`, add `first_name`/`last_name`/`phone`); Contact model gained `encrypts :phone`, `verified?`, `:verified`/`:unverified` scopes, `nullify_blank_identity_fields` callback; factory got `:verified`/`:unverified` traits; 19 model specs added (verified? matrix, scope inverses, phone encryption round-trip, blank-to-nil); 401 total specs green; rubyfmt --check exits 0; phase committed (af9c745).
- /rai-build Phase 2 (2026-05-09): `Contacts::PhoneNormalizer` PORO module-function (US-only E.164, ~6 lines of logic). Strips formatting, accepts 10-digit/11-digit-1/+1, returns nil for non-US shapes. 10 specs cover the contract. Phase committed (9a01d5d).
- /rai-build Phase 3 (2026-05-09): Filter unverified Contact emails out of `EscalationCascade.fallback_emails_for`. One bounded query per cascade evaluation; raw legacy emails pass through; verified contacts pass through. Filtering also flows through the gm_nudge `fallback_chain` payload, so unverified contacts are not CC'd on the GM nudge either. 3 new specs (skip-unverified, raw-passthrough, gm_nudge consistency). 414 total specs green; rubyfmt --check exits 0; phase committed (3af0344).
- All active backend phases COMPLETE. STOPPED for human review. Three deferred FE items remain in Live-Dogfood-Pending Tracker for a separate design pass.
