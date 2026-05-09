# Product Roadmap

## Summary

- **Total Features**: 6
- **Released Versions**: 0
- **Active Version**: none — `next` is the only version

## Versions

### next (Planning)

- **Status**: planning
- **Description**: Backlog for features pending version assignment. Features are added here on creation and moved into a numbered version when scope and target date firm up.
- **Features**:
  - FEAT-001: Tenant + GM Email-First Onboarding (complete, archived 2026-05-03) [Level 4]
  - FEAT-002: Submission Prompt Sender (complete, archived 2026-05-03) [Level 3]
  - FEAT-004: Escalation Cascade (complete, archived 2026-05-03) [Level 3]
  - FEAT-005: Escalation Refinements (complete, archived 2026-05-08) [Level 2]
  - FEAT-006: Cc'd Contact Self-Verification (planned) [Level 3]
  - FEAT-Ops-Cutover: Production email ingress, outbound provider, raw-payload archive (planned) [Level 2]

## Features

### FEAT-001: Tenant + GM Email-First Onboarding

- **Version**: next
- **Status**: complete (archived 2026-05-03)
- **Archive**: memory-bank/archive/archive-TASK-001.md
- **Priority**: high
- **Complexity**: Level 4
- **Description**: End-to-end email-first onboarding for a new dealer rooftop. Rogue staff seed a Tenant (dealership name, GM name, GM email); Rogue sends a single-click confirmation email. After confirm, the GM receives a paced sequence of single-question emails — one responsibility at a time, spaced over days — phrased in business vocabulary ("Who controls your marketing strategy?"). The GM replies and CC's the responsible party, with first CC = primary accountable, subsequent CCs = fallbacks, no-CC reply = self-assignment, and `skip` = defer. Each parsed reply triggers vendor inference against the canonical (pre-seeded) Vendor roster, creates the relevant Source and Request records with platform-default cadences, sends in-thread acknowledgment to the GM, and dispatches setup-email magic links to each named contact. Accountability for the GM is delivered to the inbox: weekly digest of all responsibilities and status, plus event-triggered emails for escalations and persistent failures. A magic-link web view of the accountability dashboard exists for GMs who want to drill in but is never required. Establishes the foundational data model (Tenant, Source, Request, Responsibility, Vendor, Question Catalog), the Action Mailbox routing and reply-parser pipeline, the question-pacing scheduler, and digest delivery — the foundation every other feature builds on.
- **Linked Tasks**:
  - TASK-001: Tenant + GM Email-First Onboarding (planned)
- **Branch**: feature/FEAT-001-tenant-gm-email-onboarding
- **Created**: 2026-05-03

### FEAT-002: Submission Prompt Sender

- **Version**: next
- **Status**: complete (archived 2026-05-03)
- **Archive**: memory-bank/archive/archive-TASK-002.md
- **Priority**: high (closed the half-shipped TASK-001 loop; SubmissionPrompt rows now get sent and captured)
- **Complexity**: Level 3
- **Description**: Closes the loop on TASK-001's invitee setup walkthrough. Phase 5 of TASK-001 wrote `submission_prompts` rows scheduled at the start of the next reporting period; Phase 6 surfaced them on the digest as "Pending first submission." This feature ships the recurring sender that finds due prompts, the `SubmissionMailer#prompt_email` that delivers them with a magic-link, and the `Submissions::FormsController` + `Submission` model that captures the data the GM expects on the cadence the catalog defines. Submission status updates the digest's per-row state (`pending_first_submission` → `on_time` / `late` / `overdue`). Restricted to `submission_method: form` at MVP; CSV/API adapter generation is deferred to FEAT-003. Audit trail via `FlowEvent.record!` for `submission.prompt_sent`, `submission.captured`, `submission.prompt_overdue`.
- **Linked Tasks**:
  - TASK-002: Submission Prompt Sender (complete)
- **Branch**: feature/FEAT-002-submission-prompt-sender (merged 2026-05-03; deleted)
- **Created**: 2026-05-03

### FEAT-004: Escalation Cascade

