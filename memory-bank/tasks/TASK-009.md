# TASK-009: Cc'd Contact Self-Verification — FE pass

**Complexity**: Level 3 (inherited from FEAT-006)
**Status**: PLANNED
**Roadmap**: FEAT-006
**Branch**: feature/FEAT-006-self-verification-fe (to be created from main)
**Worktree**: N/A
**Docs Opt-In**: no
**Docs Opt-In Reason**: no Docusaurus tree at docs/
**Marketing Opt-In**: no
**Marketing Opt-In Reason**: no marketing schema at db/seeds/marketing/

## Task Description

The front-end pass for FEAT-006 that was scope-cut from TASK-008. Backend is shipped and merged (Contact identity fields, `verified?` predicate, `Contacts::PhoneNormalizer`, cascade gating on unverified). This task lands the user-facing surface: the identity-step view, the controller branch that handles it, the edited setup invitation email, and the end-to-end system spec that proves the loop closes.

The design is fully resolved in `memory-bank/creative/TASK-008-uiux.md` — single-column inline-CSS form, Step 1 of 4, field-level errors via `@errors` hash + `aria-describedby`, no JS. Email copy + exact ERB are spec'd verbatim. This task implements that spec; it does not redesign anything.

## Design Source

- **Primary**: `memory-bank/creative/TASK-008-uiux.md` — exact ERB for `identity.html.erb`, full mailer copy (subject + HTML + text), step-counter table, error states, empty-responsibility branch, done-greeting edit. The "Implementation Guidelines / For Developers" section is the build checklist.
- **Supporting**: `memory-bank/creative/TASK-008-user-journey.md` (Q1 trigger = inline in setup walkthrough as Step 1 of 4) and `memory-bank/creative/TASK-008-architecture.md` (Q4 = `Contacts::PhoneNormalizer::Result` struct shape).

## Forward Debt — Address Before Phase 1

Per the TASK-008 archive "Forward Debt" section, `Contacts::PhoneNormalizer.call` currently returns `nil` or a `String`. The UI/UX doc's controller pseudocode and the architecture doc both reference `phone_result.valid?` on a `Result` struct. **Phase 0** of this task refactors the normalizer to match the documented contract before any controller branch consumes it — preferred path per `_learned/service-shape.md`.

## Acceptance Criteria

Carried forward from the TASK-008 spec, deferred at archive:

### AC-ENTRY-1: Setup-email subject + body reflect the new "name + phone + method" framing
**Priority**: MUST
**Given** a CC'd contact receives `OnboardingMailer#invitee_setup_email`
**When** the rendered email is inspected (HTML and plain-text)
**Then** subject = `"<Dealership>: set up your details and how you'll send data"`; body matches the templates in UI/UX Sub-Decision 1 (asks about ~1 minute, "confirm your name and phone number, then pick how you want to send data"); CTA copy = `"Set up your assignment"`.

### AC-HAPPY-1: Unverified contact completes identity step
**Priority**: MUST
**Given** a contact with an unexpired `:invitee_setup` signed link and `verified? == false`
**When** they GET `/setup/:signed_id` and submit a valid `first_name`, `last_name`, and US phone number via PATCH (scope `:contact`)
**Then**:
  - The `Contact` is updated; `contact.verified? == true`
  - A `FlowEvent` is recorded inside the same transaction (event type `contact.verified`)
  - The contact is redirected to `step=summary` (Step 2 of 4)
  - On subsequent GETs (re-clicking the link), the controller skips `:identity` and renders `:summary` directly (idempotent re-entry)

### AC-ERROR-1: Validation errors render inline; record is not mutated
**Priority**: MUST
**Given** a contact at the identity step
**When** they submit with any of: blank `first_name`, blank `last_name`, blank or non-US-parseable `phone`
**Then**:
  - Response is HTTP 422; the `:identity` view re-renders with field-specific error text above each failing input (text per UI/UX Sub-Decision 5 Validation error messages)
  - Failing inputs gain `aria-invalid="true"` and an `aria-describedby` pointing at the error `<p>`'s id
  - Failing input borders render in `#c00`; error text in `#800`
  - The `Contact` record is NOT updated; no `FlowEvent` is written
  - Submitted `first_name` / `last_name` re-populate from `@contact.assign_attributes`; raw phone attempt re-populates from `@phone_attempt` ivar (not from `@contact.phone`, which is encrypted)

