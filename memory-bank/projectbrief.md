# Project Brief: Rogue

## Project Overview

Rogue is a multi-tenant data collection and standardization platform for automotive dealerships. It solves a structural problem in the industry: dealers need to track business metrics across marketing, sales, and service, but the underlying data lives with dozens of internal staff and external vendors who each report it differently — when they report it at all.

Rogue's wedge is frictionless delegation. A dealer defines what data they need, from whom, on what cadence; Rogue handles the rest. Recipients receive magic-link or SMS prompts that route them to a no-login submission page where they can fill in a form, upload a CSV, or POST to an API — whichever is easiest. Every submission path lands at the same API endpoint, where a tenant- and source-specific adapter normalizes the payload into a canonical, domain-level schema shared by every tenant on the platform.

Schema standardization pays off twice: once when adapters can target a single contract, and again when consumption — both dashboards and natural-language reporting — can be built once across all tenants.

The MVP focuses on the marketing domain, with lead ingestion (ADF-XML email + raw HTTP POST) as the first end-to-end flow.

## Goals

1. **Eliminate friction in data collection.** People providing data should never need to create an account, learn a new tool, or change their workflow.
2. **Standardize disparate inputs.** Every domain has one canonical schema so analytics, dashboards, and chat-based reporting can be built once and applied universally.
3. **Make onboarding cheap.** Adapters are AI-generated from sample payloads, so a new tenant/source pairing goes live in minutes rather than weeks of integration work.
4. **Treat vendors as first-class, canonical entities.** A vendor serving 40 rooftops has one identity across the platform.
5. **Establish marketing as the wedge domain** before expanding to sales and service.

## Core Domain Model

- **Tenant** — A single dealer rooftop. Access control, data partitioning, and metric configuration are scoped to the rooftop.
- **Dealer Group** — A grouping of rooftops for aggregated reporting. Many-to-many with Tenant. Groups are typed (e.g., `retail_group`, `oem_region`, `oem_national`) so a single rooftop can simultaneously belong to its retail parent, its OEM region, and its OEM national rollup. Group-level access is granted via Group Memberships (see Access Model). Groups are created and assigned by Rogue staff at MVP.
- **Vendor** — A canonical record representing a third-party service provider (marketing agency, lead provider, software vendor). Vendors exist platform-wide and can be associated with many tenants. A vendor user logging in sees only the rooftops they serve.
- **Domain** — A business area with its own standardized schema. MVP launches with `marketing`; `sales` and `service` follow.
- **Standardized Schema** — The canonical data shape for a domain. Identical across all tenants. Owned by Rogue, never modifiable by tenants or vendors. **Versioned from day one** — every adapter targets a specific schema version. Schema lifecycle rules: (a) **migration is opt-in per adapter** with manual validation, and (b) **no schema version is retired while any active adapter still targets it**. Indefinite raw payload retention (see Security & Data Handling) makes migrations to newer versions replayable against historical data.
- **Source** — A specific origin of data for a (tenant, domain) pair. Optionally associated with a vendor. Multiple sources can feed the same domain for the same tenant. Vendors may create their own sources for tenants they serve.
- **Adapter** — A transformation that maps a source's native payload into the standardized schema for its domain. Adapters are scoped to a (tenant, source) pair and pinned to a schema version. Generated with AI assistance from sample payloads. Vendors may create, approve, and maintain their own adapters; **vendor approval alone is sufficient** to put a vendor-authored adapter into production. Vendors cannot alter the schemas their adapters target.

## Tenant Onboarding

Tenant onboarding is the platform's most operationally important flow. The design goal is to take a new dealership from "we just signed a contract" to "data is flowing on a cadence" with as little Rogue-staff involvement and GM time as possible.

### Seeding

Rogue staff create a tenant record with three pieces of information:

- Dealership name
- General Manager (GM) name
- GM email

