# Architecture Decision: TASK-001 Tenant + GM Email-First Onboarding

**Created**: 2026-05-03
**Status**: DECIDED
**Decision Type**: Architecture (four bundled questions)
**Task**: TASK-001 (FEAT-001)
**Complexity**: Level 4

## Context

This document resolves four LOW-confidence architecture questions for the email-first onboarding feature. Each decision is load-bearing for Phase 1 (data model) or Phase 4 (inbound routing) of the build roadmap.

### Guiding Principles in scope (from `systemPatterns.md`)
- **GP1 — Email is first-class.** Action Mailbox is platform infrastructure, not peripheral.
- **GP2 — Single accountability with named fallbacks.** Data model has exactly one primary + ordered fallbacks.
- **GP3 — Raw payload retention is the source of truth.** Inbound stored verbatim, indefinitely.
- **GP4 — Schema versioning is opt-in per adapter.** No version retired while adapters target it.
- **GP5 — Tenant isolation is structural.** Every tenant model has `tenant_id NOT NULL` + index.
- **GP6 — AI artifacts have a named human approver.**
- **GP7 — Idempotent inbound handling.** Re-delivery of same Message-ID = no-op.

### Constraints
- Rails 8.1.3 monolith, single Postgres 18, Action Mailbox + Solid Queue.
- MVP marketing-only catalog; sales/service deferred but the design must accommodate them.
- Production inbound provider deferred (`Postmark / Mailgun / SendGrid` — all support plus-addressing; subdomain wildcards have provider-specific quirks).
- The same addressing scheme must serve **two** surfaces: onboarding (this task) and lead ingestion (FEAT-002).
- Single platform-wide encryption key; no BYOK.

---

## A1. Action Mailbox addressing scheme

### Context
The platform needs two distinct inbound surfaces (per `systemPatterns.md` "Inbound Email Routing"):
- **Onboarding threads**, per-tenant: `onboarding+<tenant_token>@inbound.rogue.example`
- **Lead ingestion**, per-(tenant, source): `lead+<source_token>@inbound.rogue.example` (FEAT-002)

The decision affects DNS strategy, production ingress provider compatibility (Postmark / Mailgun / SendGrid), DKIM/SPF/DMARC setup, deliverability, and how tightly mail clients preserve the `+` segment when GMs hit Reply.

### Options

**Option A — Plus-addressing on a single inbox domain.** All inbound flows to one MX (`inbound.rogue.example`). Routing tokens live in the local-part after a `+`: `onboarding+<tenant_token>@…`, `lead+<source_token>@…`. Action Mailbox routing rules use regex on the local-part prefix.
- Pros:
  - All three candidate ingress providers (Postmark / Mailgun / SendGrid) accept and forward plus-addressed mail without provider-specific config; the local-part is opaque to the SMTP layer.
  - Single MX record + single set of DKIM/SPF/DMARC records to manage. Single deliverability story.
  - Cheapest: one inbound route at the provider, regardless of tenant count.
  - Action Mailbox routing trivial: `routing /^onboarding\+/i => :onboarding`, `routing /^lead\+/i => :lead_ingest`.
- Cons:
  - Some mail clients display the `+` segment in a confusing way (Outlook desktop occasionally shows the full address; Gmail collapses it). Cosmetic, not functional.
  - A small share of misconfigured corporate mail filters (≈1-2% historical observation) strip plus-addressing on outbound; mitigation: when a GM's reply lacks the `+token`, we can fall back to `In-Reply-To` to recover the thread (we already index `Message-ID` on the question email).
  - Token leakage in `From:` of ack emails — anyone CC'd on an onboarding thread sees the tenant token. **This is acceptable** because the token is opaque (base58, non-PK, not derivable) and only confers ability to reply on that specific thread (where the GM-only gate further restricts mutation).
- Evaluation: Best fit for "ship now, switch providers later." Zero provider-coupling.

**Option B — Per-tenant subdomain.** Each tenant gets its own subdomain: `onboarding@<tenant_slug>.inbound.rogue.example`. Routing tokens move from the local-part to the host-part.
- Pros:
  - Each tenant's inbound surface looks bespoke ("smith-toyota.inbound.rogue.example" reads more professionally to a GM than "+abc123def").
  - Cleaner reply UX in mail clients (no `+` segment).
  - Per-tenant DKIM keys become possible — useful eventually for white-labeled inbound, not at MVP.
