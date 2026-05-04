# Reflection: TASK-002 — Submission Prompt Sender

## Task ID
TASK-002

## Complexity Level
Level 3 (intermediate feature, no creative phases needed)

## Summary

Closed the loop on TASK-001's invitee setup walkthrough. Phase 5 of TASK-001 had been writing `submission_prompts` rows but nothing was sending them; the digest was reporting "Pending first submission" forever. TASK-002 ships:

1. **`SubmissionPromptSenderJob`** — hourly recurring job (declared in `config/recurring.yml`) that finds due `:pending` prompts, atomically transitions them to `:sent` via a `WHERE status = 'pending'` UPDATE (the synchronisation point — concurrent workers race; the loser sees affected_rows=0), and queues the appropriate mailer based on `Source.submission_method`.
2. **`SubmissionMailer`** — `prompt_email` for form-method recipients (carries a 14-day magic-link to the form) and `adapter_pending_email` for `:csv` / `:api_post` parked-state recipients (FEAT-003 will land actual adapter generation).
3. **`Submissions::FormsController`** at `/submissions/:signed_id` — single-controller GET (form / already-submitted / expired) + POST (capture).
4. **`Submissions::Capture`** transactional service — Submission row + prompt status flip + FlowEvent emit, returning a `Result` Struct so the controller can branch cleanly.
5. **`Accountability::DigestAssembler` extension** — flips the per-row status from `:pending_first_submission` to `:on_time` when at least one Submission exists for the current period.

Three phases delivered: Phase 1 (foundation: model + migrations + factory + 7 specs), Phase 2 (sender job + 2-action mailer + 19 specs), Phase 3 (controller + capture service + digest extension + 20 specs).

## Plan vs Reality

- **Original estimate**: 3 phases, ~30-45 specs, no creative phases.
- **Actual**: 3 phases, **46 new specs** (89 → 314 → 333 → 353 across phases 1/2/3), 0 rubocop offenses, 0 spec failures across the whole TASK-001 suite.
- **Deviations**: Two minor:
  1. **Naming clash** — drafted the service as `Submission::Capture` mirroring TASK-001's `Setup::Completion`, but `Submission` is the model class (not a module). Renamed to `Submissions::Capture` to match the `Submissions::FormsController` namespace. Caught at first run of the spec via Zeitwerk's `TypeError: Submission is not a module`.
  2. **Redirect target** — the post-submit redirect lands on `?submitted=1` which routes through `show`, where the `:fulfilled` short-circuit hits the `already_submitted` view, not the `?submitted=1` branch on the form view. Fixed by re-styling `already_submitted.html.erb` so it doubles as the success page (which it semantically is — a submitted prompt landed a contact on a "we have your data" page either right after submitting or revisiting later).

Both deviations resolved within minutes; neither required schema or design changes.

## What Went Well

### Technical
- **The "atomic UPDATE WHERE status = pending" idempotency pattern** worked exactly as designed. The unit test for "sender doesn't re-send a `:sent` prompt" needed no special test setup — the constraint is the lock.
- **Reusing `Threadable`** from TASK-001 made the prompt mailer's per-tenant `From:` work out of the box (`onboarding+<token>@inbound.rogue.example`).
- **The Result Struct pattern** (from `Setup::Completion` in TASK-001) generalized cleanly. `Submissions::Capture.call(...)` returns `Result(success:, submission:, error:)`; the controller just branches on `.success?`.
- **The `Source.configured_by_contact` already pointed at the right person.** Phase 5 of TASK-001 captured that field; we read it back here. No need to chase down "who do we email?" — the data was already shaped right.
- **`config/recurring.yml` is the right shape.** Adding a new recurring job is one block of YAML, no code changes.
- **Period derivation in tenant TZ.** The lesson from TASK-001's quarterly-scheduler bug (use `tenant.time_zone`-anchored construction, never `Time.zone`) carried into Phase 3 — `period_starting_for(prompt)` does `prompt.scheduled_for.in_time_zone(tz).to_date.beginning_of_month`. Tested across `:on_time` digest assertion which constructs the same period the same way.

