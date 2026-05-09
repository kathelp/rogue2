# Architecture Decision: Cc'd Contact Self-Verification

**Created**: 2026-05-09
**Status**: DECIDED
**Decision Type**: Architecture
**Task**: TASK-008 (FEAT-006)
**Scope**: Resolves Q2 (Gating semantics), Q3 (Schema), Q4 (Phone storage). Q1 (Trigger) and Q5 (Re-prompt cadence) are owned by the User Journey agent.

## Context

### System Requirements

- Cc'd contacts arrive in `OnboardingMailbox#handle_assignment` with only an email address (and, in the data model today, an empty `display_name` column that nothing reads or writes — confirmed below). The platform needs first name, last name, and phone before that contact is treated as a fully-onboarded responsibility holder.
- Verification status is **derived from field presence**, not a state machine and not a `verified_at` timestamp (locked decision per `tasks/TASK-008.md` lines 21–23).
- The verification flow has to compose with three established platform behaviors:
  - The escalation cascade in `app/services/onboarding_flow/escalation_cascade.rb` fans out to fallback emails (raw strings on `Responsibility#fallback_contact_emails`, not Contact FKs).
  - `SubmissionPromptSenderJob` already gates on `SubmissionPrompt#status` — it's not naturally per-contact.
  - `Accountability::DigestAssembler` emits one of five status slugs per row.

### Technical Constraints

- **Existing encryption pattern**: `Contact#email` and `Tenant#gm_email` both use `encrypts :<col>, deterministic: true` (cited: `app/models/contact.rb:5`, `app/models/tenant.rb:5`). The deterministic flavor is reserved for fields the system needs to look up exactly (uniqueness scope, dedup-by-email). PII without lookup needs lands in non-deterministic encryption.
- **Single platform-wide encryption key at MVP** (productBrief.md line 174–177). Per-tenant keys deferred. PII listed for MVP encryption: customer email and phone on inbound leads.
- **`phonelib` is NOT in the Gemfile today** (verified). Adding a new gem is a real cost: bundle audit footprint, CI cold-cache hit, and the project's omakase posture means we should justify each addition.
- **Tenant scoping is enforced by signed_id**: the verification controller looks up the contact by its purpose-scoped signed_id, which encodes the record's primary key — tenant scoping is structural rather than via `Current.tenant` in the no-login path. Established in `Contact#invitee_setup_signed_id` (`app/models/contact.rb:57–63`) and `Submissions::FormsController`.
- **FlowEvent atomicity** (`_learned/audit-trail.md`): every state-mutation crossing a system boundary writes a `FlowEvent` inside the same transaction. Verification dispatch and verification completion are both boundaries.
- **Idempotency** (`_learned/idempotency.md`): re-running the trigger path must not double-send. The available pattern is "read FlowEvent log, short-circuit if `contact.verification_invited` already present" (this is the same pattern `EscalationDetectorJob` uses against `escalation.*` events).
- **Service-shape conventions** (`_learned/namespacing.md`, `_learned/service-shape.md`): services live under `Contacts::` (plural to avoid the Zeitwerk collision the TASK-002 reflection caught) or `OnboardingFlow::`, and any service with multiple outcomes returns a `Struct.new(..., keyword_init: true)` value object.

### Non-Functional Requirements

- **Security / PII**: phone numbers are PII per productBrief.md line 174. Names are listed as *not* encrypted at MVP ("Other PII (names, addresses, VINs, free-text notes) is not encrypted at MVP"). Decisions must align.
- **Tenant isolation**: signed_id tenant scoping is sufficient for the no-login form. Any new query path must remain tenant-scoped.
- **Idempotency**: form re-submission, link re-click, and trigger re-fire are all expected; none may double-write or double-send.
- **Audit trail**: every verification event must be queryable from `flow_events`.

## Component Analysis

### Core Components

