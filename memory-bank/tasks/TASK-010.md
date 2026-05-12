# TASK-010: Separate deliverable from question prompt in QUESTIONS catalog

**Complexity**: Level 2 (inherited from FEAT-007)
**Status**: PLANNING_COMPLETE
**Roadmap**: FEAT-007
**Branch**: feature/FEAT-007-separate-deliverable-from-prompt (to be created from main)
**Worktree**: N/A
**Docs Opt-In**: no
**Docs Opt-In Reason**: no Docusaurus tree at docs/
**Marketing Opt-In**: no
**Marketing Opt-In Reason**: no marketing schema at db/seeds/marketing/

## Task Description

Today, each entry in the marketing question catalog (`lib/rogue/question_catalog/marketing/v1.rb`) has a single `prompt` field that does double duty:

1. **As a question:** the literal text emailed to the GM ("Who controls your marketing strategy at <%= dealership_name %>?") in `question_email.{html,text}.erb` and as the email subject via `canonical_subject(@tenant, @question.prompt)`.
2. **As an assignment label:** every consumer that wants to describe the *responsibility* (summary view, done view, in-thread ack, weekly digest, dashboards) reverse-engineers a label by calling `tenant_question.prompt.downcase.sub(/\?$/, "")` (sometimes `.capitalize`). That produces awkward labels like "who controls your marketing strategy at smith toyota" — leaking the dealership name into a context where the dealership is already named separately, and reading as a fragment of a question rather than a thing.

