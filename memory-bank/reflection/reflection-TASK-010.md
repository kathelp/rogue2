# Reflection: TASK-010 — Separate deliverable from question prompt in QUESTIONS catalog

**Date**: 2026-05-12
**Task Complexity**: Level 2 (inherited from FEAT-007)
**Total Phases**: 2 (+ one follow-on copy hotfix)
**Duration**: 2026-05-12 (planning + both phases + reflection same-day)
**Branch**: `feature/FEAT-007-separate-deliverable-from-prompt`

## Executive Summary

TASK-010 decoupled a dual-purpose `prompt` field on the marketing question catalog into an explicit `deliverable` column on `tenant_questions`. The two-phase plan (Phase 1: migration + model + catalog; Phase 2: swap seven consumer views/mailer-views) ran straightforwardly — 453 specs green at the end of both phases, no regressions, no rework. The migration's in-place backfill (`add_column nullable → execute UPDATE → change_column_null false`) handled both fresh test DBs and existing dev DBs cleanly; the rollback cycle (`db:rollback` → `db:migrate`) was verified before any view code was touched.

The most interesting feedback signal came at end-of-build review: the deliverable copy (e.g., "marketing strategy report") combined with `done.html.erb`'s literal template suffix ("submit your first X report") produced "submit your first marketing strategy report **report**". The data-side copy was already locked by the user in `/rai-plan`; the right resolution was template-side — drop "report" from the surrounding template prose. A one-line follow-on commit (`decbd46`) fixed it. This is the kind of side-effect that's invisible at planning time and only surfaces when you read rendered output with fresh eyes.

The workflow shape — `/rai-roadmap feature create` → `/rai-plan` → `/rai-build` × 2 → end-of-build eyeball — matched the task's complexity precisely. No `/rai-creative` was needed (and the planning gate correctly identified that). The "locked design decisions" pattern (3 decisions captured verbatim in `/rai-plan` and referenced in the task description) was a clean handoff from planning to build, and let me proceed without re-deriving those choices mid-implementation.

---

## Dimension 1: Task Implementation Quality

### Requirements Achievement

**Status**: Complete (all 6 ACs from the task spec met)

- **AC-CATALOG-1**: Each of the 6 `QUESTIONS` entries in `marketing/v1.rb` has a non-empty `:deliverable` string. Catalog spec extended (`required keys` example + new `non-empty deliverable per question` example).
- **AC-MATERIALIZE-1**: `materialize_for` writes `tq.deliverable = question_attrs[:deliverable]` inside the existing `find_or_create_by!` block. Spec covers per-key catalog→row equality and asserts no `Smith Toyota` substitution leak.
- **AC-MIGRATION-1**: Migration `20260512120000` adds `text deliverable NOT NULL` via the canonical 3-step shape (nullable add → UPDATE backfill → set NOT NULL) in a single `up`. Reversible via `down`. Verified by `db:migrate` → `db:rollback` → `db:migrate` cycle on test DB.
- **AC-MODEL-1**: `validates :deliverable, presence: true` on `TenantQuestion`. Spec uses `validate_presence_of(:deliverable)` matcher in the existing validations block.
- **AC-VIEWS-1**: Seven sites swapped — `setup/walkthroughs/{summary,done}.html.erb`, `onboarding_mailer/in_thread_ack.{html,text}.erb`, `accountability_mailer/weekly_digest.{html,text}.erb`, `dashboards/show.html.erb`. The in-thread ack call sites preserve the fallback contract via `@parsed.question&.deliverable.presence || "this responsibility"` instead of the previous `|| "this responsibility"` on `nil`.
- **AC-VIEWS-2**: Regression guards for `question_email` (subject + HTML + text) and `invitee_setup_email` (HTML body) confirm they still render the full prompt. Both consciously kept on `prompt` — the question email asks the question; the invitee setup email shows the original question to the invitee for context.

### Code Quality Assessment

**Overall Rating**: High (for a Level 2 mechanical change)