Rogue sends the GM a magic link. This is the only manual step on Rogue's side.

### GM Self-Onboarding Wizard

When the GM follows the magic link, they enter a guided wizard structured as a series of **per-domain interviews**. The marketing domain ships first; sales and service follow. Each interview asks questions phrased in the GM's own business vocabulary — not Rogue's data vocabulary — so the GM never has to translate between "what we need" and "what they call it." Examples:

- "Who controls your marketing strategy?"
- "Who is responsible for paying invoices related to marketing?"
- "Who manages your dealer website?"
- "Who handles your paid search and social campaigns?"

Each question accepts one or more email addresses. The GM can enter staff emails, vendor contact emails, or themselves. **The first email in the list is the primary accountable party; any additional emails are fallbacks.** The GM can reorder or edit the list at any time to change who is primary. Single accountability is a deliberate principle: every responsibility has exactly one person on the hook, with named backups.

### What Each Answer Produces

Each answer maps a *business role* identified by the GM to one or more *data responsibilities* the platform needs to fulfill the underlying domain schema. For each answer, Rogue:

1. **Resolves whether each named contact is internal or a vendor.** The system infers from email domain against the canonical Vendor record set, which is **pre-seeded with a substantial roster of common automotive vendors before launch** so inference works well from day one. The GM is prompted explicitly only when the domain isn't recognized. New vendors detected this way create canonical Vendor records.
2. **Creates or links a Source** for the relevant (Tenant, Domain, Vendor?) tuple covering that responsibility's data points.
3. **Creates Requests** for the metrics that responsibility covers, using platform-default cadences per metric. The GM can override defaults during onboarding; invitees cannot.
4. **Queues a magic-link invitation** to each identified email.

If the same email is named for multiple responsibilities, it's deduplicated to a single contact carrying multiple assignments.

### Invitee Walkthrough

When an invited contact accepts their magic link, they enter their own walkthrough:

1. They see what data they've been asked to provide and on what cadence.
2. They choose a submission method: form, CSV upload, or API POST.
3. For non-form submissions, they upload a sample payload, which feeds the AI-Assisted Adapter Creation flow. They review and approve the proposed mapping, which establishes them as the accountable approver for that adapter version.
4. They confirm the configuration, and the platform begins sending recurring magic-link prompts on cadence (or, for push-based data like leads, provides the unique inbound email or endpoint).

### GM Accountability Dashboard

Once invitations are out, the GM has a live operational view of every responsibility configured for the rooftop:

- Status per responsibility — invitation sent / first submission pending / on-time / late / overdue
- The primary accountable contact (with fallbacks visible on drill-down) and their organization (internal staff vs. vendor)
- Submission history and timeliness trends
- Notifications when a responsibility goes overdue, when an invitation is unclaimed past a threshold, or when an adapter starts failing

The GM can re-assign responsibilities, deactivate them, add new ones, and promote other tenant users to admin.

### Rolling Onboarding

Onboarding is not single-pass. The GM can return to the wizard to extend coverage to new domains as those domains launch on the platform, fill in responsibilities they skipped initially, or restructure as the business changes. New domains and new question-catalog entries appear automatically when the platform releases them.

## Delegation & Submission Flow

Once data requests are configured (see Tenant Onboarding), each request fires on its cadence as follows:

1. Rogue sends a magic link via email and/or SMS to the assigned recipient.
2. The recipient lands on a single-purpose, no-login page tailored to that request.
3. The recipient submits via whichever path was configured during their walkthrough:
   - **Form** — fill in fields directly in the browser
   - **CSV upload** — drop a file
   - **API POST** — push programmatically (the link can return an endpoint + token for vendors who want to automate)
4. All three paths converge on a single ingest API behind the adapter.
5. The adapter normalizes the payload to the domain's canonical schema.
6. Normalized data lands in storage, ready for consumption.

### Due Dates & Escalation