| Component | Purpose | Responsibilities |
|-----------|---------|------------------|
| `Contact` model (extended) | Persistence + derived verification predicate | `first_name`, `last_name`, `phone` columns; `verified?` and `unverified?` predicates derived from field presence; `verification_signed_id` + `find_by_verification_signed_id` helpers (purpose `:contact_verification`) |
| `Contacts::VerificationsController` | No-login signed-link form | `:show` (render form), `:update` (apply changes inside a transaction with FlowEvent), expired/invalid signed_id renders 404 |
| `OnboardingFlow::VerificationDispatcher` (service) | Idempotent invitation send | Reads FlowEvent log; if no `contact.verification_invited` event for this contact, queues `ContactVerificationMailer.invitation_email.deliver_later` and writes the FlowEvent in the same transaction |
| `Contacts::PhoneNormalizer` (PORO) | Phone → E.164 with explicit fallback | Strips formatting; if input matches a 10-digit US pattern, prefixes `+1`; otherwise rejects. No `phonelib` gem. See Q4 below for justification. |
| Gating boundary: `OnboardingFlow::EscalationCascade.fallback_emails_for` | Filter unverified out of fallback fanout | Look up `Contact` records by `email_normalized` for each fallback email string in the responsibility's tenant scope; drop ones where `verified?` is false |

### Component Interactions

```
OnboardingMailbox#handle_assignment
  └─ Contact.find_or_create_for_email
       └─ OnboardingFlow::VerificationDispatcher.call(contact: c)
            ├─ FlowEvent.where(subject: contact, event_type: "contact.verification_invited").exists? ─┬─ true → no-op
            └─ false                                                                                   │
                ├─ ContactVerificationMailer.with(contact: c).invitation_email.deliver_later          │
                └─ FlowEvent.record!(event_type: "contact.verification_invited", subject: c) ─────────┘  (same tx)

Contact clicks link
  └─ Contacts::VerificationsController#show (verifies signed_id, renders form)
  └─ Contacts::VerificationsController#update
       └─ ApplicationRecord.transaction:
            ├─ contact.update!(first_name:, last_name:, phone: normalized_phone)
            └─ FlowEvent.record!(event_type: "contact.verified", subject: contact)

EscalationCascade.fallback_emails_for(prompt)
  └─ existing array of fallback email strings
  └─ filter: tenant.contacts.where(email_normalized: email).take&.verified? != false
       └─ contacts that aren't on the contacts table at all → KEEP (legacy GM-typed emails)
       └─ contacts that exist and are verified → KEEP
       └─ contacts that exist and are unverified → DROP
```

## Options Explored

---

### Q3 — Schema relationship between `display_name` and the new fields

**Critical empirical finding (codebase audit):**
- `display_name` is declared in `db/migrate/20260503180602_create_contacts.rb:9` and present in `db/schema.rb:64`.
- `grep -rn '\.display_name\|display_name:' app/ spec/` returns **zero matches**. Nothing in the application or test suite reads or writes this column. It is dead schema.
- `Contact#name` does not exist. The task description's "split `Contact#name` into first/last" is based on a stale memory of this column.

#### Option Q3-A: Drop `display_name` entirely; add `first_name`, `last_name`, `phone` as the only identity fields
- **Description**: One migration removes the unused `display_name` column and adds three new columns. `Contact` exposes a `full_name` predicate method (`"#{first_name} #{last_name}".strip.presence`) for views that need a single rendered name.
- **Pros**:
  - No dead schema. The column the system actually relies on is the column it has.
  - Removes the trap: a future feature could plausibly start writing to `display_name` and create a second source of truth for "what's this contact's name."
  - Existing email rendering paths (`_gm_nudge.html.erb:13`, `_fallback_fanout.html.erb:9`) currently show raw email — they would either keep showing email or be updated to prefer `full_name` when verified. No regression because nothing reads `display_name` today.
- **Cons**:
  - One extra migration step (drop column) bundled with the additions.
  - If a future feature wants "best-effort header-parsed name fallback before verification", it needs a re-add. (Per spec scope boundary: "AI-assisted name parsing from `display_name` — out of scope; contact fills in manually.")
- **Technical Fit**: High — matches the project's "dead code is worse than missing code" omakase posture.
- **Complexity**: Low.
- **Future-proofing**: High — single source of truth for identity.