- **Maintainability**: High. The data model now has a clear field-purpose contract: `prompt` = the question (with ERB substitution), `deliverable` = the responsibility label (static copy). The seven swapped sites all read identically — `.deliverable` or `.deliverable.capitalize`. The previous `.prompt.downcase.sub(/\?$/, "").capitalize` six-call chain is gone everywhere a label was wanted; remaining `.prompt` reads are intentional (the question text itself).

- **Architecture**: Good. Mirrors the existing `prompt` column pattern on `tenant_questions` rather than introducing a new shape. The materializer writes both fields in the same `find_or_create_by!` block, preserving idempotency.

- **Test discipline**: Strict TDD for Phase 2 — wrote 3 new failing assertions (in_thread_ack HTML/text, done deliverable) plus tightened 5 existing assertions to require positive ("deliverable string appears") + negative ("prompt-mangled fragment does NOT appear") pairs, ran the spec batch (7 failures confirmed red), then implemented the view changes, then re-ran (0 failures). Phase 1 was looser since the model validation + migration + catalog can't easily be red-green'd separately, but the catalog spec extension and migration cycle both ran clean.

- **Migration safety**: The 3-step migration shape is the right one. Pre-existing rows in dev/prod get a non-null value derived from `prompt` (the same string the old views were producing), which is a safe default for any rows that exist before the catalog refresh. The follow-up to align prod row copy with the locked catalog deliverable strings is a data fix, not a schema fix, and was intentionally scoped out.

### Technical Decisions

**Key Decisions:**

1. **NOT NULL backfilled in-migration vs nullable column + later constraint** — Chosen in `/rai-plan` and held through build. The 3-step shape (`add_column → execute UPDATE → change_column_null false`) is atomic from a deployment perspective (the migration either fully lands or fully rolls back) and avoids the "code expects column, column is nullable, row created before backfill" race window. Cost is one extra line of migration; benefit is no nullable-handling logic in the model or views.

2. **No ERB substitution on `deliverable`** — Locked in planning. The deliverable strings are noun phrases; the dealership name is rendered separately at every consumer site (summary view says "Smith Toyota asked you to provide X", digest says "Smith Toyota — this week's accountability digest"). Re-rendering it inside the deliverable would be duplicative. The materializer writes `deliverable` verbatim; a spec example explicitly asserts no `Smith Toyota` substring leaks into any materialized row.

3. **`.presence ||` instead of `||` for the in-thread ack fallback** — The previous code was `@parsed.question&.prompt&.downcase&.sub(/\?$/, "") || "this responsibility"` — the `|| "this responsibility"` fired when `@parsed.question` was nil. With deliverable now NOT NULL on the column, the only nil path is still `@parsed.question` itself being nil (clarification responses, unparseable replies). `&.deliverable.presence || "this responsibility"` is the cleanest expression: `nil.deliverable` would `NoMethodError`, but `nil&.deliverable.presence` returns nil, and `nil.presence` returns nil. `nil || "fallback"` → fallback. Works.

4. **Positive + negative assertion pairs for the field swap** — When swapping a field that templates were using, each new assertion is a *pair*: positive ("new field value appears") AND negative ("old transformation's fragment does NOT appear"). For example, `expect(body).to include("Marketing strategy report")` AND `expect(body).not_to include("Who controls")`. The positive assertion catches "you forgot to swap this site"; the negative assertion catches "you swapped a site that should have stayed on the old field" (regression guard). Both together pin down the change tightly. This pattern is broadly useful — captured in extractable learnings.