This task decouples the two by adding an explicit `deliverable` field to each `QUESTIONS` entry and a mirrored `deliverable` column on `tenant_questions` (same pattern as the existing `prompt` column). The 7 consumer sites that currently mangle `prompt` switch to reading `deliverable`. The question email continues to use `prompt`. The invitee setup email also continues to use `prompt` (it shows the invitee the original question they were CC'd on, which is correct context for why they were assigned).

### Locked design decisions (from /rai-plan dialogue 2026-05-12)

1. **Backfill copy** — for existing `tenant_questions` rows, write `deliverable` derived from the current `prompt` (`prompt.downcase.sub(/\?$/, "")`). Catalog entries get hand-written deliverable strings (see Specification → Catalog copy). Production data fix to match catalog copy is a follow-up; this task ensures both new and existing rows have a non-null value.
2. **ERB substitution** — `deliverable` strings are static; no `<%= dealership_name %>` substitution needed. The dealership context is already rendered elsewhere on every page that shows the label. The materializer writes deliverable as-is.
3. **NOT NULL** — `deliverable` is `NOT NULL` on `tenant_questions`. Migration backfills existing rows in the same change before adding the constraint.

## Specification

**Feature Type**: End-User Feature (touches GM-visible digest copy, contact-visible summary/done copy, GM-visible in-thread ack copy)
**Primary Persona**: GM (digest, ack, dashboard) + responsible contact (summary, done)
**Creative Exploration Needed**: No — pattern mirrors existing `prompt` column; copy decisions resolved below.

### Invocation Method

This is a copy/data-model refinement. There is no new entry point. Existing surfaces that read `tenant_question.prompt` for label purposes will render `tenant_question.deliverable` instead.

### Success Criteria

- **GM sees** (weekly digest, in-thread ack, dashboard): clean noun-phrase responsibility labels like "Marketing strategy" or "Paid search and social advertising" — not "who controls your marketing strategy at smith toyota".
- **Contact sees** (setup walkthrough summary, done): same clean labels in "asked you to provide X" and "submit your first X report" sentences.
- **No regression** in question email or invitee setup email — both continue to show the full prompt with dealership name substitution.
- **Data persistence:** every `tenant_questions` row has a non-null `deliverable` after migration. New rows materialized for newly-confirmed tenants get the catalog-defined deliverable.

### Acceptance Criteria

#### AC-CATALOG-1: QUESTIONS array entries declare `deliverable`
**Priority**: MUST
**Given** the `Rogue::QuestionCatalog::Marketing::V1::QUESTIONS` constant
**When** the catalog is inspected
**Then** every entry has a `:deliverable` key whose value is a non-empty string. The spec at `spec/lib/rogue/question_catalog/marketing/v1_spec.rb` extends the existing "each question has required keys" example to include `:deliverable`.

#### AC-MATERIALIZE-1: Materializer writes deliverable for new tenant questions
**Priority**: MUST
**Given** a Tenant with no existing `tenant_questions`
**When** `Rogue::QuestionCatalog::Marketing::V1.materialize_for(tenant:)` runs
**Then** each created `TenantQuestion` row has `deliverable` populated from the catalog entry (no ERB substitution; written verbatim).

#### AC-MIGRATION-1: Existing rows backfilled before NOT NULL constraint
**Priority**: MUST
**Given** existing `tenant_questions` rows (from any pre-existing dev/test/prod data)
**When** the migration runs
**Then** every row receives a backfilled `deliverable` value derived from its current `prompt` (`prompt.downcase.sub(/\?$/, "")`). The NOT NULL constraint is added *after* the backfill in the same migration. The migration is reversible (`down` removes the column).

#### AC-MODEL-1: TenantQuestion validates deliverable presence
**Priority**: MUST
**Given** an unpersisted `TenantQuestion`
**When** saved without a `deliverable` value
**Then** the record fails validation with `deliverable: can't be blank`.

#### AC-VIEWS-1: Seven consumer sites use `.deliverable` instead of `.prompt.downcase.sub(/\?$/, "")`
**Priority**: MUST
**Given** the rendered output of the 7 consumer sites listed below
**When** a `TenantQuestion` with prompt "Who controls your marketing strategy at Smith Toyota?" and deliverable "marketing strategy" is rendered
**Then** each site shows "marketing strategy" (or "Marketing strategy" where capitalized) — not "who controls your marketing strategy at smith toyota".

Sites:
1. `app/views/setup/walkthroughs/summary.html.erb:13` — "asked you to provide X"
2. `app/views/setup/walkthroughs/done.html.erb:19` — "submit your first X report"
3. `app/views/onboarding_mailer/in_thread_ack.html.erb:15` — "is on the hook for X"
4. `app/views/onboarding_mailer/in_thread_ack.text.erb:13` — same as above
5. `app/views/accountability_mailer/weekly_digest.html.erb:41` — digest row label
6. `app/views/accountability_mailer/weekly_digest.text.erb:11` — digest row label
7. `app/views/dashboards/show.html.erb:30` — dashboard row label (`responsibility_label` local)

#### AC-VIEWS-2: Question email and invitee setup email continue to use `.prompt`
**Priority**: MUST (regression guard)
**Given** the question email and invitee setup email
**When** rendered for the same `TenantQuestion`
**Then** they show the full question prompt with dealership name (e.g., "Who controls your marketing strategy at Smith Toyota?"), unchanged from current behavior. No code change at these four sites.

Sites unchanged:
- `app/views/onboarding_mailer/question_email.html.erb:14`
- `app/views/onboarding_mailer/question_email.text.erb:3`
- `app/views/onboarding_mailer/invitee_setup_email.html.erb:21`
- `app/views/onboarding_mailer/invitee_setup_email.text.erb:5`
- `app/mailers/onboarding_mailer.rb:34` (in_thread_ack subject — uses prompt as canonical subject topic for threading)
- `app/mailers/onboarding_mailer.rb:148` (question_email subject)

### Catalog copy (deliverables for marketing/v1)

| Key | Prompt (unchanged) | Deliverable (new) |
|---|---|---|
| marketing_strategy | Who controls your marketing strategy at <%= dealership_name %>? | marketing strategy report|
| marketing_invoices | Who is responsible for reviewing and approving marketing invoices at <%= dealership_name %>? | marketing invoices |
| dealer_website | Who manages your dealer website at <%= dealership_name %>? | dealer website performance report |
| paid_search_social | Who manages your paid search and social advertising at <%= dealership_name %>? | paid search and social advertising report |
| oem_compliance | Who oversees OEM marketing compliance and co-op programs at <%= dealership_name %>? | OEM marketing compliance report |
| lead_source_attribution | Who is responsible for tracking and attributing lead sources at <%= dealership_name %>? | lead source attribution report |

**Casing convention**: deliverables are stored lowercase. Consumer sites that need a capitalized leading letter (weekly_digest, dashboards) call `.capitalize` on read. This mirrors current behavior where the same sites call `.capitalize` after `.sub(/\?$/, "")`.

### Scope Boundaries

**In scope:**
- Migration adding `deliverable` (text, NOT NULL) to `tenant_questions` with a backfill step from `prompt`.
- `TenantQuestion` model: `validates :deliverable, presence: true`.
- `lib/rogue/question_catalog/marketing/v1.rb`: add `:deliverable` to each of the 6 QUESTIONS entries; update `materialize_for` to write `tq.deliverable = question_attrs[:deliverable]` on the find-or-create block.
- `spec/lib/rogue/question_catalog/marketing/v1_spec.rb`: extend "required keys" example; add a per-question deliverable presence example; add a materialize_for example asserting deliverable is persisted from the catalog.
- 7 consumer view/mailer-view files: swap `.prompt.downcase.sub(/\?$/, "")` (and `.capitalize` variant) for `.deliverable` (and `.deliverable.capitalize` where the trailing `.capitalize` was present).
- Existing specs for the 7 consumer sites (where they exist) updated to assert the new label format.
- One model spec example for `TenantQuestion` deliverable validation.

**Out of scope:**
- Production data fix to align existing prod `tenant_questions` rows with catalog-defined deliverables (backfill from `prompt` is good enough; final copy fix is a follow-up if/when dogfooding shows it matters).
- Sales/service catalog versions (don't exist yet; pattern will be followed when they're added).
- Adapter for showing deliverable vs prompt context-sensitively in the invitee_setup_email (current behavior — full prompt — is the documented intent per TASK-009 reflection).
- Removing the existing `prompt` column or making it nullable (still required for the question email; no change).
- Tailwind/styling changes — none of the swapped sites have styling implications.

**Dependencies:**
- None. Touches only the question catalog data model + read sites. No interaction with the cascade, mailer routing, or signed-link layer.

**NFR implications:**
- Tenant isolation: `deliverable` is per-question, not per-tenant; lives on `tenant_questions` which already enforces tenant scoping via FK. No new cross-tenant surface.
- Idempotency: migration backfill is a one-shot UPDATE; safe to re-run if rolled back and re-applied (the `down` removes the column entirely).
- No new external boundaries; no FlowEvent rows produced.

## Test Strategy

### Approach
- **Emphasis**: balanced — catalog/model unit + view-rendering unit (request or view spec) per swapped site cluster
- **Target test count**: ~10 tests total (3 catalog, 1 model, 2-3 mailer-view examples, 2-3 view examples covering the digest + summary/done + dashboard). Justified <20 by Level 2 + tight scope.

### File Organization
- **Extend existing**:
  - `spec/lib/rogue/question_catalog/marketing/v1_spec.rb` — add `:deliverable` to required-keys assertion; add new examples for per-question deliverable presence and `materialize_for` persisting deliverable.
  - `spec/models/tenant_question_spec.rb` (if exists) — add deliverable-presence validation example.
  - `spec/mailers/accountability_mailer_spec.rb` (if exists) — assert digest body shows the new deliverable label.
  - `spec/mailers/onboarding_mailer_spec.rb` — assert in_thread_ack body shows the deliverable label; assert question_email and invitee_setup_email still show full prompt (regression guard for AC-VIEWS-2).
  - `spec/requests/setup/walkthroughs_spec.rb` or system spec covering summary/done — assert the new label format.
  - `spec/requests/dashboards_spec.rb` or equivalent — assert dashboard row label uses deliverable.
- **New test files**: none expected. Extending existing files keeps the test surface aligned with where the feature lives.

### What NOT to Test
- ERB substitution behavior on `deliverable` — explicitly out of scope per locked decision #2; no template logic to test.
- Re-running materializer idempotency wrt the new column — already covered by existing idempotency example (the `find_or_create_by!` semantics carry over; the example doesn't need to change beyond the required-keys assertion).
- Down-migration restoring the column — Rails' `change` block via `add_column` reverses cleanly; standard Rails migration behavior, not project-specific.

### Per-Phase Test Guidance
- **Phase 1 (catalog + migration + model):** ~5 tests
  - Catalog: required-keys assertion includes `:deliverable` (extend existing); deliverable is non-empty for every catalog entry (new example).
  - Materializer: deliverable persisted from catalog (new example).
  - Model: deliverable presence validation (new example).
  - Migration: implicitly covered by a separate test-only `rake db:migrate` run + spec suite green (no dedicated migration spec — matches project pattern; no other migration in `db/migrate/` has a dedicated spec).
- **Phase 2 (consumer site swap):** ~5 tests
  - Mailer specs: digest body, in_thread_ack body show new label; question_email and invitee_setup_email body still show full prompt (regression guard).
  - Request/view specs: summary and done show new label in their respective sentences; dashboard row label uses deliverable.

## Implementation Roadmap

- [x] **Phase 1: Catalog + persistence**
  - Add `deliverable` text column to `tenant_questions` via migration that:
    1. Adds the column as nullable
    2. Backfills via `UPDATE tenant_questions SET deliverable = lower(regexp_replace(prompt, '\?$', ''))` in the same migration (use `reversible` block; the `up` does add+backfill+set-null-false; the `down` removes the column)
    3. Sets `NOT NULL` after backfill completes
  - Add `validates :deliverable, presence: true` to `TenantQuestion` model.
  - Add `:deliverable` to all 6 entries in `QUESTIONS` per Catalog copy table.
  - Update `Rogue::QuestionCatalog::Marketing::V1.materialize_for` to write `tq.deliverable = question_attrs[:deliverable]` inside the existing `find_or_create_by!` block.
  - Update catalog spec: extend required-keys example; add per-question non-empty deliverable example; add materialize_for example asserting persistence.
  - Update model spec: deliverable presence validation example.
  - Run `bin/rails db:migrate` against test DB and confirm all 6 catalog deliverables flow through to `tenant_questions` rows in a fresh materialize.
  - Verify reflect-style: `bin/rails db:rollback` cleanly removes the column.

- [x] **Phase 2: Consumer site swap**
  - Replace `tenant_question.prompt.downcase.sub(/\?$/, "")` with `tenant_question.deliverable` at:
    - `app/views/setup/walkthroughs/summary.html.erb:13`
    - `app/views/setup/walkthroughs/done.html.erb:19`
    - `app/views/onboarding_mailer/in_thread_ack.html.erb:15` (preserves `|| "this responsibility"` fallback via `presence ||`)
    - `app/views/onboarding_mailer/in_thread_ack.text.erb:13` (same fallback handling)
  - Replace `prompt.downcase.sub(/\?$/, "").capitalize` with `deliverable.capitalize` at:
    - `app/views/accountability_mailer/weekly_digest.html.erb:41`
    - `app/views/accountability_mailer/weekly_digest.text.erb:11`
    - `app/views/dashboards/show.html.erb:30` (the `responsibility_label` local)
  - Update mailer specs and view/request specs to assert the new label format; add a regression-guard example confirming `question_email` and `invitee_setup_email` still render the full prompt.
  - `rubyfmt` the touched Ruby files; `bin/rspec` full suite green.

## Creative Phases

- None. Level 2; design is mechanical and bounded.

## Clarifications

<!--
  Populated by /rai-clarify TASK-010 (optional, post-plan).
-->

## Spec Review

<!--
  Populated by /rai-spec-review TASK-010 (optional, post-plan).
-->

## Validation Report

<!--
  Populated by /rai-validate TASK-010 (optional, post-build, pre-reflect).
-->

## Live-Dogfood-Pending Tracker

(none)

---

## Execution State

**Build Status**: BUILD_COMPLETE
**Current Phase**: BUILD (all phases complete; ready for /rai-reflect or /rai-archive)
**Last Completed**: Phase 2 (Consumer site swap)
**Can Resume**: NO

### Active Sub-Agents
(none)

### Completed Steps
- PLAN: Specification written; locked decisions (backfill from prompt, no ERB on deliverable, NOT NULL with in-migration backfill, 7 consumer sites swap, 4 sites unchanged). Catalog deliverable strings drafted. Two-phase implementation roadmap.
- BUILD Phase 1 (2026-05-12): Migration `20260512120000_add_deliverable_to_tenant_questions.rb` adds text NOT NULL `deliverable` column with in-migration backfill from `prompt`. `TenantQuestion` model validates presence. `QUESTIONS` catalog entries (all 6) gained `:deliverable` per locked copy table. Materializer writes deliverable verbatim (no ERB substitution). Factory default added. Catalog spec extended (+3 examples); model spec extended (+1 validation). 28 phase-1 specs green; 450/0 full suite green. Migrate + rollback + migrate cycle verified locally.
- BUILD Phase 2 (2026-05-12): Seven consumer view/mailer-view files swapped from `prompt.downcase.sub(/\?$/, "")` (and `.capitalize` variant) to `deliverable` (and `deliverable.capitalize`): `setup/walkthroughs/summary.html.erb`, `setup/walkthroughs/done.html.erb`, `onboarding_mailer/in_thread_ack.{html,text}.erb` (with `.presence ||` fallback preserved), `accountability_mailer/weekly_digest.{html,text}.erb`, `dashboards/show.html.erb`. Spec coverage: +3 new examples (in_thread_ack HTML/text deliverable assertions; done deliverable assertion) with tight positive+negative assertions ("deliverable string appears" AND "mangled-prompt fragment does not"). Existing summary/dashboard/digest specs tightened to assert against the new format. Regression guards added for `question_email` and `invitee_setup_email` to confirm they still render the full prompt (AC-VIEWS-2). 453/0 full suite green.