### Process
- **TDD RED → GREEN cadence held tight.** Each phase: write specs → see them fail (or load-error in the renaming case) → implement → see green → lint → commit. No phase commit was longer than ~10 minutes from spec start to green tests.
- **Pre-existing patterns made phase 2 trivial.** The `Threadable` concern, the `signed_id` purpose-scoped helpers, the `FlowEvent.record!` idiom, the hourly-recurring-job shape — all of them came from TASK-001 with zero adaptation.
- **Skipping creative was the right call.** The spec explicitly deferred per-metric form schemas to FEAT-003 by shipping a generic numeric+notes form. No design exploration needed; the LOW-confidence area was punted at the spec level.

## Challenges Encountered

### Submission namespace clash
- **Description**: First-pass service file lived at `app/services/submission/capture.rb` with `module Submission; module Capture; ...`. Zeitwerk autoload-loaded `app/models/submission.rb` first, registering `Submission` as a class; then loading `app/services/submission/capture.rb` raised `TypeError: Submission is not a module`.
- **Resolution**: Renamed both the directory and the constant to `Submissions::Capture` (aligned with the controller namespace `Submissions::FormsController`). Two `Edit` calls + one `mv`.
- **Prevention**: When the natural namespace name collides with a model class, default to the plural form (matching controller convention). Add this to the service-shape learning.

### Already-submitted page doubling as thank-you
- **Description**: First-pass design had `already_submitted.html.erb` say "Already submitted" (terse, revisit-tone) and the `show.html.erb` had a `?submitted=1` branch with "Got it." copy. The post-create redirect lands on `show?submitted=1`, but `show`'s controller logic short-circuits on `:fulfilled` and renders `already_submitted` before ever evaluating the query param. The test asserting "Got it / thanks / received" failed.
- **Resolution**: Restructured `already_submitted.html.erb` to be the unified post-submit page (works for first-time-after-submit AND idempotent revisits). Removed the dead `?submitted=1` branch in `show.html.erb` (kept as defensive fallback).
- **Prevention**: When a controller has multiple entry-states, design the views around states, not transitions. The state here is `:fulfilled`; the page is the same regardless of how the user got there.

### Redirect after capture races against status flip
- **Description**: The redirect from `create` lands back on `show`. `show` reads the prompt's status. There's a tiny window where, on a slow database, the redirect could hit before the transaction commits visibility. In practice this isn't a problem (Rails wraps the controller in a transaction wrapper, the FlowEvent insert + status update are in `Submissions::Capture`'s explicit transaction, and the redirect is sent only after the transaction commits) — but worth noting for any future async path.
- **Resolution**: Not actually a problem in the current synchronous flow; just an architectural observation.
- **Prevention**: If future work makes the capture async (e.g., move to a job for slow-running validation), the controller should render an inline thank-you instead of redirecting.

## Creative Decision Assessment

No formal `/rai-creative` phase was run. The plan flagged one MEDIUM-confidence area (per-metric form schemas) and explicitly deferred it to FEAT-003. The generic numeric+notes form shipped at MVP, fits the marketing-strategy / website-traffic / website-leads metrics in the catalog adequately. This was the right call — opening a creative phase to design per-metric forms would have ballooned scope.

## Lessons Learned

### Technical
- **Idempotency markers via single-row UPDATE WITH WHERE clause** are the right primitive for "send this exactly once" jobs that don't have a separate marker table. Cheaper than `WeeklyDigestDelivery`-style insert-marker-first because the prompt row itself is the marker. Trade-off: the marker is bound to the prompt's lifecycle.
- **Service-class namespace convention**: when the natural service noun matches a model class (e.g., `Submission`), default to the plural namespace (`Submissions::Capture`) to align with controller conventions and avoid Zeitwerk autoload conflicts.
- **One controller can serve a multi-step user flow** when the steps map to durable model state. Both TASK-001's `Setup::WalkthroughsController` (3 steps × source state) and this task's `Submissions::FormsController` (form / already-submitted / expired × prompt state) work this way. Cleaner than per-step routes.
- **Magic-link tokens scoped per (purpose, expires_in)** should also bind to the natural domain object, not the user. Here the token signs the SubmissionPrompt id, not the contact id — so a single contact can have multiple distinct prompts, each with its own URL.