- **Version**: next
- **Status**: complete (archived 2026-05-03)
- **Archive**: memory-bank/archive/archive-TASK-003.md
- **Priority**: high (completed the accountability loop — late and overdue prompts now surface to fallback contacts and the GM)
- **Complexity**: Level 3
- **Description**: When a SubmissionPrompt reaches its `:sent` status but no Submission lands within the configured grace windows, the escalation cascade fires — graduated severity from "due-soon" reminder (3 days before period close) to "overdue" notice (3 days past) to "fallback fan-out" (notifies the responsibility's ordered `fallback_contact_emails`) to "GM nudge" (when no fallbacks left or all already notified). Severity is computed as a pure function of `(prompt.scheduled_for, period_end, current_time, fallbacks_already_notified)` so the recurring detector job is stateless. Each escalation event is recorded as a `FlowEvent` with severity in the payload — re-runs check the FlowEvent log for "have we already notified at this severity?" rather than maintaining a separate state column on the prompt. Builds the foundation for the productBrief's "graduated escalation" guarantee. Note: numbered FEAT-004 (not FEAT-003) to leave the FEAT-003 slot for AI-assisted adapter generation, the next major Level-4 feature on the productBrief OOS list.
- **Linked Tasks**:
  - TASK-003: Escalation Cascade (complete)
- **Branch**: feature/FEAT-004-escalation-cascade (merged 2026-05-03; deleted)
- **Created**: 2026-05-03

### FEAT-005: Escalation Refinements

- **Version**: next
- **Status**: complete (archived 2026-05-08)
- **Archive**: memory-bank/archive/archive-TASK-004.md
- **Priority**: medium (UX polish on FEAT-004; not load-bearing for any other feature)
- **Complexity**: Level 2
- **Description**: Three additive refinements to the FEAT-004 escalation cascade:
  1. **Per-tenant grace window overrides.** Move `DUE_SOON_GRACE_DAYS` / `OVERDUE_GRACE_DAYS` / `FALLBACK_GRACE_DAYS` / `GM_GRACE_DAYS` from module constants to four optional `tenants` columns. The cascade reads tenant first, falls back to module defaults. Lets enterprise tenants tune the cadence to their reporting culture.
  2. **Per-severity body copy.** Replace the single `escalation_email.html.erb` `case @severity` block with four severity-specific partials. Tone progression: friendly nudge (due_soon) → firmer (overdue) → urgent + names-the-fallback (fallback_fanout) → executive escalation that names the contact chain (gm_nudge).
  3. **Status badges in the digest.** Color/iconify the per-row status column in `AccountabilityMailer#weekly_digest` and `DashboardsController#show`: green for on_time, gray for pending_setup / pending_first_submission, amber for late, red for overdue.
- **Linked Tasks**:
  - TASK-004: Escalation Refinements (complete)
- **Branch**: feature/FEAT-005-escalation-refinements (merged 2026-05-08; deleted)
- **Created**: 2026-05-08

### FEAT-006: Cc'd Contact Self-Verification

- **Version**: next
- **Status**: planned
- **Priority**: medium
- **Complexity**: Level 3
- **Description**: When new users are onboarded from being cc'd on an email, we should ask them to enter their first name, last name, and phone number to complete their account verification. Today, contacts promoted into the system via a GM CC arrive with little more than an email address; this feature closes that gap by giving the contact a self-service step to fill in their identity and phone before they're treated as a fully-onboarded responsibility holder. **Decided:** verification status is *derived* from field presence — a contact is "unverified" while any of `first_name`, `last_name`, or `phone` is blank, and "verified" once all three are populated. No separate `verified_at` timestamp or state machine; the columns are the source of truth. Open design questions to resolve in `/rai-creative`: (1) **Trigger** — verification email with signed-link landing page, inline prompt on the next setup-email click-through, or both? (2) **Gating semantics** — what specifically changes for an unverified contact? Candidate gates: pause submission prompts, suppress escalation fanout to them, hold them out of the GM's weekly digest until verified, mark them visually in admin views. (3) **Schema** — split the existing `Contact#name` into `first_name` / `last_name`, or keep `name` and add the new fields alongside? (4) **Phone handling** — validation/normalization (E.164 for future Twilio use). (5) **Re-prompt cadence** — what happens if the contact ignores the verification email; expire the link? Escalate to the GM? Note: Rogue's onboarding model treats `Contact` as the persona record; `Responsibility` is the accountability assignment. Verification belongs on `Contact`.
- **Linked Tasks**:
  - TASK-008: Cc'd Contact Self-Verification (planning)
- **Branch**: feature/FEAT-006-ccd-contact-self-verification
- **Created**: 2026-05-09

### FEAT-Ops-Cutover: Production email ingress, outbound provider, raw-payload archive

- **Version**: next
- **Status**: planned (carried forward from TASK-001 archive)
- **Priority**: medium (gates real GM dogfood; does not gate further feature work on local dev)
- **Complexity**: Level 2 (operational cutover; mostly DNS / provider config / Active Storage backend swap, no domain-model change)
- **Description**: Bundles the three platform-cutover items deferred from TASK-001's Live-Dogfood-Pending Tracker. None can be exercised on local dev — they require a real production environment (or a QA environment with real DNS + email provider accounts).
  1. **Production inbound email ingress provider + DNS.** Choose Postmark / Mailgun / SendGrid; provision MX for `inbound.rogue.example` (or the production domain); wire the inbound webhook to Action Mailbox's ingress endpoint; verify a real onboarding reply round-trips through the live pipeline (covers the AC-HAPPY-3 system test against a live ingress).
  2. **Production outbound email provider selection + warmup.** Choose the outbound provider; complete IP/domain warmup; verify threading reliability across real Gmail / Outlook / Apple Mail accounts; send a real `confirmation_email` and a real `question_email` to a live GM inbox and confirm the reply threads back via the inbound side.
  3. **Indefinite raw-payload archive in S3-class storage.** Swap Active Storage from local-disk to S3 (or the production storage class chosen at cutover); apply the retention policy; verify `ActionMailbox::InboundEmail` raw RFC 822 source persists across deploys.
- **Acceptance**: a real GM email address can complete the full TASK-001 loop (seed → confirm → first question → reply → ack + setup) in QA or production, with raw payloads retained in S3.
- **Linked Tasks**: (none yet — task to be created when QA / prod environment is ready)
- **Branch**: TBD (will be `feature/FEAT-Ops-Cutover-...` per branch naming)
- **Created**: 2026-05-03