#### Option Q3-B: Keep `display_name`; add `first_name`, `last_name`, `phone` alongside
- **Description**: Three additive columns; `display_name` lingers as a "future header-parsed display fallback."
- **Pros**:
  - Lowest-risk migration (no DROP).
  - Preserves the option of populating `display_name` from inbound email From header parsing later.
- **Cons**:
  - **Two name fields with overlapping meaning is the textbook way to grow inconsistency.** Any view rendering a contact will need a "which one wins" rule, and that rule will accumulate special cases.
  - The column is dead today and adding three more "right" columns next to it makes it more dead, not less.
  - Violates the project's productBrief.md scope boundary that excludes header-parsed name AI for MVP — keeping the column "for future use" is speculative scaffolding.
- **Technical Fit**: Medium — additive is safe, but cohabitation with three new identity fields is muddy.
- **Complexity**: Low (migration), Medium (downstream — every view that renders a contact needs to choose a precedence rule).
- **Future-proofing**: Low — defers the question rather than answers it.

#### Option Q3-C: Rename `display_name` → `name` and add `first_name`, `last_name`, `phone`
- **Description**: Treat `display_name` as a typo for `name` (which the task description implied), then add the new fields.
- **Pros**:
  - Aligns the column to the task description's mental model.
- **Cons**:
  - The task description was working from a stale memory; the schema reality is that no `name` column was ever populated. Renaming an empty unused column is busywork that creates a new "what is `name` versus `first_name + last_name`" question.
  - Same downstream confusion as Q3-B but with worse semantics (`name` is even more ambiguous than `display_name`).
- **Technical Fit**: Low.
- **Complexity**: Low.
- **Future-proofing**: Low.

**Chosen**: **Q3-A — Drop `display_name`; add `first_name`, `last_name`, `phone` as the canonical identity columns.** The `display_name` column is dead schema; cohabiting it with three new identity fields would create a permanent precedence rule that nobody benefits from at MVP. Removing it in the same migration that adds the new fields keeps the contacts table to one source of truth for identity. The migration is reversible (re-add nullable string on rollback), and zero data is lost because zero rows have ever populated it (no factory, no controller, no service writes to it). If a future feature needs header-parsed name fallback, re-adding a column is cheap — keeping a misleading one for years is not.

**Implementation notes:**
- Migration: `RemoveDisplayNameFromContactsAndAddIdentityFields`
  - `remove_column :contacts, :display_name, :string` (reversible because we provide the type)
  - `add_column :contacts, :first_name, :string`
  - `add_column :contacts, :last_name, :string`
  - `add_column :contacts, :phone, :string` (encryption is via Rails `encrypts`, no separate `_ciphertext` column needed — Rails 7+ handles this in-column)
- Model:
  - `Contact#verified?` → `[first_name, last_name, phone].all?(&:present?)`
  - `Contact#unverified?` → `!verified?`
  - `scope :verified, -> { where.not(first_name: [nil, ""]).where.not(last_name: [nil, ""]).where.not(phone: [nil, ""]) }` — note that `phone` is encrypted non-deterministically (per Q4), so the scope works but won't index efficiently. That's fine because the scope is rarely the entry point — gating reads happen one contact at a time via `verified?`.
  - `def full_name = "#{first_name} #{last_name}".strip.presence`
- Validations on `Contact`: deliberately *no* presence validation on `first_name`/`last_name`/`phone` at the model level. The whole point of the derived `verified?` predicate is that contacts can exist in the unverified state. Field-level required-on-submit validation belongs on the `Contacts::VerificationForm` form object (or directly in the controller `permit` + manual presence check) — see Phase 2.
- Factory updates (`spec/factories/contacts.rb`):
  - Default factory stays unverified (matches the "fresh from CC" reality).
  - `trait(:verified) do first_name { "Alex" }; last_name { "Rivera" }; phone { "+15551234567" } end`
  - `trait(:unverified) do first_name { nil }; last_name { nil }; phone { nil } end` (explicit no-op trait for readability at call sites).

---

### Q2 — Gating semantics

The candidates from the task spec were: **(A)** suppress escalation fanout, **(B)** hold submission prompts, **(C)** `:pending_verification` digest status, **(D)** visual flag only.