### Process
- **The plan's confidence assessment is the right place to defer scope.** Calling out "MEDIUM confidence on the generic-form choice — explicitly scoped MVP" in the spec made it impossible to scope-creep into per-metric forms during build.
- **Phase commits with rich messages double as a build log.** `git log --oneline feature/FEAT-002-submission-prompt-sender` reads as a 3-line summary of the entire feature; the per-commit body documents the actual mechanics. Saved having to write a build log separately.
- **TDD on the controller layer pays off.** Writing the form spec before the controller forced me to think about what "valid token + :sent" vs "valid token + :fulfilled" vs "expired token" actually look like to the user. The controller's branch structure followed naturally.

## Recommendations

- **Add a `Source has_many :requests` and `Request has_many :submissions, through: :submission_prompts`** assertion test (the current `has_many` declarations exist but no test exercises the chain). Would have caught any FK regressions introduced by Phase 1's `submissions` migration if the `request_id` index were missed.
- **Consider a `period_starting` derivation helper on Request or Cadence** — currently `Submissions::Capture.period_starting_for(prompt)` and `DigestAssembler.any_current_period_submission?` both hard-code "monthly = beginning_of_month." Quarterly / semi-annual / annual cadences are wired through the catalog but no submission flow exists for them yet. Generalizing this helper before FEAT-003 lands per-cadence forms would prevent duplication.
- **Document the `Threadable` concern's growing reach** in `systemPatterns.md` — it's now used by `OnboardingMailer` (5 actions) and `SubmissionMailer` (2 actions). Worth a one-line entry under "Mailer Patterns."
- **Promote the idempotency learning** in `agent-rules/_learned/idempotency.md` — TASK-002 just produced a second piece of evidence for it (the `pending → sent` UPDATE pattern). Once `evidence_count` hits 3, it auto-promotes to `medium` priority during the next archive consolidation.

## Claude Code Ecosystem Evaluation

### Commands Assessment

| Command | Used | Effectiveness | Notes |
|---------|------|---------------|-------|
| `/rai-init` | N | n/a | Memory bank already initialized from TASK-001. |
| `/rai-roadmap feature create` | Y | High | Roadmap entry, branch name, complexity assessment all in one shot — though the user had to be prompted twice for the feature substance (initial invocation passed no args, second invocation passed the feature ID rather than the name). |
| `/rai-plan` | Y | High | Auto-provisioned TASK-002.md from FEAT-002, including header, Specification template, and Implementation Roadmap skeleton. Spec drafted directly from the conversational context (no Spec Writer Agent spawn) — appropriate for a single-session build. |
| `/rai-creative` | N | n/a | Skipped — no LOW-confidence design questions. The plan's deferral of per-metric forms to FEAT-003 made this unnecessary. |
| `/rai-build` | Y (×3) | High | Three phase commits, each clean. The state-tracking machinery in the task file's Execution State section was lighter than for TASK-001 because phases were faster and self-contained. |
| `/rai-reflect` | Y (this command) | High | Template fits a Level 3 task well. Less ceremonial than the Level 4 version. |
| `/rai-archive` | (next) | n/a | Will evaluate post-archive. |

### Workflow Assessment

- **Phase Progression**: Smooth. Each `/rai-build` invocation closed one phase; each phase commit was a clean snapshot.
- **Unnecessary Phases**: None. The task scoped tightly to 3 phases by design.
- **Missing Phases**: None at this complexity tier.

### Context Files Assessment

