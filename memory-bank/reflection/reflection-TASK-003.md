# Reflection: TASK-003 — Escalation Cascade

## Task ID
TASK-003

## Complexity Level
Level 3 (intermediate feature, no creative phases needed)

## Summary

Closes the productBrief's "graduated escalation" promise. Three phases delivered in a tight single-session build:

1. **Phase 1 — `OnboardingFlow::EscalationCascade`** — pure-function severity classifier that returns a typed `NextAction` (or nil) for any prompt + time. The FlowEvent log is the single source of truth for "what's been escalated already"; the cascade reads but never writes.
2. **Phase 2 — `EscalationDetectorJob` + `EscalationMailer`** — hourly recurring detector iterates `:sent` prompts, calls the cascade, records a FlowEvent, and queues the matching mailer. Single mailer action with severity-driven subject + body branching.
3. **Phase 3 — `Accountability::DigestAssembler` extension** — adds `:late` and `:overdue` row statuses based on the FlowEvent log + period-end check.

Cumulative: 24 specs, ~280 lines of production code, full coverage of the 4-step ladder (due_soon → overdue → fallback_fanout → gm_nudge) and the no-fallbacks short-cut path.

## Plan vs Reality

- **Original estimate**: 3 phases, ~25-35 specs, no creative.
- **Actual**: 3 phases, **24 net new specs** (353 → 362 → 377 → 379 across phase 1/2/3 + digest). 0 rubocop offenses, 0 spec failures.
- **Deviations**: One technical hiccup — the cascade's first pass used Time math for due_soon/overdue thresholds, which made calendar-day-based test expectations fail (May 29 10:00 UTC = May 29 06:00 EDT, which compares as before May 28 23:59 EDT in Time math). Fixed by switching due_soon/overdue to Date math (`now.in_time_zone(tz).to_date >= threshold_date`) while keeping fallback/gm_nudge on Time math (anchored on prior FlowEvent's `occurred_at`, where hour precision is correct). Caught at first spec run; fixed in two edits.

## What Went Well

### Technical
- **The "FlowEvent log as idempotency anchor" pattern** that landed in TASK-001 generalized cleanly to a multi-step ladder. The cascade reads `escalation.*` events for a prompt, picks the next severity, and the detector writes the FlowEvent before the mailer — re-runs see the existing event and short-circuit naturally. No duplicate-prevention table needed.
- **The pure-function severity classifier** is a satisfying shape. It takes `(prompt, now)`, returns a value object or nil, never touches the database except to read the FlowEvent log. All 9 service specs exercise it without any mocking.
- **`travel_to` for time-based ladder traversal** in the job spec walked through the full 4-step ladder in one test (`due_soon → overdue → fallback_fanout → gm_nudge`) by hopping `travel_to` calls. The detector is stateless, so each hop is just "let time advance, run the job, check the FlowEvents."
- **Reusing `Threadable`** kept the mailer's per-tenant `From:` setup to one line.
- **Single mailer action with severity branching** kept the mailer file small and the view template count to one (vs. four separate actions). The trade-off is a `case @severity` block in the ERB; acceptable for MVP.

### Process
- **Spec-first cadence held throughout.** Phase 1 wrote 9 cascade specs before any production code. Phase 2 wrote 15 specs (job + mailer) before either was implemented. Phase 3 extended the digest spec before extending the assembler.
- **Plan's confidence assessment correctly punted** the per-tenant grace-window override question to FEAT-005. No scope creep.
- **The TASK-001/TASK-002 archives served as architectural references** — patterns like Threadable, FlowEvent.record!, value-object services, recurring jobs, and magic-link signed_ids all came from those archives without re-litigating.

## Challenges Encountered

