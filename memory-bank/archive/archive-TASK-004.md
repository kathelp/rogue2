# Archive: TASK-004 — Escalation Refinements

## Metadata
- **Task ID**: TASK-004
- **Roadmap Link**: FEAT-005
- **Complexity**: Level 2
- **Started**: 2026-05-08
- **Completed**: 2026-05-08 (single-session, single-phase build)
- **Final state**: 394 RSpec examples / 0 failures / 0 RuboCop offenses
- **Phase commits**: forthcoming on branch `feature/FEAT-005-escalation-refinements`.

## Summary

Three small additive refinements to the FEAT-004 escalation cascade, shipped as a single-phase Level 2 build:

1. **Per-tenant grace window overrides** — four new optional integer columns on `tenants`. The cascade reads tenant first, falls back to module defaults. Backward-compatible (every existing tenant unaffected).
2. **Per-severity body partials** — replaced the single `case @severity` ERB block with four severity-specific partials (× 2 formats). Tone progression: friendly → firmer → urgent fallback context → executive.
3. **Status badges** — new `AccountabilityHelper#status_badge` returns inline-styled spans, wired into the digest email and the dashboard placeholder. Palette: green (on_time), gray (pending), amber (late), red (overdue).

## Requirements

### Original Requirements
- Per-tenant grace window overrides (with module-default fallback).
- Per-severity escalation copy.
- Visual status indicators in the digest + dashboard.

### Success Criteria
- [✓] AC-OVERRIDE-1: tenant override applies in the cascade.
- [✓] AC-OVERRIDE-2: nil override falls back to module defaults.
- [✓] AC-COPY-1: per-severity headlines render as expected.
- [✓] AC-BADGE-1: digest renders inline-colored badges.
- [✓] AC-BADGE-2: dashboard renders inline-colored badges.

## Implementation

### Approach

Single phase given Level 2 + small additive scope.

### Key Components

1. **Migration `20260508120000_add_escalation_grace_days_to_tenants`** — adds 4 optional integer columns: `escalation_due_soon_grace_days`, `escalation_overdue_grace_days`, `escalation_fallback_grace_days`, `escalation_gm_grace_days`.
2. **`OnboardingFlow::EscalationCascade`** — `next_action_for` now resolves the four grace-day values via `tenant.escalation_*_days || MODULE_DEFAULT`. Both Date-math (due_soon / overdue) and Time-math (fallback / gm_nudge) thresholds use the resolved values.
3. **`EscalationMailer` partials** — `escalation_email.html.erb` + `.text.erb` now render `<%= render partial: @severity.to_s %>`. Four pairs of partials (`_due_soon`, `_overdue`, `_fallback_fanout`, `_gm_nudge`) carry severity-specific copy.
4. **`AccountabilityHelper#status_badge(status)`** — returns an inline-styled `<span>`. Color palette in `STATUS_BADGES` constant. Graceful fallback for unknown statuses (humanizes the symbol).
5. **`AccountabilityMailer`** declares `helper AccountabilityHelper` so the digest view can call `status_badge`. Dashboard view picks up the helper automatically (controller-bound).
6. **Views** — `weekly_digest.html.erb` and `dashboards/show.html.erb` simplified: status column is now `<%= status_badge(row.status) %>` (was a 7-line `case`).

### Design Decisions

No formal `/rai-creative` phase. Spec flagged no LOW-confidence areas. The MEDIUM-confidence question (single template with `case @severity` vs. partials per severity) was resolved at planning time toward partials — future per-severity copy refinements will edit a single 5-line partial rather than a growing `case` block.

## Testing

- **Unit**: 6 helper specs (`AccountabilityHelper#status_badge` covering 5 statuses + unknown fallback).
- **Service**: 3 new cascade specs (per-tenant overrides for due_soon, overdue, and nil-default fallback).
- **Mailer**: 4 new escalation_mailer specs (per-severity headline differentiation); 1 new accountability_mailer spec (digest renders status badge span with color).
- **Request**: 1 new dashboards spec (badge span with color in HTML response).

**Total added**: 15 specs. **Final suite**: **394 examples, 0 failures.**

## Files Changed

### App code
- `app/helpers/accountability_helper.rb` (new) — `status_badge` helper.
- `app/mailers/accountability_mailer.rb` — `helper AccountabilityHelper` declaration.
- `app/services/onboarding_flow/escalation_cascade.rb` — tenant-override resolution.
- `app/views/accountability_mailer/weekly_digest.html.erb` — status column → `status_badge`.
- `app/views/dashboards/show.html.erb` — status column → `status_badge`.
- `app/views/escalation_mailer/escalation_email.html.erb` + `.text.erb` — replaced `case` block with `render partial: @severity.to_s`.
- `app/views/escalation_mailer/_due_soon.{html,text}.erb` (new × 2)
- `app/views/escalation_mailer/_overdue.{html,text}.erb` (new × 2)
- `app/views/escalation_mailer/_fallback_fanout.{html,text}.erb` (new × 2)
- `app/views/escalation_mailer/_gm_nudge.{html,text}.erb` (new × 2)

### Migration
- `db/migrate/20260508120000_add_escalation_grace_days_to_tenants.rb`

### Specs
- `spec/helpers/accountability_helper_spec.rb` (new)
- `spec/mailers/accountability_mailer_spec.rb` (extended)
- `spec/mailers/escalation_mailer_spec.rb` (extended)
- `spec/requests/dashboards_spec.rb` (extended)
- `spec/services/onboarding_flow/escalation_cascade_spec.rb` (extended)

### Memory bank
- `memory-bank/roadmap.md` — FEAT-005 added.
- `memory-bank/tasks.md` — TASK-004 row added.
- `memory-bank/tasks/TASK-004.md` — full spec + plan.
- `memory-bank/archive/archive-TASK-004.md` — this document.

## Lessons Learned

- **`helper :something_helper` declaration is required for Action Mailer** — controller views auto-include helpers, but mailer views don't unless explicitly declared. Caught at view-render time when the spec hit `NoMethodError: undefined method 'status_badge'`. (Captured here rather than reflection — Level 2 doesn't get a separate reflection doc.)
- **Helper specs need `type: :helper`** — RSpec's `helper.method_name` accessor only works when the spec is recognized as a helper spec. The `spec/helpers/` directory doesn't auto-tag in this project's `rails_helper.rb`, so the `type:` annotation is needed inline.
- **Replacing inline `case` with partials is a clear win** — moves presentation logic out of the controller-template and into named files, makes diffs of copy changes review-friendly, and removes the temptation for partial logic to grow.

## References

- **Plan**: `memory-bank/tasks/TASK-004.md`
- **Roadmap**: `memory-bank/roadmap.md` → FEAT-005
- **Phase commits**: forthcoming.

## Follow-up

- **Per-Responsibility grace window overrides** — currently per-tenant. If specific responsibilities need their own cadence (e.g., the GM wants tighter escalation for OEM compliance), add columns to `responsibilities` and have the cascade prefer them. FEAT-006.
- **Tenant-customizable copy / palette** — currently fixed. Worth revisiting if enterprise tenants want their own brand voice. FEAT-006+.
- **Web UI for tuning escalation_*_days** — currently Rails console / ENV / SQL. An admin UI surface lands when admin tooling expands.