- **Helpful Files**:
  - `memory-bank/agent-rules/_learned/idempotency.md` and `time-zones.md` — the two TASK-001-extracted learnings both fired in this build (the sender's atomic UPDATE for idempotency; period derivation in tenant TZ). The `_learned/` system is already paying back.
  - `memory-bank/archive/archive-TASK-001.md` — the architecture description and patterns-worth-codifying section served as a reference shape for this feature's spec.
  - TASK-001's commit log — re-reading the per-phase commit messages was the fastest way to remember "how did we wire `Threadable`?" without re-reading source.
- **Gaps Identified**: None for a Level 3 build that's a continuation of an existing system. A new project (no archive to lean on) would have felt different.
- **Outdated Content**: None.

### Tools Assessment

| Tool | Usage | Effectiveness | Limitations |
|------|-------|---------------|-------------|
| Read | High | ~100% | None. |
| Edit | High | ~100% | The "must Read before Edit" rule fired once after Edit-then-Edit on the same file with a linter pass in between (fine — rule is correct). |
| Write | Medium | ~100% | None. |
| Bash | High | ~100% | None encountered. The earlier `cd && cmd` rule continued to be respected. |
| Grep | Low | 100% | None. |
| Glob | Low | 100% | None. |
| Task (sub-agent) | 0 | n/a | Not used — single-session in-context execution was faster. |
| TaskCreate / TaskUpdate | High | 100% | The system-reminder cadence on `task tools haven't been used recently` continues to feel over-eager during routine file edits. (Carry-forward observation from TASK-001 reflection.) |

### Subagent Assessment

- **Agents Used**: None this build (in-context execution).
- **Prompt Quality**: n/a.
- **Output Quality**: n/a.
- **Improvements Needed**: The `/rai-build` command file still describes a sub-agent fan-out architecture that isn't being used in single-session builds. As noted in TASK-001's reflection — trim the command file or document the in-context-vs-spawn branching point. Same observation, no new evidence this build.

### Memory Bank Assessment

- **File Structure**: Adequate.
- **Template Usefulness**: The `task-template.md` shape is good, but I wrote TASK-002.md by hand rather than reading the template (the in-context conversation had enough structure). The template would matter more for a fresh agent session.
- **Missing Documents**: None. The full structure (tasks/, creative/, reflection/, archive/, agent-rules/_learned/, learning-log, learning-metrics, progress, projectbrief, systemPatterns, techContext, productBrief, roadmap) covers everything.

### Ecosystem Improvement Suggestions

> Suggestions only. Not implementing here.

#### High Priority
1. **(Carried forward from TASK-001 reflection): Trim `/rai-build` command file** — for in-session multi-phase builds the orchestration content is descriptive of an unused architecture. Trim to ~200 lines + reference link.

#### Medium Priority
1. **Explicit "in-context vs spawn-agent" branching documentation in `/rai-build`** — spec what the orchestrator should do when the human-driven session has full context vs. a fresh agent.
2. **Persist `evidence_count` reinforcement in `agent-rules/_learned/`** — when a build re-encounters a pattern (idempotency fired again here, time-zones fired again here), the learned rule's Evidence table should auto-grow without waiting for the next reflection. As-is, evidence is appended only at reflection time.

#### Low Priority
1. **Lint rule banning model-class names as service module namespaces** — the `Submission` vs `Submissions::Capture` clash would be caught by a small Zeitwerk-aware linter check.
2. **`/rai-build` should pre-check for namespace collisions** — when the implementation step would create a new module/class, verify it doesn't clash with existing ActiveRecord classes.

## References

- **Plan**: `memory-bank/tasks/TASK-002.md`
- **Roadmap**: `memory-bank/roadmap.md` → FEAT-002
- **Phase commits**: `3c0b6b7` (P1), `27def7d` (P2), `9a303d6` (P3)
- **TASK-001 archive (architectural reference)**: `memory-bank/archive/archive-TASK-001.md`
- **Final state**: 353 RSpec examples / 0 failures / 0 RuboCop offenses on `feature/FEAT-002-submission-prompt-sender`