### Calendar-day vs hour-precise threshold
- **Description**: First-pass cascade compared `now < period_end - 3.days` using full-precision Time math. Test sent `now = 2026-06-03 10:00 UTC` expecting overdue to fire; in EDT that's 06:00, before the threshold of 23:59 May 31 + 3 days = June 3 23:59 EDT. Test failed.
- **Resolution**: Switch due_soon and overdue to Date-based comparison (`now.in_time_zone(tz).to_date >= due_soon_open_date`). Keep fallback_fanout and gm_nudge on Time math (anchored on prior FlowEvent's `occurred_at`).
- **Prevention**: When the test author's intent is "this fires on day N", use Date math. When the intent is "this fires N days after a specific event", use Time math anchored on that event. The ladder mixes both: period boundaries are calendar-day, inter-fallback waits are hour-precise.

### Single mailer template with severity branching
- **Description**: Considered three separate mailer actions (`due_soon_email`, `overdue_email`, `gm_nudge_email`) vs. one action with severity branching. Three actions would have meant three view templates and more boilerplate; one action with `case @severity` keeps the file count down but puts presentation logic in the view.
- **Resolution**: Single action. The view's `case` block is small (4 branches × ~5 lines each). If copy diverges in FEAT-005's per-severity refinement, revisit.
- **Prevention**: Default to one mailer action when the recipient/subject/body all derive from the same params; split when they fork into genuinely different shapes.

## Creative Decision Assessment

No formal `/rai-creative` phase was run. The plan flagged no LOW-confidence design areas; the MEDIUM-confidence "single mailer vs. three mailer actions" choice was punted to FEAT-005 via the in-spec note. Decision held — the single-mailer shape is cleaner at MVP.

## Lessons Learned

### Technical
- **Mix Date and Time math intentionally** in scheduling logic. Calendar-day boundaries (period_end + N days) want Date arithmetic; "N hours/days after a specific event" wants Time arithmetic anchored on that event.
- **The "FlowEvent log as state machine" pattern** generalizes well beyond TASK-001's domain events. Here it's the entire escalation state machine — no dedicated `escalation_state` column on `submission_prompts` because the FlowEvent log already records every transition.
- **Stateless detector + persistent log** is the right shape for recurring escalation logic. The detector is a pure read-then-write; the log is the durable state. Restartable, retriable, idempotent for free.

### Process
- **Phase 3 doubles as the digest extension and the close-out**. Bundling the small DigestAssembler change with the reflection/archive work (rather than separating into a Phase 4) kept commit count tight (3 phases instead of 4) without sacrificing reviewability.
- **The pattern of "extend an existing service's value object with new branches"** (DigestAssembler picked up `:late` and `:overdue` here) keeps churn low — no new service file, just a new private method and a thin call site change.

## Recommendations

- **Promote `idempotency.md` to medium priority** — TASK-003 produced its third evidence row (the cascade's read-FlowEvent-log pattern). The promotion threshold is 3; consolidation during this archive should fire it.
- **Promote `time-zones.md` to medium priority** — third evidence row also (cascade period boundaries in tenant TZ).
- **Add a `escalation-cascade-walkthrough` to systemPatterns.md** — the FlowEvent-as-state-machine pattern for graduated escalation is a reusable architectural shape worth documenting alongside the existing patterns.
- **Per-tenant grace-window overrides (FEAT-005)** — the four constants (`DUE_SOON_GRACE_DAYS` / `OVERDUE_GRACE_DAYS` / `FALLBACK_GRACE_DAYS` / `GM_GRACE_DAYS`) live as module constants. FEAT-005 will move them to `tenants.escalation_*_days` columns or per-Responsibility overrides.
- **Per-severity copy refinement (FEAT-005)** — current escalation copy is friendly across all severities; FEAT-005 may want progressively sterner tone.
- **Late/overdue row UX in the digest** — the digest table already renders the status column, so visual treatment is automatic. Consider distinct status colors / icons in FEAT-005.

## Claude Code Ecosystem Evaluation

### Commands Assessment

| Command | Used | Effectiveness | Notes |
|---------|------|---------------|-------|
| `/rai-roadmap feature create` | Y | High | Roadmap entry done; FEAT-004 numbering reserved FEAT-003 for AI adapter generation. |
| `/rai-plan` | Y | High | TASK-003 auto-provisioned with full spec. No Spec Writer Agent spawn — in-context drafting was faster. |
| `/rai-creative` | N | n/a | No LOW-confidence design areas. |
| `/rai-build` | Y (×3) | High | Three clean phase commits. Pattern is mature now — minimal ceremony, lots of substance per commit. |
| `/rai-reflect` | Y (this command) | High | Lighter than Level 4 reflection; appropriate. |
| `/rai-archive` | (next) | n/a | TBD. |

### Workflow Assessment
- **Phase Progression**: Smooth, fastest of the three features so far.
- **Unnecessary Phases**: None.
- **Missing Phases**: None.

### Context Files Assessment
- **Helpful Files**:
  - The 5 entries in `agent-rules/_learned/` fired multiple times across this build (idempotency, time-zones, service-shape, namespacing, audit-trail). The continuous learning system is paying back compoundingly.
  - TASK-001 and TASK-002 archives served as the architectural reference — no need to re-derive Threadable / FlowEvent / signed-id patterns.
- **Gaps**: None for a feature continuing in an established system.
- **Outdated Content**: None.

### Tools Assessment
- All standard tools (Read / Edit / Write / Bash / TaskCreate / TaskUpdate) worked without issue. No Task / sub-agent spawns this build.

### Subagent Assessment
- None used this build (in-context execution).

### Memory Bank Assessment
- File structure adequate.
- The per-feature pattern is mature: roadmap entry → tasks/TASK-NNN.md plan → 3 phase commits → reflection → archive → merge → push. Each step has a stable shape.

### Ecosystem Improvement Suggestions

#### High Priority
- (Carry-forward from TASK-001/002): Trim `/rai-build` command file. Still descriptively heavy for the in-context build pattern that's now the established workflow.

#### Medium Priority
- The Continuous Learning system worked: three patterns reinforced this build (idempotency, time-zones, service-shape), one new (calendar-vs-time math). Worth confirming that the reflection-step pattern extraction is durable across multiple consecutive features. So far so good.

#### Low Priority
- (None this build.)

## References

- **Plan**: `memory-bank/tasks/TASK-003.md`
- **Roadmap**: `memory-bank/roadmap.md` → FEAT-004
- **Phase commits**: `8fd5c15` (P1), `9be2ac2` (P2), Phase 3 + reflection commit forthcoming.
- **Final state**: 379 RSpec examples / 0 failures / 0 RuboCop offenses on `feature/FEAT-004-escalation-cascade`
