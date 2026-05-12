# Archive: TASK-010 — Separate deliverable from question prompt in QUESTIONS catalog

## Metadata
- **Task ID**: TASK-010
- **Roadmap Link**: FEAT-007
- **Complexity**: Level 2
- **Started**: 2026-05-12
- **Completed**: 2026-05-12 (single-session, two-phase build + one follow-on copy hotfix)
- **Final state**: 453 RSpec examples / 0 failures
- **Phase commits** on branch `feature/FEAT-007-separate-deliverable-from-prompt`:
  - `c4873b7` — Phase 1: deliverable column + catalog field
  - `20c1cfa` — Phase 2: consumer site swap to deliverable
  - `decbd46` — Drop "report" from done view to avoid "report report"
  - `5db6955` — Reflection + 1 extracted learning (amended)

## Summary

Decoupled the dual-purpose `prompt` field on the marketing question catalog into an explicit `deliverable` column on `tenant_questions`. Previously the same `prompt` text served as both the question emailed to the GM ("Who controls your marketing strategy at <%= dealership_name %>?") and — after `.downcase.sub(/\?$/, "")` mangling — the responsibility label rendered in digests, dashboards, summary views, and in-thread acks. Seven consumer sites now read the explicit `deliverable` field; four sites that intentionally show the original question (the question email and the invitee setup email) keep reading `prompt`.

The catalog now declares both fields explicitly per question. The migration adds the `deliverable` text column with an in-migration backfill from `prompt` so pre-existing rows satisfy the new NOT NULL constraint.

## Requirements

### Original Requirements

The catalog's `prompt` field was doing double duty. The user wanted to define the deliverable separately within the QUESTIONS array so that the question text and the responsibility label become explicit, named fields.

### Success Criteria — Acceptance Criteria

- [✓] **AC-CATALOG-1**: Each of the 6 `QUESTIONS` entries declares `:deliverable` as a non-empty string. Spec extended to assert the key is present and non-empty per question.
- [✓] **AC-MATERIALIZE-1**: `materialize_for` writes `tq.deliverable = question_attrs[:deliverable]` verbatim (no ERB substitution). Spec asserts catalog→row equality per key and asserts no dealership-name leak into materialized deliverable.
- [✓] **AC-MIGRATION-1**: Migration adds `text deliverable NOT NULL` via `add_column nullable → UPDATE backfill → change_column_null false` in a single `up`. Reversible via `down`. Migration cycle (`up → down → up`) verified locally before view code landed.
- [✓] **AC-MODEL-1**: `TenantQuestion` validates `deliverable` presence.
- [✓] **AC-VIEWS-1**: 7 consumer sites swapped to read `deliverable` (or `deliverable.capitalize`). New + tightened specs assert both that the deliverable string appears AND that the old prompt-mangled fragment does not appear (positive + negative assertion pairs).
- [✓] **AC-VIEWS-2**: Regression guards for `question_email` (subject + HTML + text) and `invitee_setup_email` (HTML body) confirm they still render the full prompt with dealership name. No code change at those four sites.

## Implementation

### Approach

Two phases:
1. **Phase 1: Catalog + persistence.** Migration, model validation, catalog field, materializer wiring, factory default, catalog + model spec extensions. Verified the migrate-rollback-migrate cycle on test DB before touching any consumer code.
2. **Phase 2: Consumer site swap.** Strict TDD red-then-green: write 3 net-new assertions + tighten 5 existing assertions so they fail against the old behavior, confirm 7 failures, swap 7 view/mailer-view files, confirm 0 failures.

A small follow-on copy fix landed after the build's end-of-build eyeball pass: the deliverables ending in "report" (e.g., "marketing strategy report") collided with `done.html.erb`'s template suffix "submit your first X report" to produce "submit your first marketing strategy report report". One-line template-side fix dropped the literal "report" from the template prose.

### Key Components

