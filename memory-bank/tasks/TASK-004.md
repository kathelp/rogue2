# TASK-004: Escalation Refinements

**Complexity**: Level 2 (inherited from FEAT-005)
**Status**: COMPLETE
**Completed**: 2026-05-08
**Roadmap**: FEAT-005
**Branch**: feature/FEAT-005-escalation-refinements (merged + deleted at archive)
**Worktree**: N/A
**Archived**: memory-bank/archive/archive-TASK-004.md
**Docs Opt-In**: no
**Marketing Opt-In**: no

## Task Description

Three additive refinements to the FEAT-004 escalation cascade:

1. **Per-tenant grace window overrides.** Add four optional integer columns to `tenants`: `escalation_due_soon_grace_days`, `escalation_overdue_grace_days`, `escalation_fallback_grace_days`, `escalation_gm_grace_days`. `OnboardingFlow::EscalationCascade` reads tenant first; falls back to module-level defaults (3 / 3 / 4 / 5) when nil. Backward-compatible — every existing tenant uses defaults until explicitly tuned.
2. **Per-severity body partials.** Replace the single `escalation_email.html.erb` / `.text.erb` `case @severity` block with four severity-specific partials per format. Mailer renders the right partial based on `params[:severity]`. Tone progression: friendly (due_soon) → firmer (overdue) → urgent and naming the fallback (fallback_fanout) → executive escalation naming the contact chain (gm_nudge).
3. **Status badges in the digest + dashboard.** Add a small `status_badge` view helper that renders an inline-styled `<span>` with severity-appropriate background/text color. Wire it into the `accountability_mailer/weekly_digest.html.erb` table and `dashboards/show.html.erb` table.

**Explicit MVP boundaries:**
- Per-Responsibility grace window overrides are NOT in scope (only per-tenant). FEAT-006 if ever needed.
- Per-tenant tone customization is NOT in scope — every tenant gets the same severity-appropriate copy.
- Status badge palette is fixed (green / gray / amber / red); admin-customizable colors are not in scope.

## Specification

**Feature Type**: NFR / UX polish (touches the GM, Invited Contact, and fallback contact personas via existing email + dashboard surfaces).

**Primary Persona**: GM (per-tenant tuning) and the contacts (per-severity copy).

**Creative Exploration Needed**: No. All three refinements are mechanical extensions of existing components.

### Invocation Method

#### Per-tenant grace window
- **Location**: `Tenant.escalation_*_days` integer columns. Set via Rails console / future admin UI.
- **Outcome**: Cascade computes thresholds using tenant value when present, module default when nil.

#### Per-severity copy
- **Location**: `EscalationMailer#escalation_email` already exists; this just swaps the view.
- **Outcome**: Each severity renders its dedicated partial; subjects unchanged.

#### Status badges
- **Location**: digest email + `/dashboard/:signed_id`.
- **Outcome**: Each row's status column shows an inline-colored badge instead of plain text.

### Success Criteria

#### Per-tenant grace override
- **Given**: A tenant with `escalation_due_soon_grace_days = 5` (vs. default 3).
- **When**: A SubmissionPrompt is `:sent` and the cascade is queried.
- **Then**: `due_soon` fires 5 days before period_end, not 3.

#### Default-fallback behavior
- **Given**: A tenant with `escalation_due_soon_grace_days = nil` (default).
- **When**: Cascade is queried.
- **Then**: 3-day default applies.

#### Per-severity copy
- **Given**: Each of the 4 severities.
- **When**: `EscalationMailer#escalation_email` renders.
- **Then**: HTML body contains severity-appropriate copy (different headlines per severity).

#### Digest status badges
- **Given**: Digest email rendered for a tenant with rows in mixed states.
- **When**: HTML body is inspected.
- **Then**: Each status word is wrapped in a `<span>` with inline color styling.

### Acceptance Criteria

#### AC-OVERRIDE-1: Tenant override applies
**Priority**: MUST
- **Verification**: Service spec on `EscalationCascade` with custom-tenant grace days produces different threshold dates.

#### AC-OVERRIDE-2: Default fallback when nil
**Priority**: MUST
- **Verification**: Service spec confirms module defaults apply when tenant column is nil.

#### AC-COPY-1: Per-severity headline differentiation
**Priority**: MUST
- **Verification**: Mailer spec asserts each severity's HTML body contains its unique headline.

#### AC-BADGE-1: Status badges render in digest
**Priority**: MUST
- **Verification**: Mailer spec on `weekly_digest.html.erb` asserts the badge `<span>` includes color styling for the relevant status.

#### AC-BADGE-2: Status badges render on dashboard
**Priority**: SHOULD
- **Verification**: Request spec on `DashboardsController#show` asserts badge markup in response body.

### Scope Boundaries

#### In scope
- Migration adding 4 optional integer columns to `tenants`.
- `OnboardingFlow::EscalationCascade` reads tenant grace overrides (with module-default fallback).
- 4 partials × 2 formats = 8 new view files (`_due_soon.html.erb`, `_overdue.html.erb`, etc.) + their text counterparts.
- `app/helpers/accountability_helper.rb` with `status_badge` method.
- `weekly_digest.html.erb` and `dashboards/show.html.erb` updated to use the badge helper.
- Mailer / cascade specs extended to cover all branches.

#### Out of scope
- Per-Responsibility overrides (still tenant-wide).
- Tenant-customizable copy or palette.
- Web UI for adjusting grace windows (Rails console / future admin).

## Test Strategy

- **Test framework**: RSpec + FactoryBot (established).
- **Target**: ~12-15 new specs.
- **File organization**:
  - Extend `spec/services/onboarding_flow/escalation_cascade_spec.rb` (override tests).
  - Extend `spec/mailers/escalation_mailer_spec.rb` (per-severity body assertions).
  - Extend `spec/mailers/accountability_mailer_spec.rb` (badge assertions).
  - New `spec/helpers/accountability_helper_spec.rb`.
  - Extend `spec/requests/dashboards_spec.rb` (badge assertion).

## Implementation Roadmap

Single phase given Level 2 + small additive scope.

- [x] **Phase 1 — All three refinements** *(COMPLETE 2026-05-08)* (closes AC-OVERRIDE-1..2, AC-COPY-1, AC-BADGE-1..2)
  - Migration `20260508120000_add_escalation_grace_days_to_tenants` (4 nullable integer columns).
  - `OnboardingFlow::EscalationCascade.next_action_for` resolves grace days via `tenant.escalation_*_days || MODULE_DEFAULT`.
  - `EscalationMailer` renders `severity` partial; subject logic unchanged.
  - 4 HTML + 4 text partials in `app/views/escalation_mailer/`.
  - `AccountabilityHelper#status_badge(status)` returns inline-styled span.
  - Wire badge into `weekly_digest.html.erb` and `dashboards/show.html.erb`.
  - Spec extensions on cascade, escalation mailer, accountability mailer, helper, dashboards.
  - **Acceptance**: full suite green, 0 RuboCop offenses, all 5 ACs verified.

## Live-Dogfood-Pending Tracker

(none — fully exercisable on local dev.)

---

## Execution State

**Build Status**: IDLE
**Current Phase**: COMPLETE
**Last Completed**: Archive (2026-05-08)
**Can Resume**: NO — task closed.
