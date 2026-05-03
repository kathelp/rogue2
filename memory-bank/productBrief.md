# Product Brief: Rogue

> Foundational project context (overview, goals, repository, git config) lives in `projectbrief.md`. This document is the canonical product specification: domain model, onboarding, submission flow, MVP scope, adapter accountability, consumption, access model, and security/data handling.

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

Rogue sends the GM a confirmation email with a single click to confirm. This is the only manual step on Rogue's side, and the only click required of the GM in the entire onboarding.

### GM Self-Onboarding via Email

GM onboarding is **email-only**. After the welcome confirmation, the GM never has to visit a web page to complete onboarding or run their rooftop. The platform's bet: GMs are saturated with apps but fluent in email, and the highest-leverage move is to meet them where they already work.

After confirmation, Rogue sends a paced sequence of question emails — one responsibility at a time, spaced over days rather than dumped in a wall. Each email asks one question in business vocabulary:

- "Who controls your marketing strategy?"
- "Who is responsible for paying invoices related to marketing?"
- "Who manages your dealer website?"

The GM responds by **replying and CC'ing the responsible party**, with three explicit conventions stated in every question email:

- **The first person you CC is the primary accountable party.** Anyone CC'd after is a fallback. Order matters; the email tells the GM this directly.
- **If this is you, reply with no CC.** No-CC replies map the GM as the accountable party for that responsibility.
- **If you don't have anyone for this yet, reply with "skip".** Skipped responsibilities are tracked and the platform can circle back later.

When the GM replies, Rogue parses the recipients, performs vendor inference (see below), creates the relevant Source and Request records, and sends a follow-up message in the same thread thanking the GM and welcoming the named CC'd parties — giving them context for the separate setup email they'll receive shortly. The thread carries full provenance of who was named, by whom, and when.

### What Each Reply Produces

For each parsed reply, Rogue:

1. **Resolves whether each named contact is internal or a vendor.** The system infers from email domain against the canonical Vendor record set, which is **pre-seeded with a substantial roster of common automotive vendors before launch** so inference works well from day one. The GM is prompted explicitly (in the same thread) only when the domain isn't recognized. New vendors detected this way create canonical Vendor records.
2. **Creates or links a Source** for the relevant (Tenant, Domain, Vendor?) tuple covering that responsibility's data points.
3. **Creates Requests** for the metrics that responsibility covers, using platform-default cadences per metric. The GM can override defaults by replying with a preferred cadence; invitees cannot.
4. **Sends a setup email** to each identified contact, introducing them to their assignment with a magic link to the (web-based) submitter walkthrough.

If the same email is named for multiple responsibilities, it's deduplicated to a single contact carrying multiple assignments.

### Invitee Walkthrough

The invitee experience is hybrid: introduced over email (in the thread the GM started), but actual data setup happens on the web because configuration benefits from richer UI. After clicking the magic link in the setup email, the invitee:

1. Sees what data they've been asked to provide and on what cadence.
2. Chooses a submission method: form, CSV upload, or API POST.
3. For non-form submissions, uploads a sample payload, which feeds the AI-Assisted Adapter Creation flow. They review and approve the proposed mapping, which establishes them as the accountable approver for that adapter version.
4. Confirms the configuration, and the platform begins sending recurring magic-link prompts on cadence (or, for push-based data like leads, provides the unique inbound email or endpoint).

### GM Accountability — Delivered to Inbox

Consistent with the email-first ethos, the GM's accountability surface is primarily **email-delivered**:

- A periodic digest (weekly by default) summarizing all configured responsibilities, their status, recent submissions, and anything that's lapsed.
- Real-time emails on consequential events — escalations, persistent failures, missed first submissions — naming specific people so the GM doesn't have to look anything up.

A magic link in any of these emails opens a richer web view of the accountability dashboard for GMs who want to drill in. GMs who prefer it can opt into password + 2FA for persistent web access — but no GM is ever required to log in to perform their role.

### Rolling Onboarding

Onboarding is not single-pass. The platform initiates new question emails when a new domain (sales, service) launches and applies to the rooftop, or when the Rogue-maintained question catalog adds questions to a domain the dealer has already covered. The GM can also revisit a skipped or assigned responsibility at any time by replying to the original thread or emailing a tenant-specific dedicated address.

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
- **Email replies** are a first-class interaction channel for GMs. A GM can complete onboarding, manage responsibilities, and receive accountability information entirely through email without ever logging in. Web access is available via magic link or 2FA but never required.
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