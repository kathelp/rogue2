# Archive: TASK-008 — Cc'd Contact Self-Verification

## Metadata
- **Task ID**: TASK-008
- **Roadmap Link**: FEAT-006
- **Complexity**: Level 3
- **Started**: 2026-05-09
- **Completed**: 2026-05-09 (single-day: plan → 3 creative phases → 3 backend build phases → reflect → archive)
- **Final state**: 414 RSpec examples / 0 failures / `rubyfmt --check` exits 0 globally
- **Phase commits on `feature/FEAT-006-ccd-contact-self-verification`**:
  - `6a12ddb` plan + creative
  - `af9c745` Phase 1: schema + Contact verification fields
  - `1657312` Phase 1 memory-bank update
  - `9a01d5d` Phase 2: `Contacts::PhoneNormalizer` (US E.164)
  - `3af0344` Phase 3: gate escalation fanout on contact verification
  - `51aadce` Phases 2 + 3 memory-bank update
  - `4fd2beb` reflection + 4 extracted learnings

## Summary

Backend foundation for a future contact-self-verification flow. When a CC'd contact arrives in the system via `OnboardingMailbox#handle_assignment`, they currently land with only an email address. This task adds the schema + model + service surface to support a verification step (the user-facing form is deferred to a separate FE design pass, with full UI/UX spec preserved in `memory-bank/creative/TASK-008-uiux.md`).

What shipped:

1. **Schema** — Migration `RemoveDisplayNameFromContactsAndAddIdentityFields` drops the dead `display_name` column (zero references in `app/` or `spec/`) and adds canonical `first_name`, `last_name`, `phone` columns on `contacts` (all nullable; an unverified contact remains a valid record).
2. **Verification predicate + scopes** — `Contact#verified?` returns true iff all three identity fields are present. `:verified` and `:unverified` scopes for SQL-side queries. `before_validation :nullify_blank_identity_fields` collapses blank strings to NULL so column-level checks stay accurate.
3. **PII encryption** — `encrypts :phone` (non-deterministic per architecture doc; names stay unencrypted at MVP).
4. **`Contacts::PhoneNormalizer`** — module-function PORO that normalizes user-entered phone strings to E.164 (`+1XXXXXXXXXX`). US-only at MVP; no `phonelib` gem.
5. **Cascade gating** — `OnboardingFlow::EscalationCascade.fallback_emails_for` now filters out unverified Contact emails. Verified contacts and unmatched legacy raw strings pass through. The filtered list also flows through the `gm_nudge` `fallback_chain` payload (FEAT-007 CC chain), so unverified contacts are not CC'd on the GM nudge.

## Requirements

### Original Requirements (from FEAT-006 roadmap entry)
- New users onboarded from being CC'd on an email enter first name, last name, and phone to complete verification.
- Verification is *derived* from field presence; no separate `verified_at` timestamp or state machine.
- Unverified contacts get different treatment from verified ones.

### Success Criteria (active backend phases)
- [✓] Schema dropped `display_name`, added the three canonical identity columns (Phase 1).
- [✓] `Contact#verified?` predicate + scopes implemented and tested (Phase 1).
- [✓] `encrypts :phone` non-deterministic per architecture decision (Phase 1).
- [✓] US E.164 phone normalizer ships as `Contacts::PhoneNormalizer` (Phase 2).
- [✓] Escalation cascade filters out unverified Contacts in `fallback_emails_for` (Phase 3).
- [✓] Three-rule passthrough preserved: verified KEEP, unverified DROP, unknown raw email KEEP (Phase 3).
- [✓] `gm_nudge` `fallback_chain` payload reflects the filtered list (Phase 3).
- [↻] AC-ENTRY-1 / AC-HAPPY-1 / AC-ERROR-1 / AC-LINK-1 from the spec — DEFERRED to FE pass (form, mailer copy, system spec, signed-link controller path). Backend is ready to receive these once the FE lands.

## Implementation

### Approach

Three discrete backend phases, one commit each, each gated by passing specs + green `rubyfmt --check` before proceeding. Front-end work (identity-step view, edited setup-email subject/body, system spec) was scope-cut by the user mid-cycle and parked for a separate design pass. The UI/UX creative doc remains valid and is the entry point for that future pass.

### Key Components

1. **Migration `db/migrate/20260509120000_remove_display_name_from_contacts_and_add_identity_fields.rb`** — single reversible migration. Specifies column type on `remove_column` so it rolls back cleanly.

2. **`app/models/contact.rb`** — added `encrypts :phone` (non-deterministic), `Contact#verified?` predicate, `:verified` / `:unverified` scopes (chained `where.not` for verified; `or`-chained NULL checks for unverified), and `before_validation :nullify_blank_identity_fields` to collapse blank strings to NULL.

3. **`app/services/contacts/phone_normalizer.rb`** — module-function PORO under `Contacts::` namespace (plural, per `_learned/namespacing.md` to avoid Zeitwerk collision with `Contact` class). ~6 lines of logic: strip non-digits, strip leading "1" if 11 digits, accept exactly 10 digits, return `+1XXXXXXXXXX`.

4. **`app/services/onboarding_flow/escalation_cascade.rb`** — `fallback_emails_for` (private method) extended with one bounded query per cascade evaluation: `tenant.contacts.where(email_normalized: emails).index_by(&:email_normalized)`. Filter rule: drop emails whose Contact exists AND is unverified. Self-healing: once a contact verifies, they rejoin the cascade on the next evaluation.

5. **`spec/factories/contacts.rb`** — added `:verified` and `:unverified` traits.