Every recurring request has a due date computed from its cadence: a grace period equal to **roughly one-quarter of the reporting interval, capped at two weeks**. In practice:

- Weekly reports — due within ~3 days of period end
- Monthly reports — due within ~1 week of period end
- Quarterly reports — due within 2 weeks of period end (the cap)
- Any longer cadence — due within 2 weeks (cap)

The magic-link prompt to the primary accountable contact fires at the start of the grace period (i.e., when the reporting period ends). The primary then receives a graduated sequence of reminders:

1. **"Your report is due soon"** — sent partway through the grace window.
2. **"Your report is due today"** — sent on the due date itself.
3. **"Your report is overdue and will be escalated tomorrow"** — sent the day after the due date if still unsubmitted, naming the specific fallbacks and the GM who will be looped in. The named-callout is deliberate; it surfaces social pressure without preaching.

If the primary still has not submitted 24 hours after the final warning:

- **All fallbacks are prompted simultaneously** via magic link and may submit on the primary's behalf.
- **The GM is cc'd** on the escalation email so accountability stays visible without requiring GM action.
- The accountability dashboard flags the responsibility as overdue and records who ultimately submitted.

The primary remains the named owner of the responsibility regardless of who actually submits — single accountability is preserved even when the safety net catches a missed report.

**No-fallback case.** When a responsibility has no fallbacks named and the primary lapses, there is no one to escalate to automatically. Instead, the GM is notified at the escalation point and prompted to add a fallback (or reassign the primary) on the spot. The responsibility remains flagged as overdue on the dashboard until either the primary submits, a newly-added fallback submits, or the GM resolves it.

## Marketing MVP — Lead Ingestion

The marketing domain ships with first-class lead ingestion:

- Every (tenant, vendor source) pair receives a **unique inbound email address**. Vendors and lead aggregators send leads to that address — no integration negotiation required.
- Leads are accepted as **ADF-XML** (the de facto industry standard, attached or inline) or via **raw HTTP POST** to the same source.
- Both paths flow through the source's adapter into the canonical lead schema.
- This deliberately replaces what would otherwise be a long tail of CRM integrations (VinSolutions, DealerSocket, Elead, etc.). Rogue is the lead destination, not a sync layer.
- **Duplicate leads are accepted as-is.** When the same lead surfaces through multiple sources, all instances are retained — duplicates carry attribution signal and should not be collapsed at ingest.

## AI-Assisted Adapter Creation

