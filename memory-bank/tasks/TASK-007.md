# TASK-007: gm_nudge emails CC the full responsibility chain

**Complexity**: Level 1
**Status**: COMPLETE
**Roadmap**: N/A
**Branch**: task/007-gm-nudge-cc-responsible-parties (merged into main via c34674c; branch deleted on archive)
**Worktree**: N/A (Level 1 uses direct branch)
**Archived**: memory-bank/archive/archive-TASK-007.md
**Completed**: 2026-05-09 (merged); archived 2026-05-10

## Task Description

When the escalation cascade reaches the `gm_nudge` rung, the email should
CC every responsible party (the active Responsibility's primary_contact +
fallback_contact_emails). Currently the email goes only to the GM with no
CCs. Putting the responsible chain on CC gives the GM a one-click
"reply-all and ask them to still complete it" path.

Other escalation rungs are unchanged — they keep their single-recipient
behavior.

## Implementation Notes

- `OnboardingFlow::EscalationCascade` builds the gm_nudge `NextAction`.
  Extend its payload to include `primary_email` (the responsibility's
  primary_contact email), alongside the existing `fallback_chain`.
- `EscalationMailer#escalation_email` reads the payload at delivery time;
  when severity is `:gm_nudge`, set `cc:` to `[primary_email, *fallback_chain]`
  uniq'd and with the recipient (the GM) filtered out (defensive — should
  never be in there, but cheap belt-and-braces).
- Use the active responsibility chain (responsibility.primary_contact +
  fallback_contact_emails), NOT `source.configured_by_contact`. The
  configured_by_contact is whoever clicked through setup; the
  responsibility's primary_contact is who the GM said is on the hook.
  Those are usually the same person but can diverge after reassignment.

## Files Touched

- `app/services/onboarding_flow/escalation_cascade.rb` — emit `primary_email`
  in gm_nudge payload
- `app/mailers/escalation_mailer.rb` — set `cc:` for gm_nudge
- `spec/services/onboarding_flow/escalation_cascade_spec.rb` — assert payload
- `spec/mailers/escalation_mailer_spec.rb` — assert CC behavior

## Verification

1. Cascade spec: gm_nudge `NextAction` payload includes `primary_email`
   (the active responsibility's primary_contact email), plus the existing
   `fallback_chain`.
2. Mailer spec: when severity is `:gm_nudge`, mail.cc contains
   primary + fallbacks (uniq'd, GM filtered out). Other severities have
   no CC.
3. Manual: re-run the runbook step 9 cascade. The final gm_nudge email to
   `jane@smithtoyota.com` should have `Cc: alex@smithtoyota.com,
   taylor@smithtoyota.com`.

---

## Execution State

**Build Status**: IDLE
**Current Phase**: COMPLETE
**Can Resume**: NO

### Active Sub-Agents
(none)

### Completed Steps
- Branch created: `task/007-gm-nudge-cc-responsible-parties`
- Task file created
- `EscalationCascade` emits `primary_email` (responsibility's primary_contact)
  in gm_nudge payload alongside existing `fallback_chain`
- `EscalationMailer#cc_for(severity, payload, recipient)` builds CC list
  from `[primary_email, *fallback_chain].compact.uniq`, dropping the
  recipient defensively. Only invoked for `:gm_nudge`; other severities
  return `[]` and `cc:` collapses to nil via `.presence`.
- Cascade spec: new test asserts `primary_email` + `fallback_chain` in
  the gm_nudge `NextAction` payload
- Mailer spec: new tests assert CC contents (chain, dedup, GM-filter,
  missing-primary tolerance) plus negative tests on every other severity
- Full suite: 398/398 specs pass