5. **Follow-on hotfix for "report report"** — When the deliverable copy ends in "report" and the template prose also appends "report", the result is "submit your first marketing strategy report report on June 1". The data-side copy was locked; the template-side prose was the right thing to prune. Caught at end-of-build eyeball review, not by any spec assertion (the new assertions check for "marketing strategy report" being present and "who controls" being absent — they don't catch "report report"). Lesson: when introducing a structured data field that names a thing, audit the surrounding template language for words now redundant.

**Trade-offs:**

- **Production data copy lag**. The migration backfills pre-existing rows from `prompt` (so they get "who controls your marketing strategy at smith toyota" rather than the catalog-defined "marketing strategy report"). New tenants confirmed after this migration get the clean copy. Existing prod rows would need a one-off data fix to align with the catalog copy. Scoped out — accepted because dogfood hasn't started in prod yet, so no real rooftop has the "ugly" backfill copy.

- **No down-migration spec**. Rails' `add_column` reverses cleanly via the standard `remove_column` path; manual verification (`db:rollback` → `db:migrate`) was done locally but not codified as an automated check. Matches the project pattern — no migration in `db/migrate/` has a dedicated spec — but worth flagging as a small gap.

### What Went Well

1. **Locked-decisions pattern in the task file** — Planning resolved three explicit yes/no questions (backfill source, ERB substitution, NOT NULL), the user answered each in one word, and those answers landed in the task file as "Locked design decisions" before any code was written. During build I never had to revisit any of them or hedge against alternatives. This is the cheapest way to capture spec stability: numbered binary questions, one-word answers, both preserved in the task file.

2. **User-edited catalog copy in the task file** — After `/rai-plan` produced an initial deliverable copy table, the user directly edited that table in `TASK-010.md` (e.g., "marketing strategy" → "marketing strategy report") before invoking `/rai-build`. The edited table was then the single source of truth for the implementation. Treating the task file as a live spec document — that the human edits in place — was friction-free.

3. **Tight positive+negative assertion pairs** — Five existing spec assertions in `accountability_mailer_spec`, `walkthroughs_spec`, and `dashboards_spec` were tightened from `include("marketing strategy")` (which would pass against both the old and new behavior) to `include("Marketing strategy report") + not_to include("Who controls")` (which fails on the old behavior and passes on the new). The negative assertion is the regression guard; the positive assertion is the change confirmation. The pair pins down the behavior change tightly enough that a future accidental revert would fail loudly.

4. **Migration shape verified before view changes** — Phase 1 included a manual `db:migrate` → `db:rollback` → `db:migrate` cycle on the test DB. Catching a broken migration before view code lands is much cheaper than catching it after.

5. **Same-day cycle on a tightly-bounded change** — Plan → build phase 1 → build phase 2 → hotfix → reflect → archive in one session, with each phase under ~15 minutes and a clean spec suite at every checkpoint. Level 2 complexity with locked decisions and a 7-site mechanical change is exactly the shape that runs same-day.

### Challenges Encountered

1. **"Report report" copy collision** — Deliverables ending in "report" + template prose also appending "report" produced doubled wording. The new spec assertions confirmed the deliverable was being rendered (positive assertion) and the old prompt-mangling was gone (negative assertion), but neither caught the surrounding-prose redundancy. Resolution: read the rendered output as a human at end-of-build (the eyeball pass that the user prompted), spotted the doubling, dropped the literal "report" from `done.html.erb`. Lesson: when introducing a data field that names a thing, the words around it in templates may need pruning. Captured in extractable learnings.

2. **Pre-existing rubocop offenses in `v1_spec.rb`** — Running `rubocop` on the file I extended flagged 6 pre-existing `Layout/SpaceInsideArrayLiteralBrackets` offenses on lines I didn't touch. Resisting the urge to "while I'm here" auto-correct those was the right call — they aren't in my diff and aren't part of this task. Noted as a small repo-wide tidy candidate for a separate Level 1 task.

---

## Dimension 2: Claude Code Ecosystem Effectiveness

### Workflow Shape

- **`/rai-roadmap feature create` → `/rai-plan` → `/rai-build` × 2** matched the task's complexity. No `/rai-creative` was needed and the planning gate correctly identified that. No reflexive "spawn five sub-agents" overhead.
- The user's interjections were the right shape: (a) approve complexity escalation (Level 1 → Level 2), (b) answer three locked-decision questions, (c) edit the catalog deliverable copy table in the task file, (d) prompt for the end-of-build eyeball. Each was a small, targeted human-in-the-loop touch at a moment of decision authority.
- Same-day cycle held: plan + build1 + build2 + hotfix + reflect inside one session.

### Task-File-as-Spec Pattern

The user edited the catalog deliverable copy table directly in `TASK-010.md` between `/rai-plan` and `/rai-build`. This worked friction-free — the markdown table was the spec, edited in place, then read back from the task file during implementation. Worth codifying: when a planning artifact contains tabular data the human cares about (copy strings, value mappings, configuration tuples), keep that data in a markdown table inside the task file rather than scattering it across the plan body. The table form invites direct edits.

### Suggested Improvements (NOT for implementation here)

1. **Phase-completion spec-suite delta in commit body** — The Phase 2 commit body says "All 453 specs green" but the user has to remember Phase 1 was at 450 to know Phase 2 added 3 examples. A small commit-body line like "Suite: 450 → 453 (+3 examples)" makes phase-over-phase delta visible at a glance from `git log`.
2. **End-of-build eyeball as an explicit checklist item** — The "report report" problem was caught by the user prompting "is there anything to eyeball?" not by anything automated. A small explicit checklist in `/rai-build`'s phase-completion output ("Eyeball rendered output for: copy collisions, button visibility, breadcrumb logic") would prompt this discovery earlier. Cheap to add; high signal-to-noise for view/copy changes.

---

## Extractable Learnings

Each learning includes a 1-line directive and a scope hint for the agent-rules system.

### Learning 1: Positive + negative assertion pairs for field-swap regressions

- **Directive**: When swapping a field that templates were reading (e.g., replacing `model.foo.downcase.sub(...)` with `model.bar`), each new spec assertion should be a *pair*: positive (`include(new field value)`) AND negative (`not_to include(unique fragment of the old transformation's output)`). The positive catches "you forgot to swap this site"; the negative catches "you swapped a site that should have stayed on the old field". Together they pin the change tightly enough that a future accidental revert fails loudly.
- **Scope**: `spec/requests/**/*_spec.rb`, `spec/mailers/**/*_spec.rb`, `spec/system/**/*_spec.rb`, `spec/features/**/*_spec.rb`
- **Topic**: testing, assertion-patterns, field-swap, regression-guards
- **Anti-pattern**: only asserting that the new value appears — leaves a tested-and-currently-passing site exposed to a future maintainer who reverts one line without breaking the positive assertion.

### Learning 2: Audit adjacent template prose when introducing a named data field

- **Directive**: When a new data field names a thing (e.g., `deliverable: "marketing strategy report"`), audit the surrounding template prose for words now redundant. The template that previously read `"submit your first <%= prompt_fragment %> report"` may produce `"submit your first X report"` where X already ends in "report", producing "report report". Spec assertions on the new field's content do not catch surrounding-prose redundancy — only an end-of-build human eyeball of rendered output does.
- **Scope**: `app/views/**/*.erb`, `app/views/**/*.html`
- **Topic**: view-templates, copy, refactoring, rendered-output-review
- **Application**: applies when a refactor replaces inline string-mangling with an explicit data field. The replacement field is now self-contained, so adjacent template words that scaffolded the old fragment may need to go.

---

## Metrics

- **Files changed (3 commits combined)**: 23 modified, 2 created
- **Code lines added/removed**: +374 / -27
- **Specs added**: 7 (3 catalog/model in Phase 1, 3 view/mailer in Phase 2, 1 done-deliverable example)
- **Specs tightened**: 5 (digest html+text, summary, dashboard, mailer regression guards)
- **Test suite**: 450 → 453 (+3 net new examples; 4 modified-but-not-net-new)
- **Migration cycle**: up + down + up verified on test DB
- **Commits on branch**:
  - `c4873b7` — Phase 1: deliverable column + catalog field
  - `20c1cfa` — Phase 2: consumer site swap to deliverable
  - `decbd46` — Drop "report" from done view to avoid "report report"
- **Time**: ~90 minutes total elapsed (planning + 2 build phases + hotfix + reflection)

---

## Evaluation Summary

**Task Implementation Quality**: High — all 6 ACs met, suite green throughout, migration verified, locked-decision discipline held, the one rough edge (copy collision) was caught and fixed before reflect.

**Claude Code Ecosystem Effectiveness**: High — workflow shape matched complexity, task-file-as-spec pattern proved friction-free, no wasted sub-agent ceremony, same-day cycle.