#### Option Q2-A: Suppress escalation fanout to unverified contacts
- **Description**: `EscalationCascade.fallback_emails_for(prompt)` filters its return value: for each email string, look up the matching `Contact` in the responsibility's tenant; drop the email if the contact exists and `unverified?`. Emails that don't match a contact at all (e.g., the GM typed a raw email that hasn't been promoted to a Contact yet) keep the existing pass-through behavior.
- **Pros**:
  - **Highest user-protective value at lowest code cost.** The escalation fanout is the moment the platform starts pinging strangers; gating it on verification means an un-verified contact never gets dragged into a "you're overdue" email cascade for a responsibility they haven't acknowledged.
  - Fits the existing seam exactly: `fallback_emails_for` is a single private method, returning an array. The filter is one `select` block plus one query.
  - The cascade already reads tenants and FlowEvents — adding a `Contact.where(email_normalized: ..., tenant: ...)` query is the same shape.
  - Composable: if a contact later verifies, the next cascade tick automatically picks them back up. No state drift, no explicit "re-include them" job.
  - Tests cleanly: one new spec case in `escalation_cascade_spec.rb` flips a fallback contact to unverified and asserts the cascade skips them.
- **Cons**:
  - When all fallbacks are unverified and the primary lapses, the cascade falls through to GM nudge faster — which is arguably correct (the GM should know there's nobody verified to chase) but should be acknowledged in the UJ design.
  - Introduces the first cross-table read in `EscalationCascade`. Mitigation: `tenant.contacts.where(email_normalized: <list>).index_by(&:email_normalized)` once per `next_action_for` call — bounded by `fallback_contact_emails.length` (typically ≤ 3).

#### Option Q2-B: Hold submission prompts to unverified contacts
- **Description**: `SubmissionPromptSenderJob` filters the contacts it sends to.
- **Pros**:
  - Stops unverified contacts from receiving anything at all until they verify.
- **Cons**:
  - **Submission prompts already go to the source's `configured_by_contact`, not to fallbacks** — the unverified case for *that* contact is rare (they had to click through setup to become `configured_by_contact`, which is itself a verification-equivalent act).
  - The natural unverified persona at MVP is a CC'd fallback who hasn't acted yet, not a primary submitter. Gating prompts misses the actual problem.
  - Risks creating a deadlock: contact never gets a prompt → never has a reason to verify → never gets prompted → ...
- **Technical Fit**: Medium. **Value per LOC**: Low.

#### Option Q2-C: New `:pending_verification` digest status
- **Description**: `Accountability::DigestAssembler` adds a sixth status slug. When a responsibility's primary contact is unverified, the digest row shows `:pending_verification` instead of (e.g.) `:pending_first_submission`.
- **Pros**:
  - Surfaces verification state to the GM in their weekly digest — they see "Alex hasn't verified yet" before chasing.
- **Cons**:
  - The digest's existing five statuses are about *submission lifecycle* (pending_setup → pending_first → on_time → late → overdue). Verification is orthogonal to that ladder.
  - Adding a sixth slug forces every status-rendering partial to handle it; new strings, new copy, new test surface.
  - At MVP, the GM nudge in the escalation cascade *already* names fallback chain members by email — the GM can see who's involved without a new digest concept.
- **Technical Fit**: Medium. **Value per LOC**: Medium. Better as a Phase 2 follow-up if the GM's feedback is "I want to see verification state in the digest."

#### Option Q2-D: Visual flag only (no behavioral change)
- **Description**: Admin views show a "pending verification" badge; no behavior changes.
- **Pros**:
  - Zero risk to in-flight flows.
- **Cons**:
  - Provides no actual user value. The unverified contact still gets escalation emails for responsibilities they've never acknowledged.
  - "We added a database column and a flag" is not a feature.

#### Option Q2-A+C: Combined — suppress fanout AND emit a digest status
- **Description**: Both A and C.
- **Pros**: Belt + suspenders.
- **Cons**: C's marginal value is low (above) and it doubles the number of new tests, partials, and copy decisions.

**Chosen**: **Q2-A — Suppress escalation fanout to unverified contacts.** This is the single highest-leverage gate: it directly protects a user persona (a CC'd fallback who hasn't acknowledged the responsibility) from receiving "you're overdue" emails about something they haven't even registered exists. The implementation seam is one private method (`EscalationCascade.fallback_emails_for`), the cross-table query is bounded and tenant-scoped, and the gate is naturally self-healing — when a contact verifies, they're automatically re-included on the next cascade tick. The other candidates either solve the wrong persona's problem (B), add cosmetic surface without behavior change (D), or are better deferred until GM digest feedback warrants them (C).

**Implementation notes:**
- File to touch: `app/services/onboarding_flow/escalation_cascade.rb`, method `fallback_emails_for(prompt)` (currently lines 146–150).
- New filter:
  ```ruby
  def self.fallback_emails_for(prompt)
    raw = Array(active_responsibility_for(prompt)&.fallback_contact_emails)
    return raw if raw.empty?

    contacts_by_email = prompt.tenant.contacts
      .where(email_normalized: raw)
      .index_by(&:email_normalized)

    raw.reject { |email| contacts_by_email[email]&.unverified? }
  end
  ```
- Pass-through semantics: an email string that doesn't match any Contact (e.g., a GM-typed raw email that hasn't been promoted yet) is **kept** — we only suppress *known* unverified contacts. This preserves the existing escalation-to-strangers behavior the platform already has.
- Tests: extend `spec/services/onboarding_flow/escalation_cascade_spec.rb` with one example: "skips fallback when matching contact is unverified" and one regression: "keeps fallback when matching contact is verified" and "keeps fallback when no matching contact exists."
- No change to `EscalationDetectorJob`, no change to `_fallback_fanout` partial copy.

**Out-of-scope explicit non-decisions (per CLAUDE.md "no error handling for scenarios that can't happen"):**
- We do *not* gate the GM nudge — the GM is by definition verified (their email is the tenant's gm_email).
- We do *not* introduce a "the entire fallback chain is unverified, what do we do?" branch. The cascade already handles the empty-fallbacks case (line 104: skips fanout, goes straight to gm_nudge). Filtering all fallbacks out is observationally the same as having none.

---

### Q4 — Phone storage, encryption, validation, normalization

#### Option Q4-A: Free-form string, presence-only validation
- **Description**: `phone` is a plain `string` column, validated only as non-blank in the form. Stored as the user typed it.
- **Pros**: No new gem, no new library, simplest possible.
- **Cons**:
  - Productbrief.md and the task spec both call out Twilio as the future SMS provider. Twilio requires E.164. Storing free-form means a future migration touches every row.
  - Same number entered as `(555) 123-4567` and `555-123-4567` would be stored as different strings — duplicates would not collide.
  - PII storage with no encryption violates productBrief.md line 174.

#### Option Q4-B: `phonelib` gem + E.164 normalization on write, deterministic encryption
- **Description**: Add `phonelib` to the Gemfile. `before_validation` callback parses the input, raises if invalid, stores the E.164 form. `encrypts :phone, deterministic: true`.
- **Pros**:
  - Battle-tested international parsing (`phonelib` wraps Google's libphonenumber).
  - Deterministic encryption enables exact-match queries (e.g., "is this Twilio inbound SMS from a known contact?").
- **Cons**:
  - `phonelib` pulls in `libphonenumber` data files (~2MB of tables) and is one more gem CI has to install.
  - **Deterministic encryption is overkill for the actual MVP query pattern.** The phone is captured for *future* Twilio outbound use; it's not queried in the verification feature itself. We should not pay deterministic encryption's "this exact ciphertext matches this exact ciphertext" optimization until a feature actually does that lookup.
  - Adds a new dependency for a single field. The project's posture (omakase Rails + only 8 non-default gems) suggests we lean toward in-house when the rule is simple.
  - International phone numbers are not in scope for MVP (US-only dealerships). `phonelib`'s value is in handling 200+ country dialing rules — most of which we'll never see.

#### Option Q4-C: Hand-rolled US-E.164 normalizer + non-deterministic `encrypts :phone`
- **Description**: A small `Contacts::PhoneNormalizer` PORO. Strips all non-digits. If the result is exactly 10 digits, prefix `+1`. If exactly 11 digits and starts with `1`, prefix `+`. Otherwise, return `nil` (invalid). Encrypt the column with `encrypts :phone` (non-deterministic — Rails defaults to non-deterministic when the option is omitted).
- **Pros**:
  - **Zero new gems.** The full normalizer is ~10 lines of Ruby plus a short spec.
  - Matches the verification form's actual input shape: a US dealership's GM CC'ing a US contact.
  - Non-deterministic encryption is the right default for a field that is captured-for-later-use rather than queried — it's stronger against ciphertext-frequency analysis and matches the productBrief.md MVP "encrypt phone" requirement.
  - Forward-compatible: when Twilio integration ships and needs deterministic lookup-by-phone, it's a one-line change to `deterministic: true` plus a backfill (and a `phonelib` introduction at *that* point if international support is needed).
  - Validation error message is dictated by us — we control the UX without inheriting `phonelib`'s error catalog.
- **Cons**:
  - Hand-rolled validators have a long history of being subtly wrong. Mitigation: the rule is genuinely simple (10 digits → +1, 11 digits starting with 1 → +, else invalid) and the test is exhaustive (a half-dozen format permutations + one obviously-invalid + one international-input-which-we-reject case).
  - Rejects international numbers. Mitigation: that matches the MVP scope (US dealerships); we add a one-line "valid US phone (10 digits)" hint to the form copy.

#### Option Q4-D: `phonelib` + non-deterministic encryption
- **Description**: Use `phonelib` for parsing/validation but encrypt non-deterministically.
- **Pros**: International-ready, future-Twilio-ready on the validation front.
- **Cons**: Inherits Q4-B's "new gem for a 10-line rule" complaint without the deterministic-encryption upside. Strictly worse than Q4-C for an MVP US-only feature.

**Chosen**: **Q4-C — Hand-rolled US-E.164 normalizer + non-deterministic `encrypts :phone`.** The rule is simple enough to write in ten lines of Ruby and verify exhaustively in spec; we're not going to do better than that with a 2MB gem dependency for an MVP US-only feature. Non-deterministic encryption matches the actual access pattern (write-once, render-on-edit-only, never-queried) and is strictly stronger than deterministic at-rest. When a future Twilio feature requires E.164 *and* lookup-by-phone *and* international support, that's the moment to pull in `phonelib` and migrate the column to deterministic — a known and bounded change. We're not pre-paying for it now.

**Implementation notes:**

- **New PORO**: `app/services/contacts/phone_normalizer.rb`
  ```ruby
  module Contacts
    module PhoneNormalizer
      Result = Struct.new(:normalized, :valid?, keyword_init: true)

      # Returns a Result. .valid? is false when the input cannot be reduced
      # to a US 10-digit number (with or without leading 1). Callers branch
      # on .valid?; the controller turns invalid into an HTTP 422 with a
      # field-level error.
      def self.call(input)
        return Result.new(normalized: nil, valid?: false) if input.blank?

        digits = input.to_s.gsub(/\D/, "")
        case digits.length
        when 10 then Result.new(normalized: "+1#{digits}", valid?: true)
        when 11 then digits.start_with?("1") ? Result.new(normalized: "+#{digits}", valid?: true) : Result.new(normalized: nil, valid?: false)
        else Result.new(normalized: nil, valid?: false)
        end
      end
    end
  end
  ```
  Returns a `Result` Struct per `_learned/service-shape.md`.

- **Encryption directive on `Contact`**:
  ```ruby
  encrypts :phone   # non-deterministic; no exact-match query needed at MVP
  ```
  Place this immediately below the existing `encrypts :email, deterministic: true` line for visual consistency.

- **Names are not encrypted at MVP**, per productBrief.md line 174 ("Other PII (names ...) is not encrypted at MVP"). `first_name` and `last_name` are plain string columns. This is an explicit decision recorded here so the build phase doesn't second-guess it.

- **No `phonelib` gem added** to the Gemfile. This is a deliberate non-dependency.

- **Validation/normalization happens in the controller's `:update` action**, not in a model `before_validation` callback. The reason: the model accepts and persists unverified contacts (where `phone` is `nil`) as a normal state. A `before_validation` callback that hard-fails on unparseable phones would interfere with `Contact.find_or_create_for_email` and other paths that don't touch phone at all. The verification form is the one and only ingress for phone data, so the normalization belongs there.

- **`Contacts::VerificationsController#update` shape**:
  ```ruby
  def update
    contact = find_contact_or_404
    permitted = params.require(:contact).permit(:first_name, :last_name, :phone)
    phone_result = Contacts::PhoneNormalizer.call(permitted[:phone])

    if permitted[:first_name].blank? || permitted[:last_name].blank? || !phone_result.valid?
      @contact = contact
      @errors = build_errors(permitted, phone_result)
      render :show, status: :unprocessable_entity
      return
    end

    ApplicationRecord.transaction do
      contact.update!(
        first_name: permitted[:first_name].strip,
        last_name: permitted[:last_name].strip,
        phone: phone_result.normalized
      )
      FlowEvent.record!(
        event_type: "contact.verified",
        tenant: contact.tenant,
        subject: contact
      )
    end

    redirect_to verification_completed_path  # or render confirmation
  end
  ```

## Evaluation Matrix (cross-question summary)

| Criteria | Q3-A drop+add | Q2-A fanout gate | Q4-C in-house normalizer |
|----------|---------------|-------------------|--------------------------|
| Scalability | High (no perf change) | High (1 indexed query per cascade tick) | High (synchronous, in-process) |
| Maintainability | High (one source of truth for identity) | High (one method change) | High (10 LOC, fully tested) |
| Security | N/A | High (protects unverified PII from entering escalation copy) | High (non-det encrypts; PII NFR met) |
| Observability | N/A | High (FlowEvent for cascade unchanged; per-fallback skip not logged) | High (FlowEvent on verification dispatch + completion) |
| Implementation Cost | Low | Low | Low |
| Future-proofing | High (no dead column) | High (self-healing on verify) | Medium (Twilio shift requires column migration to deterministic — but bounded) |

## Decision Summary

| Question | Chosen | One-line rationale |
|----------|--------|---------------------|
| Q3 Schema | **Q3-A**: drop `display_name`, add `first_name`, `last_name`, `phone` | `display_name` is dead schema; cohabiting it with three new identity fields is a permanent precedence-rule trap. |
| Q2 Gating | **Q2-A**: suppress escalation fanout to unverified contacts | Highest-leverage gate (protects an unverified persona from being chased) at the lowest code surface (one private method). |
| Q4 Phone | **Q4-C**: in-house US-E.164 normalizer + non-deterministic `encrypts :phone` | A 10-line rule and a non-deterministic at-rest encryption is the right MVP cost; a 2MB international-parsing gem is YAGNI. |

## Implementation Guidelines

1. **Migration first** (Phase 1). `RemoveDisplayNameFromContactsAndAddIdentityFields`. Reversible. Test that rollback restores `display_name` as nullable string.
2. **Model extensions** (Phase 1). `verified?` / `unverified?` predicates derived purely from field presence. `verification_signed_id(expires_in: 7.days)` + `find_by_verification_signed_id(signed_id)` — purpose `:contact_verification`. Encryption directive: `encrypts :phone` (non-deterministic).
3. **Factory**: default unverified, `:verified` trait sets all three. (Phase 1.)
4. **Phone normalizer PORO** (Phase 2). `Contacts::PhoneNormalizer` returns `Result` struct.
5. **Controller** (Phase 2). `Contacts::VerificationsController` mirrors `Submissions::FormsController` shape: `:show` loads via signed_id-or-404; `:update` runs the controller-level field-level validation, normalizes phone, writes Contact + FlowEvent in one transaction.
6. **Trigger dispatcher** (Phase 3). `OnboardingFlow::VerificationDispatcher.call(contact:)` reads FlowEvent log for `contact.verification_invited` on this contact's id; if absent, queues mailer + records the event in one transaction. Idempotent against double-promotion.
7. **Gating filter** (Phase 4). One method change in `EscalationCascade.fallback_emails_for`. Add the `index_by(&:email_normalized)` lookup, reject unverified.
8. **No new gems.** `phonelib` is deferred until a feature actually requires international parsing or deterministic phone lookup.

## Validation Checklist

- [x] Meets all system requirements (Q2 protects the unverified-fallback persona; Q3 single source of truth; Q4 stores E.164 phone encrypted at rest).
- [x] Respects technical constraints (deterministic encryption only where lookup is needed; phone is non-det per MVP access pattern).
- [x] Addresses NFRs: PII encryption (Q4), tenant isolation (signed_id scope; cascade query is `prompt.tenant.contacts`), idempotency (FlowEvent log read in dispatcher), audit trail (FlowEvent on dispatch + completion in same tx).
- [x] Technically feasible — every seam is a small change to existing files, no new infrastructure.
- [x] Risks identified and acceptable (see Risk Assessment).
- [x] Complies with Guiding Principles in `systemPatterns.md`:
  - Single accountability with named fallbacks (P2): preserved — gate filters, never reassigns.
  - Tenant isolation is structural (P5): cascade lookup uses `prompt.tenant.contacts`; verification controller uses signed_id which encodes the record FK.
  - Idempotent inbound handling (P7): VerificationDispatcher reads FlowEvent log before sending; controller `update` is last-write-wins at the column level (re-submitting same values is a no-op write).
- [x] Respects established patterns: signed_id purpose-scoping, `_learned/service-shape.md` Struct value objects, `_learned/audit-trail.md` FlowEvent atomicity.

## Risk Assessment

| Risk | Likelihood | Impact | Mitigation |
|------|------------|--------|------------|
| Hand-rolled phone normalizer rejects a valid edge case (e.g., toll-free vanity number) | Medium | Low | Exhaustive spec on the normalizer's case statement; vanity-number rejection produces a form-level error the user can correct. The fix is a one-line change if a real case shows up. |
| Dropping `display_name` breaks a future feature that wanted header-parsed name fallback | Low | Low | Re-adding a nullable string column is trivial. The feature isn't on the roadmap and is explicitly out-of-scope for this task. |
| Cross-table query in `EscalationCascade.fallback_emails_for` adds latency to `next_action_for` | Low | Low | Bounded by `fallback_contact_emails.length` (≤3 typical). Index on `(tenant_id, email_normalized)` already exists (schema.rb:70). One indexed lookup per cascade tick. |
| Deterministic encryption is needed later (Twilio inbound SMS lookup-by-phone) and we have to migrate | Medium | Medium | Migration is bounded: change the directive, run a backfill (`Contact.find_each { |c| c.update!(phone: c.phone) }`). Acceptable cost paid only when the feature actually warrants it. |
| Verification form re-submission with new values silently overwrites old verified fields | Low | Low | Last-write-wins is the documented behavior in the task spec ("re-submitting new values updates the record (last-write-wins is acceptable for a self-service identity form)"). FlowEvent log captures every write. |
| Concurrent verification dispatch (e.g., two GM CCs of the same email arriving in quick succession) double-sends invitation | Low | Medium | `VerificationDispatcher` reads `FlowEvent.where(subject: contact, event_type: "contact.verification_invited").exists?` before dispatch. Race window is small but technically present. If observed, harden with a `find_or_create_by!` on a unique `(contact_id, event_type)` partial index — deferred until evidence. |

## Next Steps

1. Build phase Phase 1 (Schema + Model) implements Q3-A migration, model extensions, and factory traits.
2. Build phase Phase 2 (Mailer + Controller) implements Q4-C normalizer and controller shape.
3. Build phase Phase 3 (Trigger) wires `VerificationDispatcher` into `OnboardingMailbox#handle_assignment`.
4. Build phase Phase 4 (Gating) implements Q2-A in `EscalationCascade.fallback_emails_for`.
5. The User Journey agent (running in parallel) resolves Q1 (Trigger UX) and Q5 (Re-prompt cadence). Their decisions may add or refine Phase 5; this architecture document does not pre-empt those choices.

ARCHITECTURE CREATIVE COMPLETE
Document: memory-bank/creative/TASK-008-architecture.md
Decision: Drop dead `display_name`, add three identity columns; gate via `EscalationCascade.fallback_emails_for` filter; in-house US E.164 normalizer with non-deterministic phone encryption; no `phonelib` gem.
