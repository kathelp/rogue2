# Archive: TASK-007 — gm_nudge emails CC the full responsibility chain

## Metadata

- **Task ID**: TASK-007
- **Roadmap Link**: N/A (Level 1)
- **Complexity**: Level 1
- **Started**: 2026-05-09
- **Completed**: 2026-05-09
- **Archived**: 2026-05-10
- **Final state**: 398 RSpec examples / 0 failures
- **Branch**: `task/007-gm-nudge-cc-responsible-parties` (merged into `main` via `c34674c`, task commit `5f9c2d4`)

## Summary

The `gm_nudge` rung of the escalation cascade now CCs every responsible party (the active Responsibility's `primary_contact` plus `fallback_contact_emails`). Earlier rungs are unchanged — they remain single-recipient. The GM can now reply-all from the final escalation email to lean on the people who were supposed to deliver, instead of forwarding manually.

## Solution

- `OnboardingFlow::EscalationCascade` emits `primary_email` in the `gm_nudge` `NextAction` payload alongside the existing `fallback_chain`. Sources the email from the **active Responsibility's primary_contact** (the person the GM said is on the hook), not `source.configured_by_contact` (which tracks the setup-clicker — usually the same person but diverges after reassignment).
- `EscalationMailer#cc_for(severity, payload, recipient)` builds the CC list for `:gm_nudge` as `[primary_email, *fallback_chain].compact.uniq`, defensively dropping the recipient. Other severities short-circuit to `[]` and the `cc:` collapses to `nil` via `.presence`.
- Refactored `fallback_emails_for` to share a single `active_responsibility_for` lookup with the new `responsibility_primary_email_for` helper — one resolution path for both pieces of contact info.

## Files Changed

### App code
- `app/services/onboarding_flow/escalation_cascade.rb` — emit `primary_email` in gm_nudge payload; share `active_responsibility_for` between fallback + primary lookups.
- `app/mailers/escalation_mailer.rb` — `cc_for` helper; CC header only set on `:gm_nudge`.

### Specs
- `spec/services/onboarding_flow/escalation_cascade_spec.rb` — assert `primary_email` + `fallback_chain` in the gm_nudge `NextAction` payload.
- `spec/mailers/escalation_mailer_spec.rb` — CC contents, dedup, GM-filter, missing-primary tolerance; negative tests on every other severity.

### Memory bank
- `memory-bank/tasks.md` — TASK-007 row.
- `memory-bank/tasks/TASK-007.md` — full task plan and Execution State.
- `memory-bank/archive/archive-TASK-007.md` — this document.

## Notes

- **Use the active Responsibility for "who's on the hook," not the Source's `configured_by_contact`.** Whoever first clicked through the setup link gets persisted on the Source as `configured_by_contact`. That is the right anchor for setup-related correspondence, but for accountability the canonical "who owns this" is the *active* Responsibility's `primary_contact`. The two diverge after reassignment.
- **Defensive `recipient` filter on CC** is cheap belt-and-braces: with the data model as-is the GM should never appear in `primary_email` or `fallback_chain`, but a sloppy seed or a fixture-only test could produce that state. Filtering at the mailer keeps the cascade resilient.
- **Single shared lookup**, not two parallel scans. Earlier draft computed `responsibility_primary_email_for` and `fallback_emails_for` independently; the refactor extracted `active_responsibility_for` so both helpers walk the responsibilities once. Pure cleanup, no behavior change.

## References

- **Task file**: `memory-bank/tasks/TASK-007.md`
- **Task commit**: `5f9c2d4`
- **Merge commit**: `c34674c`