### AC-LINK-1: Existing `:invitee_setup` signed-link guarantees preserved
**Priority**: MUST
**Given** an expired, tampered, or substituted `:invitee_setup` signed_id
**When** the contact GETs or PATCHes `/setup/:signed_id`
**Then** the existing `:expired` view renders with HTTP 404 — no new vulnerability introduced by the identity branch. (Same behavior as before; new branch must NOT bypass `load_contact`.)

### AC-INTEGRATION-1: System E2E — GM reply → CC promotion → identity step → cascade gating activates
**Priority**: MUST
**Given** the full pipeline from `OnboardingMailbox#handle_assignment`
**When** a GM reply CCs a new contact, the contact clicks the setup link, completes identity, and the cascade later fires for a missed prompt
**Then** the cascade's `fallback_emails_for` now INCLUDES that contact's email (because they are verified). Pre-verification, the same cascade would have filtered them out. One system spec covers the round-trip.

## Scope Boundaries

**In scope:**
- Refactor `Contacts::PhoneNormalizer` to return `Contacts::PhoneNormalizer::Result` struct with `:normalized` (E.164 string or nil) and `:valid?` (Boolean). Existing 10 specs updated accordingly.
- New view `app/views/setup/walkthroughs/identity.html.erb` (exact ERB per UI/UX Sub-Decision 2).
- `Setup::WalkthroughsController` extension:
  - `template_for_step`: render `:identity` first when `@contact.unverified?` (unless the step query param explicitly requests a later step that's still valid for an unverified contact — see UI/UX flow diagram).
  - `update`: branch on `params.key?(:contact)`. Identity branch builds `@errors` hash, calls `PhoneNormalizer`, writes Contact + FlowEvent in one transaction, redirects to `step=summary` on success.
- View edits (one line each):
  - `summary.html.erb:8` — `Step 1 of 3` → `Step 2 of 4`
  - `method_picker.html.erb:8` — `Step 2 of 3` → `Step 3 of 4`
  - `done.html.erb` — first-name greeting per UI/UX Sub-Decision 5
  - `summary.html.erb` empty-responsibility else-branch — refresh copy; wrap Continue link in `<% if @responsibility %>`
- Mailer edits:
  - `app/mailers/onboarding_mailer.rb` — subject line for `invitee_setup_email`
  - `app/views/onboarding_mailer/invitee_setup_email.html.erb` — body
  - `app/views/onboarding_mailer/invitee_setup_email.text.erb` — body
- `FlowEvent` writes for `contact.verified` (and optional `contact.invitation_revisited` — defer unless cheap).
- System spec covering AC-INTEGRATION-1.
- Letter-opener manual verification of the edited email (not codified; one-line entry in the build phase commit body confirming it was eyeballed).

**Out of scope:**
- Twilio SMS, phone provider integration, any actual texting.
- Re-prompt cadence (Q5 decided as "none at MVP" in TASK-008 creative; piggybacks on 7-day setup link expiry).
- Verification email separate from setup email (Q1 decided as Option B — inline in setup walkthrough).
- Admin UI for viewing verification status.
- Retroactive backfill of pre-FEAT-006 contacts.
- New `class=""` attributes or Tailwind — UI/UX doc explicitly forbids; codebase uses inline styles only.

**Dependencies:**
- TASK-008 (archived 2026-05-09) — `Contact` identity fields, `verified?` predicate, `:verified`/`:unverified` scopes, `encrypts :phone`, `Contacts::PhoneNormalizer`, cascade gating.
- FEAT-001 / TASK-001 — `OnboardingMailer#invitee_setup_email` exists with current copy; this task edits subject + both templates.

## Test Strategy

### Approach
- **Emphasis**: full-stack — model contract (Result struct), controller branches, mailer subject + body content, system E2E.
- **Target test count**: 14–18 new specs.

### File Organization

**Modified:**
- `spec/services/contacts/phone_normalizer_spec.rb` — rewrite 10 specs against Result struct (`.normalized`, `.valid?`)
- `spec/mailers/onboarding_mailer_spec.rb` — extend `invitee_setup_email` specs for new subject + body copy

**New:**
- `spec/requests/setup/walkthroughs_spec.rb` — identity branch happy path (PATCH `:contact`), validation errors (3 fields × blank/invalid), re-entry idempotency after verified, expired-signed-id passthrough (unchanged behavior, regression guard)
- `spec/system/contact_self_verification_spec.rb` — AC-INTEGRATION-1 E2E spec

### Per-Phase Test Guidance
- **Phase 0** (PhoneNormalizer refactor): rewrite 10 existing specs; no new test count.
- **Phase 1** (identity step controller + view): ~8 request specs.
- **Phase 2** (mailer edits): ~3 mailer spec additions (subject, body asserts, plain-text body assert).
- **Phase 3** (system spec + letter-opener): 1 system spec.

### What NOT to Test
- Rails framework concerns (signed_id crypto, ActionMailer SMTP).
- `Contact#verified?` predicate matrix — TASK-008 already covers.
- Cascade gating logic — TASK-008 already covers; system spec asserts integration only.

## Implementation Roadmap

- [x] **Phase 0: `Contacts::PhoneNormalizer::Result` struct** — COMPLETE 2026-05-10. Refactored `Contacts::PhoneNormalizer.call` to return `Result = Struct.new(:normalized, :valid?, keyword_init: true)`. Implementation matches the architecture doc's prescribed shape exactly (no doc edit needed). 13 specs now assert against the struct (`.normalized` + `.valid?`). Full suite green: 424 examples, 0 failures. `rubyfmt --check` exits 0 globally. No callers existed yet — purely contract-shaping change ahead of Phase 1.

- [x] **Phase 1: Identity step (controller + view + ancillary view edits)** — COMPLETE 2026-05-10. New `app/views/setup/walkthroughs/identity.html.erb` per UI/UX Sub-Decision 2 (Step 1 of 4, single-column inline-CSS, aria-described errors above each input, phone hint always visible). `Setup::WalkthroughsController` gained `template_for_step` identity route (`return :identity if @contact.unverified?` after the resume short-circuit) and a `handle_identity_update` branch in `update` that builds an `@errors` hash, calls `Contacts::PhoneNormalizer`, and on success transacts `Contact.update! + FlowEvent.record!(event_type: "contact.verified")` and redirects to `step=summary`. Step-counter edits in `summary.html.erb` (now Step 2 of 4) and `method_picker.html.erb` (Step 3 of 4). `done.html.erb` greets by first name. Empty-responsibility branch on `summary.html.erb` refreshed with the "Your details are saved, X" copy and Continue link wrapped in `<% if @responsibility %>`. Added `Contact#unverified?` instance predicate to mirror `verified?`. Updated the existing FEAT-001 system spec (`gm_email_first_onboarding_full_loop_spec.rb`) to walk the identity step (Alex now fills in name + phone before the assignment summary). Spec body: 18 new request specs (33 total in the file, was 15). Full suite: **442 / 442 passing**. `rubyfmt --check` exits 0 globally.

- [x] **Phase 2: `OnboardingMailer#invitee_setup_email` edits** — COMPLETE 2026-05-10. Subject changed from `"<Dealership>: data collection assignment"` to `"<Dealership>: set up your details and how you'll send data"` (UI/UX Sub-Decision 1). Both `invitee_setup_email.html.erb` and `.text.erb` replaced per UI/UX Sub-Decision 1 verbatim — heading unchanged; body says "asked you to handle this" (was "named you as the person to handle this"), "It takes about a minute. You'll confirm your name and phone number, then pick how you want to send data." (was "To finish setup..."), CTA "Set up your assignment" (was "Set up data collection"), and a small-print reassurance line "No password or account needed — just your name, phone, and a submission preference." Two parallel specs (mailbox + system) updated to find the email by the new subject. Mailer spec gained 4 new assertions (CTA, ~1-minute language in HTML, ~1-minute language in text, "name and phone" framing). Rendered output eyeballed via `bin/rails runner` — text body matches the doc verbatim, conductor-reply dev link (TASK-006) auto-fills the new subject correctly. Full suite **444/444** green. `rubyfmt --check` exits 0 globally.

- [ ] **Phase 3: System E2E spec + final verification** — `spec/system/contact_self_verification_spec.rb` exercises AC-INTEGRATION-1: simulate a GM reply landing in `OnboardingMailbox#handle_assignment`, contact created unverified, click setup link, complete identity, then verify the next cascade evaluation includes their email in `fallback_emails_for`. Capybara-driven end-to-end. Full suite expected to be ~430–435 specs, 0 failures, `rubyfmt --check` exits 0 globally.

### Cross-phase invariants
- All `Contact` mutations are atomic with `FlowEvent.record!` inside the same DB transaction.
- Identity-form re-submit is safe (last-write-wins; FlowEvent is guarded so a re-verify on the same contact does not double-write — use `find_or_create_by` or a presence check).
- No new `class=""` attributes; inline-CSS only.
- Run `rubyfmt` on every Ruby file touched at end of each phase before commit (project rule per `feedback_rubyfmt.md`).

## Open Questions

None — all five resolved in TASK-008's `/rai-creative` (preserved in the three creative docs). One small decision baked into Phase 0: the `Result` struct field name. UI/UX doc says `phone_result.valid?`; using `:valid?` as a struct member produces a method name that ends in `?` — that's valid Ruby and idiomatic for predicate-shaped struct accessors. Equivalent style: `Struct.new(:normalized, :valid?, keyword_init: true)`.

## Live-Dogfood-Pending Tracker

| Item | Phase | Owner | Target | Resolution |
|------|-------|-------|--------|------------|
| (none) | — | — | — | — |

---

## Execution State

**Build Status**: PHASE_COMPLETE (Phase 2)
**Current Build**: Phase 2: OnboardingMailer#invitee_setup_email edits — COMPLETE
**Build Started**: 2026-05-10
**Phase Number**: 2 of 4 (labelled 0,1,2,3); next phase = Phase 3 (system E2E spec covering AC-INTEGRATION-1: GM reply → CC promotion → identity step → cascade gating activates)
**Is Multi-Phase**: YES
**Current Phase**: BUILD
**Current Step**: Phase 2 complete; STOPPED for human review before Phase 3
**Step Started**: 2026-05-10
**Can Resume**: YES

### Active Sub-Agents
(none — lighter route, direct execution)

### Completed Steps
- 2026-05-10: TASK-009 task file created (lighter route, design source = TASK-008 creative docs)
- 2026-05-10: Roadmap link confirmed → FEAT-006 (status: backend complete, FE pass = this task)
- 2026-05-10: Branch name decided: `feature/FEAT-006-self-verification-fe` (from main; original FEAT-006 backend branch left untouched at its archived state)
- 2026-05-10: Branch `feature/FEAT-006-self-verification-fe` created; planning commit c432a1d
- 2026-05-10: /rai-build TASK-009 invoked — Phase 0 started, lighter route (direct execution)
- 2026-05-10: Phase 0 — refactored `Contacts::PhoneNormalizer.call` to return `Result = Struct.new(:normalized, :valid?, keyword_init: true)` per architecture doc. Spec rewritten to assert on `.normalized` and `.valid?` (13 examples, was 10 — split the single blank-input it-block into three separate specs for nil/empty/whitespace + added a struct-type assertion). Full suite 424/424 green. `rubyfmt --check` exits 0 globally.
- 2026-05-10: Phase 1 — implemented identity step. New `identity.html.erb` (UI/UX Sub-Decision 2 verbatim), controller `template_for_step` identity branch + `handle_identity_update` in `update`, three ancillary view edits (summary/method_picker step counters, done first-name greeting, summary empty-responsibility else-branch refresh + Continue gating). Added `Contact#unverified?` instance predicate (mirrors `verified?`). Updated FEAT-001 full-loop system spec to walk the new identity step. 18 new request specs (33 total in `walkthroughs_spec.rb`, was 15). Full suite **442 / 442** green. `rubyfmt --check` exits 0 globally.
- 2026-05-10: Phase 2 — updated `OnboardingMailer#invitee_setup_email` subject + both body templates per UI/UX Sub-Decision 1. Subject: `"<Dealership>: set up your details and how you'll send data"` (was `"...: data collection assignment"`). HTML + text bodies replaced verbatim from the UI/UX doc (CTA "Set up your assignment", ~1-minute language, name+phone framing, "no password or account needed" reassurance). Mailer spec extended (+4 assertions: CTA, HTML ~1-minute language, text ~1-minute language, "name and phone" phrase). Two collateral specs that looked up the email by old subject text updated: `onboarding_mailbox_spec` and the FEAT-001 full-loop system spec. Manually eyeballed via `bin/rails runner` — output renders correctly; conductor-reply dev link auto-fills the new subject. Full suite **444 / 444** green. `rubyfmt --check` exits 0 globally.