- During source onboarding, the user submits one or more sample payloads (CSV headers + a row, ADF-XML sample, JSON example).
- An AI generation step proposes a field-by-field mapping to the target schema version, including type coercion, derived fields, and transformations.
- A human reviews and approves the mapping before it goes live. **The reviewing human is recorded as accountable for the data the adapter produces** — accountability sits with the approver, not the AI. For tenant-authored adapters this is a tenant user; for vendor-authored adapters this is a vendor user (no dealer co-approval required).
- Adapters are versioned and pinned to a schema version. When the canonical schema introduces a new version, existing adapters continue to target the version they were built against until explicitly migrated.
- Failed payloads (don't parse against the active adapter) are flagged for review and re-generation. Because raw payloads are retained indefinitely, re-runs are always possible.

### Trust & Transparency

- **Dealers have full visibility** into every adapter operating against their data — mappings, version history, and the approving user are visible to dealer users — but dealers are not required to verify or pre-approve vendor-authored mappings.
- **Errors are correctable after the fact** by re-running a corrected adapter against retained raw payloads. The cost of an adapter mistake is replay time, not data loss.
- The trust model leans on dealer visibility, replay-based correction, and vendor commercial incentive (vendors who produce bad numbers lose dealers) — not on dealer gate-keeping.

## Consumption Layer

Two surfaces, both built directly on the standardized domain schemas:

- **Dashboards** — pre-built per domain, identical for every tenant since the underlying schema is identical. Group-level access aggregates across member rooftops.
- **Ad-hoc chat reporting** — a natural-language interface that translates questions into queries against the canonical schemas. Feasible because the schemas are fixed and platform-wide. Current direction: constrain the chat layer to a set of deterministically authored SQL views with row-level security baked in, rather than letting the model author free-form queries. Metric catalog, query patterns, and security boundaries are deferred to a follow-up brief.

## Access Model

- **Magic links** are always available for any user. They are the universal floor — required for one-off submitters and supported for everyone else.
- **Password + 2FA** is an opt-in upgrade path for persistent sessions. Supported 2FA methods at MVP: **SMS and TOTP**.
- **Tenant users** are scoped to a single rooftop, with two roles:
  - **Tenant Admin** (GM by default) — sees the full rooftop including the accountability dashboard, all submissions, and configuration. Can promote other tenant users to admin.
  - **Tenant Submitter** — sees only their own assignments and submission history.
- **Vendor users** are scoped to the rooftops their vendor serves, with a parallel split:
  - **Vendor Admin** — sees all rooftops the vendor serves.
  - **Vendor Submitter** — sees only their own assignments.
- **Group Memberships** grant users access to one or more Dealer Groups with associated permissions. A user can hold memberships in multiple groups (e.g., a regional manager covering both an OEM region and a retail sub-group). The specific permission catalog is a follow-up decision; the data access layer is built with permission checks as a hook so the catalog can be expanded without rework.

## Security & Data Handling

- **PII encryption at rest.** Customer email addresses and phone numbers on inbound leads are encrypted at rest using a **platform-wide encryption key**. Other PII (names, addresses, VINs, free-text notes) is *not* encrypted at MVP — this can be revisited as the data footprint grows.
- **Indefinite raw payload retention.** Every inbound payload — ADF-XML, CSV, API POST body, form submission — is stored verbatim in S3-class object storage with no expiration. This enables (a) re-running adapters when bugs are found, (b) replaying ingest against new schema versions during future migrations, and (c) audit and forensics. The normalized data in the canonical schema is the working dataset; the raw archive is the source of truth.
- **Adapter accountability and lineage.** Each adapter version records the human approver, their organization (tenant or vendor), and timestamp. Every normalized record links back to the adapter version that produced it and the raw payload it came from.

## Out of Scope (MVP)

- Sales and service domains.
- Direct DMS or CRM integrations.
- Cross-dealer benchmarking products.
- Detailed dashboard and chat-reporting specs — concept and direction defined; metric catalog and query guardrails follow.
- Self-serve Dealer Group creation (Rogue staff-managed at MVP).
- BYOK or per-tenant encryption keys (single platform-wide key at MVP).
- Encryption beyond customer email and phone fields.
- Group Membership permission catalog (architectural seam exists; specific permissions defined later).
- Tenant co-approval for vendor-authored adapters.

## Open Questions

1. **Question catalog versioning.** The per-domain interview catalog is a Rogue deliverable, owned and maintained by the platform team. When new questions are added to an existing domain — to expand coverage or in response to dealer feedback — already-onboarded GMs need to be notified and walked through the additions. The mechanic for surfacing catalog deltas to existing tenants needs definition.
2. **Chat-reporting security model.** Vendor and group users have access spanning multiple tenants, and an ad-hoc query layer needs hard guarantees that one user can't craft a question that pulls another tenant's data. Current direction is a fixed catalog of deterministically authored SQL views with row-level security — but the view catalog, the prompting and grounding strategy, and the failure mode (refuse vs. fall back to dashboard) all need definition before this surface is built.

## Repository Structure
- **Type**: Poly-repo
- **Workspace Tool**: None
- **Workspace Root**: N/A

## Git Configuration
- **Repository**: No
- **Provider**: None
- **CLI Available**: none
- **Remote URL**: none
- **Default Branch**: N/A
- **Archive Strategy**: local-merge