1. **Migration `20260512120000_add_deliverable_to_tenant_questions`** — adds `text deliverable` (nullable first), backfills via `UPDATE tenant_questions SET deliverable = lower(regexp_replace(prompt, '\?$', '')) WHERE deliverable IS NULL`, then sets `NOT NULL`. Reversible via `def down; remove_column(:tenant_questions, :deliverable); end`.
2. **`TenantQuestion` model** — added `validates :deliverable, presence: true` alongside the existing field validations.
3. **`Rogue::QuestionCatalog::Marketing::V1`** — each of the 6 `QUESTIONS` hash entries gained a `:deliverable` string (locked in `/rai-plan` by the user via in-place edit of the task file's catalog copy table). The materializer's `find_or_create_by!` block writes `tq.deliverable = question_attrs[:deliverable]` without ERB substitution.
4. **Factory** — `spec/factories/tenant_questions.rb` gained a `deliverable { "marketing strategy report" }` default so existing specs continue to materialize valid records.
5. **Seven view/mailer-view files** — `setup/walkthroughs/summary.html.erb`, `setup/walkthroughs/done.html.erb`, `onboarding_mailer/in_thread_ack.{html,text}.erb`, `accountability_mailer/weekly_digest.{html,text}.erb`, `dashboards/show.html.erb`. The in-thread ack call sites preserve their fallback contract via `@parsed.question&.deliverable.presence || "this responsibility"` (deliverable is now NOT NULL on the column, but `@parsed.question` itself may still be nil for clarification responses or unparseable replies).
6. **Done view template prose** — dropped the literal "report" suffix in `done.html.erb` since the deliverables themselves end in "report" where applicable.

### Catalog Copy (locked in /rai-plan, edited in-place by user)

| Key | Deliverable |
|---|---|
| marketing_strategy | marketing strategy report |
| marketing_invoices | marketing invoices |
| dealer_website | dealer website performance report |
| paid_search_social | paid search and social advertising report |
| oem_compliance | OEM marketing compliance report |
| lead_source_attribution | lead source attribution report |

### Design Decisions

No formal `/rai-creative` phase — Level 2 task with mechanical scope. Three open decisions were resolved as locked yes/no questions during `/rai-plan` and held through build:

1. **Backfill source**: derive from `prompt` (`lower(regexp_replace(prompt, '\?$', ''))`). Safe default for any pre-existing rows; new catalog rows get the hand-written deliverable.
2. **ERB substitution**: no. Deliverable is a static noun phrase; the dealership name is rendered separately at every consumer site.
3. **NOT NULL**: yes. Constraint added in the same migration after the backfill completes.

## Testing

- **Catalog (`spec/lib/rogue/question_catalog/marketing/v1_spec.rb`)** — extended the existing "required keys" example to include `:deliverable`; added a per-question non-empty deliverable example; added a materialize_for example asserting catalog→row equality; added a "no Smith Toyota leaked" example.
- **Model (`spec/models/tenant_question_spec.rb`)** — added `validate_presence_of(:deliverable)`.
- **Mailer (`spec/mailers/accountability_mailer_spec.rb`)** — tightened two digest body assertions (HTML + text) from `include("marketing strategy")` to `include("Marketing strategy report") + not_to include("Who controls")`. The negative assertion is the regression guard against accidental future reverts.
- **Mailer (`spec/mailers/onboarding_mailer_spec.rb`)** — added 2 net-new examples for `in_thread_ack` HTML + text deliverable rendering; renamed/tightened 2 existing examples as regression guards for `question_email` (HTML + text) keeping the full prompt; renamed 1 existing example as regression guard for `invitee_setup_email` keeping the prompt.
- **Request (`spec/requests/setup/walkthroughs_spec.rb`)** — tightened summary assertion to require deliverable + reject "who controls" mangled fragment; added 1 net-new example for `done` view next-prompt sentence using deliverable.
- **Request (`spec/requests/dashboards_spec.rb`)** — tightened the dashboard responsibility-row example with positive + negative assertions.

**Total**: +3 net-new examples (in_thread_ack HTML/text + done deliverable). Plus +4 catalog/model/factory test additions in Phase 1 (catalog required-keys extension; non-empty deliverable per question; materializer persistence; model validation matcher). 5 existing examples tightened to positive+negative assertion pairs. **Final suite: 453 examples, 0 failures** (up from 450).

## Files Changed

### App code
- `app/models/tenant_question.rb` — `validates :deliverable, presence: true`.
- `app/views/setup/walkthroughs/summary.html.erb` — `tenant_question.deliverable` swap.
- `app/views/setup/walkthroughs/done.html.erb` — `tenant_question.deliverable` swap; dropped literal "report" suffix from template prose.
- `app/views/onboarding_mailer/in_thread_ack.html.erb` — `@parsed.question&.deliverable.presence || "this responsibility"` swap.
- `app/views/onboarding_mailer/in_thread_ack.text.erb` — same swap.
- `app/views/accountability_mailer/weekly_digest.html.erb` — `deliverable.capitalize` swap.
- `app/views/accountability_mailer/weekly_digest.text.erb` — same swap.
- `app/views/dashboards/show.html.erb` — `responsibility_label = ...deliverable.capitalize` swap.

### Library
- `lib/rogue/question_catalog/marketing/v1.rb` — `:deliverable` added to all 6 QUESTIONS entries; materializer writes deliverable.

### Migration + schema
- `db/migrate/20260512120000_add_deliverable_to_tenant_questions.rb` (new)
- `db/schema.rb` — reflects new `t.text "deliverable", null: false` column on `tenant_questions`.

### Specs + factories
- `spec/factories/tenant_questions.rb` — deliverable default.
- `spec/lib/rogue/question_catalog/marketing/v1_spec.rb` (extended).
- `spec/models/tenant_question_spec.rb` (extended).
- `spec/mailers/accountability_mailer_spec.rb` (tightened).
- `spec/mailers/onboarding_mailer_spec.rb` (extended + tightened).
- `spec/requests/setup/walkthroughs_spec.rb` (tightened + extended).
- `spec/requests/dashboards_spec.rb` (tightened).

### Memory bank
- `memory-bank/roadmap.md` — FEAT-007 added; TASK-010 linked.
- `memory-bank/tasks.md` — TASK-010 row added.
- `memory-bank/tasks/TASK-010.md` — full spec + plan + execution state.
- `memory-bank/reflection/reflection-TASK-010.md` — reflection.
- `memory-bank/archive/archive-TASK-010.md` — this document.
- `memory-bank/agent-rules/_learned/html-entity-agnostic-assertions.md` — amended (renamed to "Rendered-output spec assertion patterns"; evidence count 1 → 2; widened scope to cover positive+negative assertion-pair pattern for field-swap regressions).
- `memory-bank/learning-log.md` — appended TASK-010 extraction entry.
- `memory-bank/learning-metrics.md` — task history + rule effectiveness updated.

## Lessons Learned

(From `memory-bank/reflection/reflection-TASK-010.md`)

- **Positive + negative assertion pairs for field-swap regressions.** When swapping a field that templates were reading, each new spec assertion should be a pair: positive (`include(new field value)`) AND negative (`not_to include(unique fragment of the old transformation's output)`). The positive catches "you forgot to swap this site"; the negative catches "you swapped a site that should have stayed on the old field" or "this test still passes against the unfixed code". Together they pin the change tightly. *(Extracted to `_learned/html-entity-agnostic-assertions.md` — renamed to "Rendered-output spec assertion patterns" and widened scope.)*

- **Audit adjacent template prose when introducing a named data field.** When a new data field names a thing (e.g., `deliverable: "marketing strategy report"`), audit the surrounding template prose for words now redundant. The template that previously read "submit your first <prompt-fragment> report" may produce "submit your first X report" where X already ends in "report", producing "report report". Spec assertions on the new field's content do not catch surrounding-prose redundancy — only an end-of-build human eyeball of rendered output does. *(Captured in reflection but not extracted to `_learned/`; cap exceeded at 12 files and single-task evidence.)*

- **Locked-decisions pattern.** Three explicit binary questions resolved at `/rai-plan` time (backfill source, ERB substitution, NOT NULL), captured in the task file as "Locked design decisions" with one-word answers, held cleanly through build. The pattern preserves spec stability without forcing the planner to over-document every alternative.

- **Task-file-as-spec.** The user directly edited the catalog deliverable copy table inside `TASK-010.md` between `/rai-plan` and `/rai-build`. Treating the task file as a live spec document — editing in place — was friction-free.

- **Migration cycle verified before view changes.** Phase 1 ran `db:migrate → db:rollback → db:migrate` on the test DB before any view code was touched. Catching a broken migration before consumers depend on the column is much cheaper than catching it after.

## Workflow Notes

- **Same-day cycle**: plan + 2 build phases + hotfix + reflect + archive all within one session, ~90 minutes elapsed. Level 2 + locked decisions + 7-site mechanical change is exactly the shape that runs same-day cleanly.
- **No `/rai-creative` phase** — planning gate correctly identified no creative exploration needed.
- **End-of-build eyeball as a process step** — the "report report" doubling was caught by the user prompting "anything to eyeball?" not by any automated check. The follow-on hotfix commit `decbd46` captures the resolution. Reflection includes a suggestion to add an explicit eyeball-rendered-output prompt to the `/rai-build` phase-completion output.

## References

- **Plan**: `memory-bank/tasks/TASK-010.md`
- **Reflection**: `memory-bank/reflection/reflection-TASK-010.md`
- **Roadmap link**: `memory-bank/roadmap.md` → FEAT-007
- **Predecessor patterns reinforced**: `_learned/html-entity-agnostic-assertions.md` (now "Rendered-output spec assertion patterns" after amendment)
