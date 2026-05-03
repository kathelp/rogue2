# Product Roadmap

## Summary

- **Total Features**: 1
- **Released Versions**: 0
- **Active Version**: none — `next` is the only version

## Versions

### next (Planning)

- **Status**: planning
- **Description**: Backlog for features pending version assignment. Features are added here on creation and moved into a numbered version when scope and target date firm up.
- **Features**:
  - FEAT-001: Tenant + GM Email-First Onboarding (planned) [Level 4]

## Features

### FEAT-001: Tenant + GM Email-First Onboarding

- **Version**: next
- **Status**: planned
- **Priority**: high
- **Complexity**: Level 4
- **Description**: End-to-end email-first onboarding for a new dealer rooftop. Rogue staff seed a Tenant (dealership name, GM name, GM email); Rogue sends a single-click confirmation email. After confirm, the GM receives a paced sequence of single-question emails — one responsibility at a time, spaced over days — phrased in business vocabulary ("Who controls your marketing strategy?"). The GM replies and CC's the responsible party, with first CC = primary accountable, subsequent CCs = fallbacks, no-CC reply = self-assignment, and `skip` = defer. Each parsed reply triggers vendor inference against the canonical (pre-seeded) Vendor roster, creates the relevant Source and Request records with platform-default cadences, sends in-thread acknowledgment to the GM, and dispatches setup-email magic links to each named contact. Accountability for the GM is delivered to the inbox: weekly digest of all responsibilities and status, plus event-triggered emails for escalations and persistent failures. A magic-link web view of the accountability dashboard exists for GMs who want to drill in but is never required. Establishes the foundational data model (Tenant, Source, Request, Responsibility, Vendor, Question Catalog), the Action Mailbox routing and reply-parser pipeline, the question-pacing scheduler, and digest delivery — the foundation every other feature builds on.
- **Linked Tasks**:
  - TASK-001: Tenant + GM Email-First Onboarding (planned)
- **Branch**: feature/FEAT-001-tenant-gm-email-onboarding
- **Created**: 2026-05-03