- Cons:
  - Requires **wildcard MX** at `*.inbound.rogue.example`. Postmark and SendGrid support wildcard inbound but require explicit config; Mailgun supports it but bills per route depending on plan tier.
  - DKIM/SPF/DMARC story is more complex — wildcard TXT records, alignment checks against the parent domain.
  - Action Mailbox routing must extract from the host part (less natural — Action Mailbox routing is local-part-first).
  - Tenant slugs must be globally unique (not just within Rogue's namespace) and stable. Adds a slug-generation rule and reservation table to Phase 1 — extra surface, extra collision logic.
  - Migrating tenants between subdomains (rebrand, slug typo) is painful — every existing email thread points at the old subdomain.
- Evaluation: Marginal UX gain at significant operational cost. Locks us into earlier provider selection.

**Option C — Dedicated MX per Tenant.** Each tenant has its own MX (`inbound.smith-toyota.com` or similar).
- Pros:
  - Maximally white-label; tenant feels like the email originated from "their" domain.
- Cons:
  - Operationally extreme: tenant-managed DNS, per-tenant DKIM key provisioning, per-tenant deliverability monitoring.
  - At MVP we have ~1 tenant; this is overhead for zero current benefit.
  - Inconsistent with "one manual step on Rogue's side" goal — Rogue staff would need to bootstrap DNS records per tenant.
- Evaluation: Reject. Re-evaluate post-100-tenants if a customer demands white-label.

**Option D — Hybrid (subdomain for tenants, plus-addressing within tenant).** `onboarding+<tenant_token>@inbound.rogue.example` for onboarding (plus-addressing); but for FEAT-002 lead ingestion, use `<source_token>@<tenant_slug>.lead.rogue.example` (subdomain for tenant, local-part for source).
- Pros: separates the two surfaces visually and gives lead-ingestion white-label-ish per tenant.
- Cons: combines the operational costs of A and B. Most complex routing story. Unjustified at MVP scale.
- Evaluation: Reject as YAGNI.

### Decision
**Chosen: Option A — plus-addressing on a single inbox domain.**

Plus-addressing is the only option that lets us defer the production ingress provider decision (it works on Postmark, Mailgun, and SendGrid identically) while keeping the routing logic in one regex per surface. The cosmetic objections to the `+` segment are real but low-impact — and we have a robust fallback (`In-Reply-To` lookup against persisted question `Message-ID`s) for the ≤2% of mail filters that strip plus-addressing.

Trade-offs accepted:
- **No per-tenant white-label inbound at MVP.** Acceptable: productBrief never promised this; the platform's value proposition is operational efficiency, not vanity domains.
- **Tenant token visible in `From:` headers.** Acceptable because the token is opaque (base58, never derived from PK or PII), confers no read/mutate capability without the GM-only thread gate, and a malicious actor with the token can only generate noise (Action Mailbox archives + GM-only gate filters non-GM senders).
- **Both surfaces share one MX.** This is actually a feature — one inbound provider integration, one DKIM key, one bounce-handling story.

The Option D hybrid is rejected because both surfaces benefit from identical operational treatment, and FEAT-002's lead-ingestion source addresses also belong on `inbound.rogue.example` to preserve provider flexibility.

### Implementation guidance
- **Domain**: `inbound.rogue.example` (placeholder; real domain set at operational cutover and stored in `Rails.application.credentials.inbound_email_domain` — never hardcoded).
- **Token columns**:
  - `tenants.onboarding_token` — `string`, `null: false`, unique index. Generated via `SecureRandom.base58(16)` at create time. **Persisted, opaque, never derived from PK or PII.** (16 chars of base58 ≈ 93 bits of entropy — enough that brute-forcing is uneconomic and the address still fits comfortably in a typical mail client's display width.)
  - `sources.lead_token` (FEAT-002, but stub the column on the migration map) — same shape.
- **Routing in `config/application_mailbox.rb`**:
  ```ruby
  routing(/^onboarding\+[\w]+@/i => :onboarding)
  routing(/^lead\+[\w]+@/i       => :lead_ingest) # FEAT-002 placeholder
  routing(/^onboarding@/i         => :onboarding) # fallback for stripped plus-addressing
  ```
  The fallback routes to `OnboardingMailbox` which then performs `In-Reply-To` lookup against `outbound_emails.message_id` to recover the tenant.
- **Outbound `From:` and `Reply-To:`** on every onboarding email set to `"#{tenant.dealership_name} Onboarding <onboarding+#{tenant.onboarding_token}@#{Rails.application.credentials.inbound_email_domain}>"` so reply lands back at the right tenant.
- **Address builder helper**: `Tenant#onboarding_address` and `Tenant#onboarding_reply_to` (both pull from credentials, never hardcoded — 12-Factor).
- **Test helper**: `addresses_for(tenant)` factory method that returns the same address shape used by `OnboardingMailer` and asserts route matches; reused across mailer + mailbox tests.

---

## A2. Question Catalog data model

### Context
The Question Catalog drives the GM-onboarding interview. The decision affects:
- productBrief Open Question 1 (rolling onboarding — surfacing catalog deltas to existing tenants).
- Whether copy edits require a deploy.
- How `SkippedQuestion` and `Responsibility` rows reference the catalog (FK to a row vs. string slug).
- What happens when the catalog evolves while a Tenant is mid-onboarding.

### Options

**Option A — DB-backed `questions` table.** Each question is a row with version columns; admin CRUD ships with a seed file.
- Pros:
  - Edits without deploy.
  - Trivial to point a `Responsibility.question_id` foreign key at a stable row.
  - Easy to back an A/B test by adding a `variant` column.
- Cons:
  - Without versioning discipline, an in-flight edit can mutate the question a GM is currently answering. **Requires explicit immutability rules** — questions become append-only-after-publish, edits create a new version row.
  - Seeds must be kept in sync with code that references questions by slug.
  - "Rolling onboarding" still requires diff logic between catalog versions; the table form doesn't make this free.

**Option B — Code-defined Ruby module.** Catalog defined in `lib/rogue/question_catalog/marketing/v1.rb`; Tenant pins a version.
- Pros:
  - Versioning is git-native — `v1`, `v2`, `v3` are file revisions; the diff is in source control.
  - No drift between code and seed file.
  - Trivially testable in isolation.
  - Aligns with GP4 (schema versioning is opt-in per adapter) — Tenants pin a catalog version analogous to adapters pinning a schema version.
- Cons:
  - Copy edits require a deploy. For an MVP with one Rogue ops team and continuous deploy, this is fine; at scale it constrains marketing-team agility.
  - No first-class admin CRUD.
  - References from `Responsibility.question_slug` are by string slug, not FK — losing referential integrity at the DB level.

**Option C — Hybrid: code-defined templates that materialize as DB rows when first activated for a Tenant.** Catalog versions live in `lib/rogue/question_catalog/marketing/vN.rb`; on Tenant confirm, the activation step materializes the pinned version's questions into `tenant_questions` rows (per-Tenant, per-question).
- Pros:
  - Versioning and editability of templates lives in code (with git history).
  - DB rows give referential integrity (`responsibilities.tenant_question_id` FK).
  - Skip / revisit / answered tracking is per-Tenant per-question — natural fit.
  - "Rolling onboarding" mechanic is concrete: when a new catalog version (e.g., `v2`) adds questions to a domain, a `RolloutCatalogDeltaJob` walks confirmed tenants and inserts new `tenant_questions` rows for any deltas. The Tenant remains pinned to their original version for already-asked questions.
  - A future admin CRUD can edit the *materialized rows* for a single Tenant without affecting the canonical template.
- Cons:
  - Two-step model (template + materialized row) is more code than either alternative alone.
  - Needs a clear rule: edits to materialized rows are tenant-scoped and never propagate back to the template.

### Decision
**Chosen: Option C — Hybrid (code-defined templates that materialize per-Tenant on activation).**

Three reasons drive this:

1. **Rolling onboarding becomes a concrete mechanic, not a TBD.** When the marketing team adds Q11 in `marketing/v2.rb`, a `RolloutCatalogDeltaJob` walks confirmed tenants whose pinned version < v2, materializes the new question rows, and enqueues a question email. Pure DB-backed (Option A) requires the same job *plus* a versioning discipline that has to be enforced by code reviews. Pure code (Option B) lacks the per-tenant state for "this Tenant has already been notified about Q11."

2. **Per-Tenant state needs DB rows.** `SkippedQuestion`, `revisited_at`, `answered_at`, the link to `Responsibility` — these are inherently per-Tenant per-Question and want referential integrity. Option B forces all of this into string-slug references; Option A gives us rows but requires strict version-pinning to prevent in-flight mutation. The hybrid gives us rows with the version-pinning baked into the activation step.

3. **Aligns with GP4 (schema versioning is opt-in per adapter).** Tenants pin to a catalog version exactly the way adapters pin to a schema version. Same mental model, same migration pattern.

Trade-offs accepted:
- **More code than either pure alternative.** Two concepts to learn (template + materialized row). Acceptable: the alternative is either runtime drift (A) or no per-tenant state (B), both worse.
- **Copy edits to canonical templates require a deploy.** Acceptable at MVP: single ops team, continuous deploy, no marketing-team self-service yet. A future admin UI can edit *materialized rows* for a single Tenant (e.g., custom pilot phrasing) without touching the template.
- **Catalog-delta rollout job is non-trivial.** Mitigation: it lives outside the MVP build path; we set up the templates and the materialization step in Phase 1, but the rollout job is a follow-up (productBrief explicitly calls "rolling onboarding" an Open Question — we resolve the *mechanism* here, defer the *first run* to a later task).

### Implementation guidance
- **Template files**: `lib/rogue/question_catalog/marketing/v1.rb` (and forward). Each defines a frozen array of question hashes:
  ```ruby
  module Rogue::QuestionCatalog::Marketing::V1
    VERSION = "marketing.v1"
    QUESTIONS = [
      { slug: "marketing_strategy", order: 1, prompt: "Who controls your marketing strategy?", responsibility_key: :marketing_strategy, default_metrics: [...] },
      { slug: "website_ownership",  order: 2, prompt: "Who manages your dealer website?",      responsibility_key: :website_ownership,  default_metrics: [...] },
      # ...
    ].freeze
  end
  ```
- **Materialization table** (`tenant_questions`):
  - `tenant_id` (FK, NOT NULL, indexed)
  - `catalog_version` (string, NOT NULL — e.g., `"marketing.v1"`)
  - `slug` (string, NOT NULL)
  - `domain` (enum: `:marketing | :sales | :service`, default `:marketing`)
  - `prompt` (text, NOT NULL — copy snapshot at materialization time)
  - `order` (integer, NOT NULL)
  - `state` (enum: `:pending | :asked | :answered | :skipped`)
  - `asked_at`, `answered_at`, `skipped_at`, `revisited_at` (timestamps, nullable)
  - `last_message_id` (string, nullable — outbound `Message-ID` of the question email, for inbound `In-Reply-To` resolution)
  - Unique index on `(tenant_id, catalog_version, slug)`.
- **Activation step**: `Tenant#activate_marketing_catalog!(version: "marketing.v1")` — invoked from `Onboarding::ConfirmationsController#show` after status transition. Reads the template module, inserts `tenant_questions` rows in a single transaction, sets `tenants.pinned_marketing_catalog_version = "marketing.v1"`.
- **`Responsibility` reference**: `responsibilities.tenant_question_id` (FK to `tenant_questions`, NOT NULL, indexed). Provides referential integrity at the DB layer; survives template churn.
- **`SkippedQuestion` model**: thin row that mirrors `tenant_questions.state = :skipped`. Persist as a separate table for historical clarity (state on `tenant_questions` is "current state"; `skipped_questions` is "was once skipped, even if revisited"). `tenant_questions.revisited_at` indicates the GM came back to it.
- **Catalog delta job** (deferred, but seam established): `Rogue::QuestionCatalog::RolloutDeltaJob` — walks tenants whose pinned version is older than the latest published version and inserts the new questions as `tenant_questions` rows. Idempotent on `(tenant_id, catalog_version, slug)`.
- **Question Catalog registry**: `Rogue::QuestionCatalog.versions` returns the loaded version modules; used by tests and by the rollout job to determine "latest." Versions are append-only — once published, never edited.
- **Test seam**: a `Rogue::QuestionCatalog::TestVersion` module under `test/support/` for tests that need a small fake catalog without depending on production copy.

---

## A3. Vendor roster seed strategy

### Context
The productBrief commits to "pre-seeded with a substantial roster of common automotive vendors before launch." Resolve: source of truth, size, schema, maintenance cadence. The accuracy of vendor inference at launch depends entirely on this roster — if the GM CCs `alex@vinsolutions.com` and `vinsolutions.com` isn't in the roster, the system asks an awkward clarification question. Density matters.

### Options

**Option A — Manually curated CSV in the repo.** A one-off curation effort produces `db/seeds/vendors/automotive_vendors.csv`; `db/seeds.rb` loads it. Updates land via PR.
- Pros:
  - Fully under code review; auditable history.
  - No external dependencies at deploy time.
  - Deterministic — the same Tenant onboarding produces the same vendor classifications across environments.
- Cons:
  - Manual curation effort upfront (the only one-time cost in this option).
  - Updates are deploy-gated.

**Option B — Bootstrap from first 100 inbound replies.** Launch with empty roster; every unrecognized domain triggers GM clarification, and accepted clarifications populate the canonical vendor list.
- Pros:
  - Zero curation effort; the data builds itself.
  - Every vendor in the roster is one a real customer actually uses.
- Cons:
  - **Catastrophic for early UX.** First N tenants face dozens of clarification questions; the email-first flow promises smoothness and this option ships a worse experience to the people who matter most.
  - Reject.

**Option C — Scrape from a known industry directory.** Pull from Auto Remarketing, NADA vendor directory, or similar.
- Pros:
  - Larger initial roster than manual curation.
- Cons:
  - Legally murky depending on the source's TOS.
  - Stale data immediately.
  - Schema mismatch — directories list "company name + headline service" but Rogue needs domain-to-vendor mapping which most directories don't expose.
- Evaluation: Reject as primary; could augment Option A.

**Option D — Manual curation seeded from product team's known-vendor list, with auto-promotion on inbound clarification.** Hybrid of A + a runtime growth mechanism: ship with a curated CSV (~150-250 entries), but every successful GM clarification ("yes, that's a vendor — add it as `Vendor: VinSolutions`") creates a new canonical Vendor row at runtime. Rogue staff can review and edit via a future admin UI.
- Pros:
  - Best of A's auditability and an organic growth path.
  - Productizes the AC-ERROR-4 round-trip (vendor disambiguation) — every awkward clarification question makes the next tenant's experience smoother.
  - Clear data shape from day one; CSV is the spec, runtime additions append.
- Cons:
  - Two write paths (seed-time and runtime) that must produce identical row shapes — easy to drift if not enforced.
  - Risk of tenant-suggested vendor names being inconsistent ("VinSolutions" vs. "Vin Solutions" vs. "VS Inc."); mitigation: runtime additions go to a `pending_review` state until a Rogue admin promotes them.

### Decision
**Chosen: Option D — Manually curated CSV + auto-promotion from runtime clarifications (with `pending_review` gating).**

The MVP needs immediate density (the email-first flow's value prop falls apart if every reply triggers a clarification round-trip), and it also needs a growth path that doesn't require Rogue staff to chase vendors forever. Option A alone gets us launch density but means staff curation is forever; Option D adds a self-sustaining mechanism.

The `pending_review` state is critical. Without it, GM-suggested vendor names (with their typos and inconsistencies) corrupt the canonical roster. With it, runtime additions accumulate as candidates that an admin promotes with a click — much lighter ongoing curation than open-ended discovery.

Trade-offs accepted:
- **Manual curation cost upfront.** Acceptable: scoped, time-boxed task by a domain-knowledgeable team member; one-time. Estimate ~4-8 hours for the initial 200-entry roster.
- **Two write paths.** Mitigation: a single `Vendor.bootstrap!(name:, domains:, source:, **attrs)` class method used by both seed loader and runtime clarifier; `source` enum (`:seed | :clarification | :admin`) records origin.
- **`pending_review` adds a workflow step.** Acceptable: zero blocking effect on tenants — once a vendor is `pending_review`, it still classifies subsequent CCs against the same domain correctly. The promotion is just metadata cleanup.

**Sizing decision**: target **~200 entries** for the initial roster. Rationale: covers the major automotive verticals (lead aggregators ~30, marketing/SEM agencies ~40, CRM/DMS providers ~20, inventory/merchandising ~15, F&I tech ~15, service-side ~25, social ~15, OEM-direct vendors ~30, regional/long-tail ~10). 200 is large enough to cover most CCs the first 50 tenants will produce; small enough that one person can curate and review in a single sitting. Anything below ~100 leaves too many gaps; anything above ~500 is hand-curation overkill at MVP scale.

### Implementation guidance
- **Schema** (`vendors` table):
  - `id`
  - `canonical_name` (string, NOT NULL — e.g., `"VinSolutions"`)
  - `domains` (string array `text[]` with GIN index, NOT NULL — e.g., `["vinsolutions.com", "vinsolutions.net"]`). Multiple because vendors often own variant domains.
  - `aliases` (string array, default `[]` — alternate display names: `["Vin Solutions", "VinSolutions Inc."]`)
  - `categories` (string array, default `[]` — e.g., `["crm", "dms"]`)
  - `parent_vendor_id` (FK to `vendors`, nullable — for vendor families like `Cox Automotive` → `Dealer.com`)
  - `regions` (string array, default `[]` — e.g., `["us", "ca"]` for vendors not globally available)
  - `state` (enum: `:active | :pending_review | :archived`, default `:active`)
  - `source` (enum: `:seed | :clarification | :admin`, NOT NULL)
  - `created_by` (string, nullable — `"seed"`, `"clarification:tenant_<id>"`, or `"admin:<email>"`)
  - `created_at`, `updated_at`
  - Unique index on `canonical_name` (case-insensitive, via `LOWER(canonical_name)`).
- **Seed file**: `db/seeds/vendors/automotive_vendors.csv` with columns `canonical_name,domains,aliases,categories,regions`. Loaded via `db/seeds.rb` (idempotent — uses `Vendor.find_or_create_by(canonical_name:)`).
- **`Vendor.bootstrap!`** class method: shared write path for seed and runtime. Validates domain-list non-empty for `:active`; allows empty for `:pending_review` (clarification might create a row before domains are confirmed).
- **Domain matching**: `Vendor.match_by_domain(email_domain)` — case-insensitive exact match against `domains` array, then walks `parent_vendor_id` to find the canonical parent (so `dealer.com` can resolve to its Cox Automotive parent if that's how Rogue wants to group). Returns the match or `nil`.
- **Auto-promotion on clarification** (`VendorInferenceService::Clarifier`): when GM replies `vendor: VinSolutions` to AC-ERROR-4, the clarifier calls `Vendor.bootstrap!(canonical_name: "VinSolutions", domains: ["unknownvendor.com"], source: :clarification, state: :pending_review, created_by: "clarification:tenant_#{tenant.id}")`. The Tenant gets normal `Source` / `Responsibility` creation; the row stays `pending_review` until promoted.
- **Curation tooling**: `bin/rails rogue:vendors:review_pending` rake task lists `pending_review` rows with their suggested domains, count of tenants that have been routed against them, and a one-line promote/archive prompt. Not a full admin UI at MVP; a follow-up task.
- **False-positive guard**: when two real vendors share a parent domain (rare but real — e.g., a generic ESP host that several agencies use), the `categories` field disambiguates. If domain matches multiple `:active` vendors, the inference service flags it `:ambiguous` and asks the GM to clarify which vendor specifically (same shape as AC-ERROR-4 round-trip).
- **Initial roster delivery**: scoped as a Phase 1 sub-task (not a separate creative phase). The CSV ships in the same commit as the migration.

---

## A4. Audit-event / lineage shape

### Context
Every state transition in onboarding (seed, confirm, question sent, reply received, ack sent, skip recorded, vendor clarification asked, etc.) needs to be auditable. The decision composes with FEAT-002's lead-ingestion lineage (every normalized record traces back to its raw payload + adapter version, per GP3) and the productBrief's accountability dashboard (which queries this data).

### Options

**Option A — One generic `OnboardingFlowEvent` table (polymorphic).** Single table with `event_type`, `subject_type`, `subject_id`, `actor_type`, `actor_id`, `payload jsonb`, `tenant_id`, `created_at`.
- Pros:
  - Simple. One table to query, one place to write.
  - Polymorphic enables logging events on any model (Tenant, Responsibility, Question, Source).
  - The accountability dashboard's "what happened recently for this Tenant" query is `WHERE tenant_id = ? ORDER BY created_at DESC` — fast with proper index.
- Cons:
  - `payload jsonb` is unstructured — schema drift over time as event types proliferate.
  - Polymorphic FKs aren't enforced at DB level; orphan risk if a subject is deleted.
  - Not transactionally tied to the domain mutation by default — risk of "event written, mutation rolled back" or vice versa unless carefully wrapped.

**Option B — Per-domain audit tables.** `tenant_events`, `responsibility_events`, `question_events`, etc. Each has its own typed columns.
- Pros:
  - Strongly typed schema per event family.
  - DB-level FK enforcement against the subject.
- Cons:
  - 5-10 tables to maintain, each near-identical in shape.
  - Cross-domain queries ("show me everything that happened for Smith Toyota in the last week") require UNIONs across N tables — slow and brittle.
  - Adds friction to introducing new event types.

**Option C — paper_trail-style versioning gem.** Install `paper_trail` (or `audited`) — every model change captured automatically as a `versions` row.
- Pros:
  - Zero per-event coding; just `has_paper_trail` on each model.
- Cons:
  - Captures **state** changes only, not **flow events**. "Question email was sent" or "vendor clarification requested" aren't model state changes — they're side-effect events that don't have a natural model row.
  - Generic versioning gems track every column change; high storage growth, low signal.
  - Doesn't compose cleanly with the lineage requirement (every normalized record back-references raw payload + adapter version) — that's an FK relationship, not a versioning concern.
- Evaluation: Reject. Wrong tool for this job.

**Option D — Outbox pattern.** Every domain mutation writes an `event` row in the same DB transaction; downstream readers (dashboard, future analytics, third-party webhooks) consume the outbox.
- Pros:
  - Transactionally consistent — event is committed atomically with the mutation.
  - Decouples writers from readers — same event powers dashboard, analytics, webhooks, replay tooling.
  - Composes naturally with GP3 (raw payload retention) and lineage requirements — events reference both the inbound payload ID and the resulting domain row.
  - The FEAT-002 lead-ingestion lineage requirement (every normalized record links back to the adapter version + raw payload) becomes a special case of "the lead-normalized event references the raw payload event."
- Cons:
  - Requires discipline — every mutation must write the event in the same transaction. Mitigation: a single `Rogue::EventLog.record!` helper called inside transactions; tests that assert event presence after each mutation.
  - Storage growth: every state transition is a row. For onboarding scale (thousands of events per Tenant per year), Postgres handles this trivially.

### Decision
**Chosen: Option D — Outbox pattern, implemented as a single `flow_events` table with structured-jsonb payloads and per-event-type schema validation.**

This is functionally Option A's table with Option D's transactional discipline layered on top. Key choices:

1. **Single table, polymorphic subject + actor**, but with **per-event-type payload schemas** validated in code (a registry of event types declares what keys their payload may contain). Gives the simplicity of A and the type-safety of B without the table sprawl.
2. **Transactionally written with the domain mutation.** Every state-changing operation calls `Rogue::EventLog.record!(event_type:, subject:, actor:, tenant:, payload:)` inside the same transaction; if the transaction rolls back, so does the event.
3. **Composes with FEAT-002 lineage.** The `payload` jsonb on a `lead_normalized` event will carry `raw_payload_id` and `adapter_version_id`; the table is the same; queries are uniform.
4. **Composes with GP3 (raw payload retention).** Inbound events (`gm_reply_received`, `lead_payload_received`) carry an FK to the `ActionMailbox::InboundEmail` row (or, for HTTP, the stored payload row). The retention guarantee is preserved by the inbound row itself; the event is a pointer.

Rejected outright:
- **paper_trail** — wrong abstraction (state versioning, not flow events).
- **Per-domain tables (B)** — accountability dashboard queries fragment; we'd UNION across 8+ tables on the hot path.

The accountability dashboard query — "show me what happened to Smith Toyota's responsibilities in the last 7 days" — becomes `WHERE tenant_id = ? AND created_at > ? ORDER BY created_at DESC`, which is one index away from sub-millisecond.

Trade-offs accepted:
- **Discipline burden.** Every mutation must remember to record the event. Mitigation: enforced by a service-layer helper used universally; a Phase 4 build test that asserts every mutation in onboarding produces exactly the expected event sequence.
- **Storage growth.** ~50-200 events per Tenant per onboarding cycle, plus ~weekly recurring events. At 10,000 tenants this is single-digit GB — Postgres-trivial. We will revisit (e.g., partitioning by month) if/when we cross 100K tenants.
- **Polymorphic subject FK isn't DB-enforced.** Acceptable: the writer helper validates the subject exists; orphan risk exists only if a model is hard-deleted (rare for the models in scope — Tenants and Responsibilities are not hard-deleted, they transition to terminal states).

### Implementation guidance
- **Schema** (`flow_events` table):
  - `id`
  - `tenant_id` (FK, NOT NULL, indexed) — every event is tenant-scoped (GP5).
  - `event_type` (string, NOT NULL — e.g., `tenant.seeded`, `tenant.confirmed`, `question.email_sent`, `gm_reply.received`, `responsibility.created`, `vendor.clarification_requested`, `setup.email_sent`, `digest.email_sent`)
  - `subject_type`, `subject_id` (polymorphic — `Tenant`, `Responsibility`, `TenantQuestion`, `Source`, etc.)
  - `actor_type`, `actor_id` (polymorphic, nullable — `RogueStaff` / `Tenant` / `Contact` / `null` for system events)
  - `payload` (jsonb, NOT NULL default `'{}'`) — structured per `event_type` schema
  - `inbound_email_id` (FK to `ActionMailbox::InboundEmail`, nullable) — set on events triggered by an inbound message; preserves lineage.
  - `outbound_message_id` (string, nullable) — set on `*.email_sent` events; the SMTP `Message-ID` of the dispatched email; enables inbound `In-Reply-To` resolution.
  - `request_ip` (inet, nullable) — set on web-triggered events (confirm click, walkthrough completion).
  - `created_at` (NOT NULL, indexed).
  - Indexes: `(tenant_id, created_at DESC)` (dashboard hot path); `(subject_type, subject_id)`; `(event_type, created_at)` (analytics); `(inbound_email_id)`; `(outbound_message_id)`.
- **Writer helper** (`app/services/rogue/event_log.rb`):
  ```ruby
  module Rogue::EventLog
    def self.record!(event_type:, subject:, tenant: Current.tenant, actor: nil, payload: {}, inbound_email: nil, outbound_message_id: nil, request_ip: nil)
      validate!(event_type, payload) # registry-driven payload schema check
      FlowEvent.create!(
        tenant: tenant, event_type: event_type, subject: subject, actor: actor,
        payload: payload, inbound_email: inbound_email,
        outbound_message_id: outbound_message_id, request_ip: request_ip
      )
    end
  end
  ```
  Always called inside the transaction performing the mutation. Validation registry lives at `config/initializers/event_log_schemas.rb`.
- **Event-type registry**: a hash literal in the initializer mapping `event_type => required_payload_keys`. Validated at `record!` time so a typo raises during development; in production raises and rolls back the transaction (consistent with the principle that an unrecorded event is worse than a failed mutation, since the dashboard would silently lie).
- **Event consumers**:
  - The accountability dashboard (FEAT-003) reads from `flow_events` directly.
  - The weekly digest job reads `flow_events WHERE tenant_id = ? AND created_at >= last_digest` to summarize.
  - Future webhook delivery / analytics export would tail this table.
- **Lineage composition**:
  - For onboarding: `gm_reply.received` event has `inbound_email_id` set; `responsibility.created` event has `actor` = the `Contact` named, `payload.cited_event_id` pointing back to the `gm_reply.received` event ID.
  - For FEAT-002: `lead_payload.received` event has `inbound_email_id`; `lead_normalized.created` event has `payload.raw_event_id` + `payload.adapter_version_id` — same pattern, different event types. **One audit substrate, two surfaces.**
- **Test seam**: `assert_event_recorded(event_type, subject:, **payload_keys)` Minitest helper; matching RSpec matcher if RSpec is selected in Phase 1. Used universally across mailer / mailbox / controller tests.

---

## Cross-cutting decisions

**1. Tokens and addresses share a common shape.** A1's `tenants.onboarding_token` and FEAT-002's `sources.lead_token` use the same generation routine (`SecureRandom.base58(16)`), the same column type (`string, null: false`, unique index), and the same lookup pattern (regex-routed to a Mailbox class which loads the subject by token). Implementing both at once in Phase 1 (token columns on `tenants` and a `lead_token` placeholder on `sources` even though `sources` doesn't fully land until FEAT-002) avoids a follow-up migration.

**2. Catalog versioning (A2) and lineage (A4) are the same idea applied twice.** A pinned catalog version on a Tenant is to onboarding what an `adapter_version_id` is to lead normalization — both anchor "this artifact was produced under that frozen specification." The `flow_events.payload` for catalog-related events should carry `catalog_version` so audit queries can trace which version of the marketing catalog produced any given Tenant's responsibility set.

**3. The vendor roster (A3) is exempt from tenant scoping but participates in the audit trail (A4).** Per GP5, every domain model has `tenant_id` *except* `Vendor`, `Question`, and `Domain` (which are platform-wide). However, when a runtime clarification creates a `Vendor` row, that creation **is** tenant-scoped and emits `vendor.clarification_promoted` event with `tenant_id` set — preserving the audit thread for "where did this vendor come from."

**4. `Current.tenant` carries through the entire stack** (per `systemPatterns.md` Tenant Scoping). The `Rogue::EventLog.record!` helper defaults `tenant:` to `Current.tenant` so callers don't have to thread it manually; only mailbox `process` methods (where the tenant is freshly resolved from the routing token) and rake tasks need to set it explicitly.

**5. One MX, one provider, one operational burden.** Choosing plus-addressing (A1) means we have one inbound provider integration to do later (operational cutover); choosing the outbox pattern (A4) means we have one event-stream to operationalize. Together these collapse what could have been 4-6 distinct operational decisions into 2.

---

## Open questions deferred

These are explicitly **not** settled by this document — they belong to other phases or operational cutover:

- **Production inbound email provider** (Postmark / Mailgun / SendGrid / dedicated MX). Plus-addressing (A1) was selected specifically to keep this open. Resolution: operational cutover, tracked in `Live-Dogfood-Pending Tracker`.
- **Production outbound email provider.** Same as above.
- **S3-class object storage class + retention policy** for Active Storage backing of `ActionMailbox::InboundEmail`. Active Storage local disk in dev meets the schema seam; production class is operational.
- **Reply parser algorithm** (signature stripping, `skip` detection guards, multi-client header normalization). Owned by the Algorithm Design creative phase running in parallel.
- **Question pacing scheduler** (fixed 24h vs. adaptive). Owned by the User Journey Design creative phase running in parallel.
- **First-question delivery delay after confirm** (0min / ~1h / business-hour-aware). Owned by User Journey Design.
- **Tenant seed surface UX** (the controller default in TASK-001 is fine; the User Journey phase validates with actual ops users).
- **In-thread ack subject conventions and threading discipline.** Owned by Algorithm Design.
- **Catalog delta rollout job** (the Phase 1 mechanism is established; the *first run* with a real `marketing.v2` is a follow-up task once Rogue maintains a multi-version history).
- **Vendor admin UI for promoting `pending_review` rows.** A rake task suffices at MVP; full UI deferred.
- **Event-stream consumers** beyond the accountability dashboard (webhooks, analytics export, OpenTelemetry bridge) — the substrate is in place, the consumers are deferred.
- **Encryption** of `flow_events.payload` for events that carry PII. Out of scope at MVP per productBrief (only customer email/phone on leads are encrypted); revisit if onboarding events ever carry customer data.

---

## Validation Checklist

- [x] Each decision references a Guiding Principle it respects (or explicitly justifies a deviation — none required here).
- [x] Each decision specifies concrete file paths, table names, and column names so Phase 1 of the Implementation Roadmap is directly executable.
- [x] Trade-offs are explicit, not glossed.
- [x] Cross-cutting consequences are surfaced.
- [x] Production-cutover items are explicitly deferred, not silently assumed.
- [x] Composes with FEAT-002 (lead ingestion) — addressing scheme, lineage shape, and token shape are reused, not re-decided.
