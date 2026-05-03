# Product Roadmap

## Summary

- **Total Features**: 2
- **Released Versions**: 0
- **Active Version**: none — `next` is the only version

## Versions

### next (Planning)

- **Status**: planning
- **Description**: Backlog for features pending version assignment. Features are added here on creation and moved into a numbered version when scope and target date firm up.
- **Features**:
  - FEAT-001: Tenant + GM Email-First Onboarding (complete, archived 2026-05-03) [Level 4]
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