### Design Decisions (resolved in `/rai-creative`)

Three creative phases produced:
- **Architecture** (`memory-bank/creative/TASK-008-architecture.md`) — Q3 schema (drop display_name + add three fields), Q2 gating (Candidate A only — escalation fanout, not submission prompts), Q4 phone (in-house normalizer + non-deterministic encryption).
- **User Journey** (`memory-bank/creative/TASK-008-user-journey.md`) — Q1 trigger (inline in existing setup walkthrough as Step 1 of 4), Q5 re-prompt (none at MVP — piggyback on 7-day setup link expiry).
- **UI/UX** (`memory-bank/creative/TASK-008-uiux.md`) — form layout, edited setup email subject/body, error states, step counters. **Output preserved for the deferred FE design pass.**

The active build leveraged Architecture + portions of User Journey. UI/UX is parked.

### Surprises Encountered

1. **`display_name` was dead schema.** Declared in the FEAT-001 migration (`20260503180602_create_contacts.rb`), present in `db/schema.rb`, never written or read anywhere in `app/` or `spec/`. The Spec Writer Agent caught this via `grep -rn 'display_name' app/ spec/` returning zero matches. The original task description's "split `Contact#name` into first/last" was based on a stale memory of this column — there was no `name` column to split. Q3 in architecture resolved this as "drop the dead column."

2. **Codebase has no Tailwind.** UI/UX agent discovered all setup walkthrough views use inline styles. The original test strategy mentioned "Tailwind styling" — corrected during reconciliation. (Doesn't impact the active backend phases, but was important context for the deferred FE work.)

3. **Mid-cycle scope cut.** After all three creative agents had written their docs, the user directed "skip all FE for now." The Implementation Roadmap and Test Strategy had to be regenerated from scratch against the reduced scope (12–16 tests → 8–11 tests; 6 phases → 3 active + 3 deferred). The creative docs themselves remained valid as inputs to the deferred FE pass.

## Testing

- **Unit (model)**: 19 specs in `spec/models/contact_spec.rb` — `verified?` true/false matrix (3 fields × empty/present), `:verified` / `:unverified` scope inverses, encryption round-trip on `:phone`, blank → NULL normalization, factory traits exercise.
- **Unit (service)**: 10 specs in `spec/services/contacts/phone_normalizer_spec.rb` — happy E.164, formatted variants, 11-digit `1`-prefix, blank/non-numeric/wrong-length rejection, non-US country code rejection.
- **Service (cascade gating)**: 3 new specs in `spec/services/onboarding_flow/escalation_cascade_spec.rb` — unverified Contact email filtered, verified Contact retained, unknown raw email passes through, `gm_nudge` `fallback_chain` payload consistency.

**Total added**: 32 specs. **Final suite**: **414 examples, 0 failures.**

## Lessons Learned (Reflection)

Full reflection in `memory-bank/reflection/reflection-TASK-008.md`. Headline points:

- The Spec Writer Agent's empirical codebase analysis (grep for column references) was the single most valuable planning step. Without it, three phases of work would have been planned against a non-existent `Contact#name` column.
- Post-creative scope cuts are not a smooth path in the current workflow. The Implementation Roadmap and Test Strategy needed manual reconstruction. Captured as the `scope-cut-resilience` learned rule with a suggested workflow improvement (Step 0.7 reconciliation gate in `/rai-build`).
- `techContext.md` lint-command drift (rubocop → rubyfmt) had to be fixed mid-task. Surfaced as a need for `/rai-init` to validate development commands periodically.

### Extracted Learnings (added to `memory-bank/agent-rules/_learned/`)
- **service-shape** — AMENDED (evidence 1 → 2): two-outcome services may return nil-or-value, but if an architecture doc has specified a Result struct, implement OR update the doc; don't diverge silently.
- **schema-validation** — CREATED: grep proposed column names against `app/` and `spec/` before planning to surface dead schema.
- **scope-cut-resilience** — CREATED: post-creative scope cuts require regenerating Roadmap and Test Strategy from scratch.
- **gating-filter-passthrough** — CREATED: when filtering by a related model's state, "no record" → KEEP; only "record exists AND fails gate" → DROP.

## Forward Debt

- **`Contacts::PhoneNormalizer` return type diverges from architecture doc.** The architecture doc specified a `Result = Struct.new(:normalized, :valid?, keyword_init: true)` and the deferred controller stub uses `phone_result.valid?`. The implementation returns `nil` or a `String` directly. Before the deferred FE phase begins, either implement the Result struct (preferred — consistent with `_learned/service-shape.md`) or update the architecture doc and consuming controller stub to use a nil-check idiom.

- **`Contact.verified` SQL scope on encrypted `phone` column.** At current scale, the scope is never an entry-point query — gating reads happen per-contact via `verified?`. If a feature ever needs to batch-query verified contacts at scale, the scope would need rethinking (e.g., a queryable `verified_at` proxy column).

## Deferred Work (Not Done in This Cycle)

The following items were captured in the Live-Dogfood-Pending Tracker and parked at archive. UI/UX creative spec at `memory-bank/creative/TASK-008-uiux.md` is the entry point for any future task that picks them up:

1. **Setup walkthrough identity step** — controller branch in `Setup::WalkthroughsController#template_for_step`, new `identity.html.erb` view, identity PATCH action, step-counter updates.
2. **Edited `OnboardingMailer#invitee_setup_email`** — subject + body copy per UI/UX doc.
3. **System E2E spec** — GM reply → CC promotion → invitation → identity step → cascade gating activates.
4. **Letter-opener manual verification** — sanity-check the edited email copy locally.
