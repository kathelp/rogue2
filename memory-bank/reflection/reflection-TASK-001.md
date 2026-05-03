# Reflection: TASK-001 — Tenant + GM Email-First Onboarding

## Metadata
- **Task ID**: TASK-001
- **Roadmap Link**: FEAT-001
- **Complexity**: Level 4 (enterprise / architectural)
- **Branch**: `feature/FEAT-001-tenant-gm-email-onboarding`
- **Duration**: 2026-05-03 (compressed multi-phase build session)
- **Final Build State**: 307 RSpec examples, 0 failures, 0 RuboCop offenses
- **Closed ACs**: AC-ENTRY-1..4, AC-HAPPY-1..8, AC-ERROR-1..5, AC-ASYNC-1..3, AC-NAV-1..2 (20 of 20 specified)

## Executive Summary

TASK-001 delivered the foundational email-first onboarding loop for a new dealer rooftop: Rogue staff seed a Tenant via an admin form, the GM single-clicks a magic-link to confirm, and the system then drives a paced sequence of one-question-at-a-time emails through Action Mailbox / parser / vendor-inference / setup-walkthrough / weekly-digest. Six phases shipped over a single build session, each ending at a green test boundary, with a compounding spec count (89 → 147 → 185 → 242 → 279 → 307). The architecture follows the productBrief's "email is the entire UI" thesis and lays the data substrate (Tenant / Vendor / Contact / TenantQuestion / Responsibility / Source / Request / SubmissionPrompt / SkippedQuestion / FlowEvent / WeeklyDigestDelivery) that every subsequent feature will build on.

The task was executed under an unusual recovery condition: Phase 4's build crashed mid-orchestration with all source files written but uncommitted and the orchestrator's Execution State stale. The first thing the resumed session had to do was reconstruct what had been done by reading working-tree files, run the suite to confirm correctness, lint, and only then close the phase with a commit. The fact that the resume produced a clean Phase 4 commit (no rework) is the best signal that the working pattern — file-first, commit-last, idempotent service classes — survived a hard interruption gracefully.

## Goals vs Outcomes

| Goal | Target | Actual | Status |
|------|--------|--------|--------|
| Foundational data model spans every concept the productBrief named | 11 models / migrations | 12 models / 11 migrations + Action Mailbox parser-fields extension | ✅ |
| Tenant seed → GM confirm → first question loop | One end-to-end traversal in tests | Closed via AC-HAPPY-1 + AC-HAPPY-2 + AC-ENTRY-3 system specs | ✅ |
| Inbound reply parser handles 4 intents reliably | assign / self_assign / skip / unparseable + 1 clarification_response | All 5 implemented; 28 parser-spec branches covering CC ordering, signature/quote stripping, attachment metadata, raw_excerpt cap | ✅ |
| Vendor inference resolves internal vs vendor vs unknown | 3 branches | All 3 + clarification round-trip (`internal` / `vendor: <Name>`) | ✅ |
| Adaptive question pacing (J3) | 12h / 24h / 48h / silence ladder | Implemented with clock-skew clamp + business-hours envelope | ✅ |
| Invitee setup walkthrough (3 steps) | summary → method → done, resumable | Single-controller `?step=` design with Source-state short-circuit | ✅ |
| Weekly digest with idempotency on `(tenant, week_starting)` | Hard constraint, not advisory | Unique index on `weekly_digest_deliveries`; `RecordNotUnique` is the no-op signal | ✅ |
| Magic-link tokens scoped per-purpose with appropriate expiry | `:gm_confirm` (72h) / `:invitee_setup` (7d) / `:dashboard_drilldown` (8d) | All three implemented + finder helpers + expired views | ✅ |
| Test count target ~90-120 | 90-120 | 307 (218 over the upper bound) | ✅ (over-delivered) |
| Outbound mailers have html + text alternatives | All transactional mail | All 6 mailer actions have both | ✅ |

## Phase Analysis

### Phase 1 — Foundation (committed before this session)
- **Output**: 11 migrations, 11 ActiveRecord models + `Current`, `Rogue::QuestionCatalog::Marketing::V1`, vendor seed CSV + loader, 9 factories, 7 spec files, 89 examples green, 0 RuboCop offenses.
- **Notes**: Established the load-bearing `find_or_create_by!` + idempotent service-class pattern that every later phase relies on. Encryption (`encrypts :gm_email, deterministic: true`) on the Tenant is also locked in at this layer.

### Phase 2 — Tenant seed + GM confirm (committed before this session)
- **Output**: `Admin::BaseController` (HTTP basic auth), `Admin::TenantsController`, `Onboarding::ConfirmationsController` (with resend + anti-enumeration + rate limit), `OnboardingMailer#confirmation_email`, all views, rake task, 5 spec files (58 new examples). Total 147.
- **Notes**: First end-user-facing surface; sets the bar for the magic-link UX (single CTA, plain-text alt, expired-view copy).

### Phase 3 — First question email (committed before this session)
- **Output**: `Threadable` mailer concern, `OnboardingMailer#question_email` with explicit Message-ID injection, `OnboardingFlow::Scheduling` business-hours envelope service, `EnqueueFirstQuestionJob` / `EnqueueNextQuestionJob`. Total 185.
- **Notes**: Pre-generated Message-IDs so the inbound path can resolve `In-Reply-To` against `tenant_questions.outbound_message_id` before delivery has even completed. This decoupling is what makes Phase 4's parser deterministic.

### Phase 4 — Inbound reply pipeline (resumed after crash)
- **Output**: `OnboardingMailbox` dispatcher, `OnboardingReplyParser` with four submodules (`CcOrdering`, `BodyExtractor`, `SkipDetector`, `ThreadResolver`), `VendorInferenceService`, `OnboardingFlow::AdaptivePacing`, three new mailer actions (`in_thread_ack`, `gm_only_thread_notice`, `vendor_clarification`), `OnboardingMailerHelper#humanize_next_question_at`. 57 new examples → 242 total.
- **Crash recovery**: All source files were on disk but uncommitted; `Build Status: PHASE_3_COMPLETE` was stale. The recovery workflow was: (1) read every working-tree file to reconstruct intent, (2) `bundle exec rspec` → 242 green confirmed correctness, (3) RuboCop touched up 2 pre-existing offenses in `config/routes.rb` from Phase 2, (4) update task file + progress.md, (5) commit. Total recovery time was minimal because the code was already well-structured and the parser is purely functional.
- **Notes**: This is the single most complex phase in the task — 57 specs, 4 parser submodules, mail-client variation, signature/quote stripping, threading discipline. The split into a thin Mailbox dispatcher and a pure `OnboardingReplyParser` value-object service paid off: every parsing edge case is testable without instantiating a Mail::Message inside the mailbox.

### Phase 5 — Invitee setup walkthrough
- **Output**: `OnboardingMailer#invitee_setup_email`, `Setup::WalkthroughsController` (single controller, three "steps" via `?step=` query + Source-state short-circuit), `Setup::Completion` service (transactional Source update + Request provisioning + SubmissionPrompt scheduling + FlowEvent), `OnboardingFlow::RequestProvisioning`, `OnboardingFlow::SubmissionPromptScheduler` (next-period-start in tenant TZ), `Contact#invitee_setup_signed_id`, `Rogue::QuestionCatalog::Marketing::V1.metrics_for`. 37 new examples → 279 total.
- **Notes**: Phase 5 also retroactively closed the Phase-4 Request-creation gap: `OnboardingMailbox#handle_assignment` now calls `RequestProvisioning.call` so the AC-HAPPY-3 spec language ("One Request row per metric the responsibility covers") is actually satisfied. The Phase 4 spec didn't enforce this — caught only because Phase 5 needed Requests to exist to schedule SubmissionPrompts. **This is a representative example of how the cascade of dependencies in a Level 4 task surfaces gaps that single-AC reading misses.**

### Phase 6 — Weekly digest + dashboard placeholder
- **Output**: `AccountabilityMailer#weekly_digest`, `Accountability::DigestAssembler` (Row + Digest value objects), `WeeklyDigestJob` (recurring), `WeeklyDigestDelivery` model + migration, `Tenant#dashboard_signed_id`, `DashboardsController#show`, `config/recurring.yml` schedule. 28 new examples → 307 total.
- **Notes**: The `WeeklyDigestDelivery.create!` first / mailer second pattern is the right idempotency primitive. `RecordNotUnique` is the synchronisation point — concurrent workers and accidental re-runs both no-op cleanly without needing a distributed lock.

## Architecture Assessment

### What Worked

- **`find_or_create_by!` everywhere domain mutations meet inbound traffic.** Every entry point that processes inbound email or external triggers (mailbox handlers, scheduled jobs, walkthrough completion) is idempotent on its natural key. `Tenant#confirm!` is a no-op on second click; `Vendor.bootstrap!` reuses the existing row by name; `RequestProvisioning` reuses by `(source, metric_key)`; `WeeklyDigestDelivery` is unique on `(tenant_id, week_starting)`. Combined with Action Mailbox's native `Message-ID` dedup, the system is naturally retry-safe end to end.

- **Pure service classes returning value objects.** `OnboardingReplyParser` returns a `ParsedReply` Struct, `Accountability::DigestAssembler` returns a `Digest` with `Row` Structs, `Setup::Completion` returns a `Result` with `success?`. The Mailbox / Job / Controller layers stay thin and dispatch on those values. This made every parser branch / digest row / completion path testable in isolation without touching the database or `Mail` machinery.

- **Magic-link tokens scoped per purpose.** Three distinct purposes (`:gm_confirm` / `:invitee_setup` / `:dashboard_drilldown`) with three different expiries (72h / 7d / 8d) and three controller-specific finders. Token verification failures return `nil` rather than leaking existence — the expired view doubles as anti-enumeration. Rails' built-in `signed_id` machinery handled this without any custom crypto.

- **Per-purpose FlowEvent stream as the audit trail.** `flow_events` is the single append-only log that every domain mutation writes through. Searches like "what happened on this thread" are one query (`tenant_id` + `event_type` filter). The `vendor.clarification_requested` payload carries the ambiguous email back to the clarification handler, avoiding a separate "pending clarifications" table. This is essentially the outbox pattern repurposed as a domain event log.

- **The `?step=` query parameter for the setup walkthrough.** A 3-step walkthrough as a single controller with one show + one update action turned out simpler than nested resources or per-step routes. Source state is the source of truth for which step to render; the query param is just a hint.

- **Spec-first, lint-last, commit-last cadence.** The TDD RED → GREEN → lint → memory-bank → commit ordering kept every phase's commit a clean snapshot. When Phase 4 crashed, the resumption picked up exactly because the on-disk state was the only ground truth — there was no half-commit to reconcile.

### What Could Improve

- **`Source has_many :responsibilities` is a phantom association.** The schema has no `source_id` on `responsibilities`. The association was declared in Phase 1 (`dependent: :nullify`), and it didn't fire until Phase 5 needed to look up "the responsibility that owns this source". The fix was a `(tenant, responsibility_key) ↔ (tenant, tenant_question.key)` lookup in `Setup::Completion`. **Recommendation**: in a Phase-7-or-later cleanup, either add an actual `source_id` column to `responsibilities` (preferred — it's the natural domain shape) or remove the `has_many :responsibilities` from `Source`. As written, the association is misleading.

- **Phase 4 system test for AC-HAPPY-3 didn't assert Request count.** The Phase 4 spec verified `Source` and `Responsibility` creation but not Request rows; Phase 5 surfaced the gap. **Lesson**: system tests for inbound-driven flows should assert _every_ downstream artifact named in the AC, not just the headline ones. Easy to miss without a "full check" mental discipline.

- **Multi-responsibility setup walkthrough is ambiguous at MVP.** `Contact#invitee_setup_signed_id` binds to a Contact, not a (Contact, Responsibility) tuple. If the GM CCs the same person on multiple questions, all setup emails for that contact link to the same `/setup/<signed_id>` URL, and the walkthrough renders only the most recent active responsibility. **Recommendation**: introduce a per-(Contact, Responsibility) signed payload in a follow-up — `Responsibility#invitee_setup_signed_id(contact:)` — so each setup email targets the specific assignment.

- **`config/recurring.yml` only declares the digest job in `production`.** Test/dev environments don't have it scheduled (which is fine for tests because they invoke the job directly). But local developers exercising the digest will need to enqueue manually. Document this in `techContext.md` if/when it bites.

- **No system spec covers the full skip→revisit→answer arc end-to-end.** AC-NAV-1 is covered at the mailbox-spec level (`describe "skip then revisit"`), but a higher-fidelity system spec walking from Phase-2 confirm through skip, then through revisit-with-CC, would be stronger. Plan named `spec/system/gm_skip_then_revisit_spec.rb` but it didn't ship — covered at the mailbox layer instead.

- **The `OnboardingFlow::AdaptivePacing.next_wait_hours` / `Tenant#next_question_cadence_gap` duplication.** Two implementations of the same J3 ladder live in the codebase: `AdaptivePacing` keys off `(question_sent_at, reply_received_at)`, while `Tenant#next_question_cadence_gap` keys off `last_gm_reply_at`. The Tenant method is unused in the live flow but visible. **Recommendation**: delete `Tenant#next_question_cadence_gap` and route everything through `AdaptivePacing`.

## Technical Successes

### 1. Recoverable build pattern
- **Evidence**: Phase 4 crashed mid-orchestration with all source on disk and an outdated Execution State. The resumption produced a clean commit with zero rework. RSpec confirmed the on-disk code was correct; RuboCop touched up only 2 unrelated pre-existing offenses.
- **Impact**: This validates "file-first, commit-last" as the right cadence under interruption. Memory-bank `Execution State` is supplementary status, not source of truth — the working tree + `git status` is.

### 2. Parser modularity
- **Evidence**: 28 parser-spec branches across 5 mail-client header layouts × 4 intents + edge cases (attachments, raw_excerpt cap, signature stripping, quote-block false-positive, plain-vs-HTML divergence warning, clock-skew handling).
- **Impact**: Adding a new mail client variant or a new intent now means writing one new BodyExtractor branch + one new dispatch line in `classify_intent`. The CC ordering, signature stripping, and skip detection are independent submodules that don't know about each other.

### 3. End-to-end idempotency
- **Evidence**: Action Mailbox `Message-ID` dedup, `Vendor.bootstrap!`, `Contact.find_or_create_for_email`, `RequestProvisioning.find_or_create_by!(source, metric_key)`, `SubmissionPromptScheduler.find_or_create_by!(tenant, request, status: :pending)`, `WeeklyDigestDelivery` unique on `(tenant_id, week_starting)`.
- **Impact**: Re-deliveries, re-runs, duplicate webhooks, and concurrent workers are all safe. No domain mutations require an explicit lock.

### 4. Test count over-delivered without over-engineering
- **Evidence**: Plan target was ~90-120 specs; final is 307 (Phase distribution: 89 / 58 / 38 / 57 / 37 / 28). RuboCop 0 across all phases.
- **Impact**: Heavy spec coverage on the parser (the highest-risk surface) and lighter on UI surfaces (which are template-rendered) is the right shape. The spec count grew because every service class had clean unit tests on top of the system tests, not because of redundant coverage.

### 5. FlowEvent as the audit trail
- **Evidence**: 8 distinct event_types emitted in Phase 4 alone (`reply.parsed`, `responsibility.created`, `question.skipped`, `question.revisited`, `reply.unparseable`, `reply.rejected_non_gm_sender`, `vendor.clarification_requested`, `vendor.bootstrap_from_clarification`). Phase 5 adds `source.configured`. Phase 6 adds `digest.sent`.
- **Impact**: Diagnostic queries during dogfood are one-liners. A separate "audit log" service was avoidable — the same write path that records the event is the one that creates the domain row, so they're atomic.

## Technical Challenges

### 1. Quarterly scheduler timezone bug
- **Description**: `Time.zone.local(year, month, 1)` constructed the date in the application zone (UTC), not the tenant zone. When converted to `America/New_York` it landed at the previous day's 8pm. Spec failed: expected July 1, got June 30.
- **Resolution**: Use `now.time_zone.local(...)` instead — the time zone is carried on the input `now`. Same fix applied to the half-year branch.
- **Prevention**: All date construction in tenant-scoped code should derive from `tenant.time_zone` (or a TimeWithZone the function received), never from `Time.zone` (the application default).

### 2. Phase 4 crash with uncommitted state
- **Description**: Build phase died mid-orchestration with all source on disk but uncommitted, and the task file's Execution State frozen at PHASE_3_COMPLETE.
- **Resolution**: Used the working-tree as ground truth: read every new file to confirm it was complete and well-structured, ran RSpec to confirm correctness, ran RuboCop, then updated memory bank and committed.
- **Prevention**: The cadence already prevents this from corrupting state. The only thing missing was a "is the build interrupted" check that uses `git status` rather than (or in addition to) the task file's Execution State.

### 3. Phantom `Source#has_many :responsibilities` association
- **Description**: Discovered in Phase 5 when `Setup::Completion` tried `source.responsibilities.where(status: :active).first` — there's no FK in the schema.
- **Resolution**: Replaced with explicit lookup: `TenantQuestion.where(tenant: source.tenant, key: source.responsibility_key).order(catalog_version: :desc).first`.
- **Prevention**: A model spec asserting `has_many` associations exercise their FK would have caught this in Phase 1. Worth adding a generic `it_behaves_like :well_formed_associations` shared example.

### 4. RSpec `.or raise_error` matcher composition
- **Description**: `expect { ... }.to raise_error(A).or raise_error(B)` is not supported (RSpec rejects compound expectations that both expect call-stack jumps).
- **Resolution**: Restructured to a manual `begin/rescue` capturing the exception, then `expect(error).to be_a(A).or be_a(B)`.
- **Prevention**: When the database might raise either `RecordInvalid` (validation) or `RecordNotUnique` (constraint) depending on race timing, write the test against the captured exception, not via `raise_error`.

### 5. `form_with` scoped radio buttons without a model
- **Description**: First pass at `method_picker.html.erb` used `f.radio_button :"source][submission_method", "form"` — a string-stuffing hack to nest params. Worked but ugly.
- **Resolution**: Use `form_with url: ..., scope: :source do |f|` which makes `f.radio_button :submission_method, "form"` produce `<input name="source[submission_method]">` cleanly.
- **Prevention**: Reach for `form_with`'s `scope:` parameter when nesting params under a non-model namespace.

## Process Assessment

### Effective Practices

- **Spec-first, then implement, then lint, then memory-bank, then commit.** Each phase's commit is one atomic snapshot. RuboCop catches style issues before they're locked in.
- **One `find_or_create_by!` per domain entry point**. Idempotency-by-default removes whole categories of "what if this runs twice?" bug classes from the design space.
- **Pure value-object services**. `OnboardingReplyParser`, `Accountability::DigestAssembler`, `OnboardingFlow::AdaptivePacing` — each returns a Struct; no callbacks, no state, no callers needing to mock. Made the test pyramid heavy on cheap unit tests.
- **`?step=` for multi-step flows.** Avoided over-engineering Turbo Frames or per-step routes for a 3-step walkthrough that's a one-shot for most users.
- **Recurring jobs with row-based idempotency.** `WeeklyDigestDelivery` is the synchronisation primitive; the unique index is the lock. No Redis, no advisory locks.
- **Pre-generated Message-IDs.** Outbound `question_email` ships with a deterministic Message-ID that gets persisted to `tenant_questions.outbound_message_id` before delivery completes. Inbound `In-Reply-To` resolution has nothing to race against.
- **Tracking Live-Dogfood-Pending items.** Three production-cutover items (inbound provider, outbound provider, S3 archive) sat in the tracker through the build instead of getting addressed inline. This kept scope tight.

### Improvement Opportunities

- **Earlier "system test for the full happy path".** Plan named `spec/system/gm_email_first_onboarding_full_loop_spec.rb` as the integration gate; it didn't ship. The mailbox spec's per-AC coverage is good but doesn't prove the seams between phases. Add this in a Phase-7 cleanup or before archive.
- **Phantom-association detection.** Add a small lib/spec helper that asserts every `has_many` declared on every model resolves to a real FK. Would have caught the `Source has_many :responsibilities` issue in Phase 1.
- **Tenant-zone date construction lint rule.** A custom RuboCop cop (or just a code-review checklist line) banning `Time.zone.local` inside tenant-scoped code would prevent the quarterly scheduler bug class.
- **Push earlier or push at all.** All 6 phase commits are local. Nothing's on `origin`. For a multi-day dogfood that can be picked up by anyone with the repo, that's fine; for a real team, push at the first phase commit (or use a draft PR per phase) so the work has external visibility.

## Business Impact

- **Closes the Phase-1 product bet.** ProductBrief frames the GM as "saturated with apps but fluent in email"; this task is the first concrete proof point that the email-only loop holds together end to end. Every subsequent feature (FEAT-002 lead ingestion, FEAT-003 dashboard, FEAT-004 escalations) leans on this substrate.
- **Operational footprint is one screen.** Rogue staff have a `/admin/tenants/new` form, basic-auth-gated, with three fields. No ticketing, no per-rooftop config files, no console invocations.
- **Audit story is built in.** `flow_events` plus indefinite raw-payload retention on `ActionMailbox::InboundEmail` (Guiding Principle 3) means any "why did Rogue do X for tenant Y on date Z" question is answerable from a single SQL query.
- **Multi-tenant isolation is enforced at the model level.** `tenant_id NOT NULL` everywhere except canonical models (`Vendor`, `Domain`); `Current.tenant` carried through; `gm_email_normalized` unique sitewide.

## Strategic Insights

### For Future Enterprise Work

1. **Ship the data substrate as Phase 1, even if the UI is empty.** Phase 1 created 11 migrations and 12 models with factories before any controller existed. Subsequent phases just attached behavior; no schema rework.
2. **Pure service classes returning value objects scale.** The Mailbox / Mailer / Job layers stay thin and dispatch on values; specs cover the values, not the I/O. This pays off compounding-ly as complexity grows.
3. **Idempotency is a design dimension, not a debugging concern.** Every entry point that meets external traffic (HTTP / inbound email / scheduled job / webhook) should have a natural idempotency key resolved in code via `find_or_create_by!` or in the database via a unique constraint.
4. **The audit log is the same write path as the domain mutation.** Don't build a separate "events service"; record the FlowEvent inside the same transaction that performs the mutation.
5. **Magic-link tokens scoped per purpose are essentially free.** Rails' `signed_id` machinery + a `Foo#thing_signed_id(expires_in:)` helper + `Foo.find_by_thing_signed_id` is a 6-line pattern that gives you token-gated URLs with no auth system.

### Reusable Components

- **`Threadable` mailer concern**: `onboarding_address(tenant)` + `canonical_subject(tenant, topic)` + `thread_with(message_id)`. Will move verbatim into FEAT-002+ when other mailers need to thread.
- **`OnboardingFlow::Scheduling.next_business_window`**: Pure function for Mon-Fri 9:30am-6pm in any timezone. Can be reused for any "deliver during business hours" requirement.
- **`OnboardingFlow::AdaptivePacing`**: J3's responsiveness-aware ladder is generic — applicable to any "schedule the next nudge based on how recently the user engaged" use case.
- **`FlowEvent.record!` pattern**: The single-write-path-with-actor/subject signature is reusable for any audited domain mutation.
- **`WeeklyDigestDelivery` idempotency primitive**: The "insert-the-marker-row-first; only deliver if save! succeeds" pattern works for any "once per period per entity" job.
- **`Setup::Completion` Result struct**: The pattern of wrapping a multi-step transaction in a service that returns a typed Result the controller can branch on is generally applicable.

## Action Items

### High Priority
- [ ] Replace `Source has_many :responsibilities` with either a real `source_id` FK on responsibilities or remove the association declaration (one Level-1 task).
- [ ] Add `spec/system/gm_email_first_onboarding_full_loop_spec.rb` as the end-to-end integration gate (Level 1 task).

### Medium Priority
- [ ] Delete unused `Tenant#next_question_cadence_gap`; everything routes through `OnboardingFlow::AdaptivePacing` (Level 1).
- [ ] Per-(Contact, Responsibility) signed token for setup walkthroughs so multi-assignment contacts get distinct URLs (Level 2 — schema + token + walkthrough lookup change).
- [ ] Add the `weekly_accountability_digest` recurring schedule to non-production environments (or document that it must be enqueued manually) in `techContext.md` (Level 1).

### Low Priority
- [ ] Custom RuboCop cop banning `Time.zone.local` inside tenant-scoped code (Level 2).
- [ ] Generic shared example for `has_many` association FK resolution (Level 1).
- [ ] Push feature branch to `origin` if dogfooding with anyone other than the original author (Level 1, operational).

## Claude Code Ecosystem Strategic Evaluation

### Executive Summary

For a Level 4 task with substantial scope (12 models, 6 phases, 307 specs, 6 mailer actions, 4 controllers, 1 mailbox, 4 jobs, 11 services), the ecosystem held up well. The progressive-context-loading pattern (load only the level-specific reflection rules; load step-N context inside step N) kept the working context manageable. The crash-recovery story was the strongest signal: the system survived a hard mid-build interruption without losing work, because (a) the working tree was the source of truth and (b) RSpec was the validation primitive.

The two friction points worth flagging: the `tasks/[task_id].md` Execution State machinery is heavyweight for a multi-phase build that takes one session, and the "spawn sub-agents per step" architecture wasn't actually used in this build (the orchestrator did the work directly), suggesting the orchestrate-everything design may be over-specified for compressed sessions.

### Command Architecture Assessment

| Command | Phases Used | Effectiveness | Strategic Notes |
|---------|-------------|---------------|-----------------|
| `/rai-init` | (pre-existing — not run in this session) | n/a | Memory Bank was already initialized. |
| `/rai-roadmap` | feature-create (pre-existing) | n/a | FEAT-001 was already created. |
| `/rai-plan` | (pre-existing) | n/a | Plan was already in place when this session started. |
| `/rai-creative` | (pre-existing) | n/a | All three creative phases (Architecture / User Journey / Algorithm) were complete. |
| `/rai-build` | 4, 5, 6 (this session) | 5 | The single most-used command. Worked smoothly across phase commits. The "resume after crash" path worked despite the orchestrator's Execution State being stale. |
| `/rai-reflect` | 6 (this command) | 4 | Template is comprehensive. Level 4 ecosystem-evaluation table burden is heavy but appropriate for the complexity tier. |
| `/rai-archive` | (next) | n/a | Will be evaluated post-archive. |
| `/rai-verify` | (not used) | n/a | The build flow's integrated rspec/rubocop made this redundant. |

**Command Gap Analysis:**
- **Missing**: A "phase-status" / "what's the build state" lightweight read-only command. When resuming a crashed build, the recovery flow had to read three files (`tasks/[task_id].md`, `progress.md`, working-tree `git status`) to reconstruct intent. A `rai-status TASK-XXX` that summarizes those three sources in 10 lines would shorten the recovery loop.
- **Missing**: A "rollback this phase" command. If a phase commit goes sideways post-merge, the recovery is `git revert <sha>` plus manual memory-bank rollback. A scripted version would help.

### Workflow Architecture Assessment

| Phase | Duration | Friction Level | Value Delivered |
|-------|----------|----------------|-----------------|
| INIT | (pre-existing) | n/a | Memory Bank scaffolding — very high one-time value. |
| PLAN | (pre-existing) | n/a | The Spec Writer agent's output (Specification + Test Strategy + Implementation Roadmap + Creative Phases) was the single most useful artifact for this build. |
| CREATIVE | (pre-existing) | n/a | The three creative docs (Architecture A1-A4, User Journey J1-J5, Algorithm L1-L2) compressed into the implementation cleanly — no re-litigation of decisions during build. |
| BUILD (Phase 4 resume) | ~minutes | Low | Crash recovery path worked. |
| BUILD (Phase 5) | ~minutes | Low | Smooth — TDD RED→GREEN→lint→commit. |
| BUILD (Phase 6) | ~minutes | Low | Same. |
| REFLECT | (in progress) | Medium | Template is heavy but comprehensive; appropriate for Level 4. |
| ARCHIVE | (next) | n/a | TBD. |

**Workflow Recommendations:**
- The INIT→PLAN→CREATIVE→BUILD→REFLECT→ARCHIVE workflow is well-suited to this scale. The handoff quality between phases is high because each phase writes durable artifacts (creative docs, task file roadmap, progress.md entries) that the next phase reads.
- The Execution State sub-section of `tasks/[task_id].md` is heavyweight for compressed sessions where build phases run in minutes. For session-scale builds, consider letting the working tree + commit log be the state, with Execution State updated only at phase boundaries (not every step).

### Context System Assessment

| Context Category | Files Loaded | Usefulness | Token Efficiency |
|------------------|--------------|------------|------------------|
| Level-specific build/reflection rules | `level4-implementation.md` (implicit), `level4-reflection.md` (explicit) | 4 | Good — only loaded when relevant. |
| Agent prompts | `reflection-agent.md` referenced (not read this session) | n/a | Lazy-loaded via the methodology link in agent prompts. |
| Project-level (CLAUDE.md, productBrief, systemPatterns, techContext) | All implicitly loaded | 5 | High value. The CLAUDE.md "Tool Usage Rules" section in particular saved permission prompts. |
| Phase-step build files (step3-test-writer.md, etc.) | Not loaded this session (orchestrator did work directly) | n/a | Progressive-discovery pattern means these are only read when their step runs. |

**Context Gaps:**
- No explicit "what changed since the last commit" context primer. Each phase commit's message is detailed, but a synthesized "rolling brief" (similar to progress.md but pruned to what's actively in flight) would help when resuming after long gaps.
- Live agent-rules indexing (`memory-bank/agent-rules-index.md`) wasn't run this session — the project doesn't have user-supplied agent rules yet. Once it does, the Step 0.1 rules-index check will become more load-bearing.

**Context Redundancy:**
- The build command file is ~700 lines of orchestration logic that's largely descriptive of an architecture the orchestrator can implement directly. For Level 4 builds done in a single agent session, ~70% of the command's content is reference material the orchestrator doesn't act on. Could be trimmed to ~200 lines + a "see full architecture for sub-agent delegation" link.

### Tool Utilization Analysis

| Tool | Approx Operations | Success Rate | Limitations Encountered |
|------|------------------:|--------------|-------------------------|
| Read | High | ~100% | None encountered. |
| Edit | High | ~100% | The "must Read before Edit" rule was hit once or twice on freshly-stashed files; minor friction. |
| Write | Medium | ~100% | None encountered. |
| Glob | Low | 100% | None. |
| Grep | Low | 100% | None. |
| Bash | High | ~100% | The "no compound commands with `&&`" rule (per CLAUDE.md) prevented one rubocop-stash-pop sequence that would have been more efficient. The denial was correct — the rule favors safety over throughput. |
| Task (sub-agent) | 0 | n/a | Not used this session. The build orchestration was done directly. |
| TaskCreate / TaskUpdate | High | 100% | The system-reminder cadence ("you haven't used task tools recently") felt over-eager during routine file edits. |

**Tool Gap Analysis:**
- **Missing**: A "checkpoint" primitive that is a logical save-point but doesn't require a git commit. Useful inside long phases where you'd like to mark a sub-phase as committed-to-disk-but-not-to-history without polluting the commit log.
- **Missing**: An RSpec-aware tool that could run a single example by description-substring without invoking Bash. Probably out of scope; Bash + `bundle exec rspec` works.

**Workarounds Required:**
- The "no compound commands" rule meant some sequences (stash → run rubocop → stash pop) had to be split. Fine for safety; minor throughput cost.

### Subagent Architecture Assessment

| Agent Type | Invocations | Output Quality | Prompt Issues |
|------------|------------:|----------------|---------------|
| Build Test Writer / Coding Agent / etc. | 0 (orchestrator did directly) | n/a | The "spawn agent per step" architecture is explicit in the build command but went unused this session. For a single-agent session covering 3 phases, in-context execution was strictly faster. |
| Reflection agent | 0 (this reflection drafted directly) | n/a | Same — for a single-agent session with full conversational context, drafting in-context is more accurate than spawning a fresh agent that has to re-read everything. |

**Agent Prompt Improvements:**
- The build command's Step 3-9 sub-agent prompts assume the orchestrator has not done the work itself. For sessions where the orchestrator IS doing the work, the prompts read as instructions to a stranger — appropriate for the spawn-an-agent path but verbose for the in-context path.

**New Agent Types Needed:**
- A "build-resume-from-crash" agent that runs `git status` + `bundle exec rspec` + reads the task file's Execution State and produces a 10-line "where you left off" report. Would compress the recovery flow to one tool call.

### Memory Bank Architecture Assessment

| Document Type | Created | Utility | Maintenance Burden |
|---------------|---------|---------|-------------------|
| `tasks.md` registry | Y | 4 | Low — one row to update per phase. |
| `tasks/TASK-001.md` | Y | 5 | The Implementation Roadmap section is the single most-useful artifact. The Execution State section is heavier than needed for in-session builds. |
| `progress.md` | Y | 4 | Append-only per phase; low burden. |
| `creative/TASK-001-*.md` (3 files) | Pre-existing | 5 | Compressed into build cleanly; zero re-litigation. |
| `reflection/reflection-TASK-001.md` | Y (this file) | TBD | Heavy template but appropriate for Level 4. |
| `archive/archive-TASK-001.md` | (next) | TBD | TBD. |

**Knowledge Preservation Quality:**
- Phase commit messages are dense and self-contained — re-reading just the commit log gives a complete picture of what shipped. This is the highest-fidelity artifact in the system.
- `progress.md` plus `tasks/TASK-001.md` Completed Steps log together give a phase-by-phase narrative.
- The creative docs (A1-A4, J1-J5, L1-L2) effectively serve as the architecture decision record (ADR).

**Cross-Reference Effectiveness:**
- The `tasks.md` → `tasks/[task_id].md` → `creative/[task_id]-*.md` → `reflection/reflection-[task_id].md` chain is intuitive and discoverable.
- The `agent-rules/_learned/` directory is empty (this is the first reflection); the consolidate-first extraction pattern in Step 3.5 is the right shape but its long-term effectiveness can only be evaluated after several reflections feed it.

### Ecosystem Scalability Assessment

| Metric | Observation | Impact |
|--------|-------------|--------|
| Context window pressure | Low | The 1M-context model handled the full conversation comfortably. |
| Token efficiency | Good | Progressive context loading + lazy file reads kept token usage proportional to the work done, not to the total system size. |
| Phase handoff quality | Smooth | Memory-bank artifacts (creative docs, task file roadmap, progress.md) make handoffs durable across sessions. |
| Recovery from errors | Good | Phase 4 crash recovery validated the resilience. |

### Strategic Improvement Recommendations

> **Note**: Recommendations only. Implementation is out of scope for reflection.

#### Immediate (High Priority)
| Recommendation | Component | Rationale | Expected Benefit |
|----------------|-----------|-----------|------------------|
| Trim `/rai-build` command file from ~700 lines to ~200 + reference link | `commands/rai-build.md` | ~70% of current content is reference material the orchestrator doesn't act on in single-session builds | Faster context load, less cognitive overhead per phase |
| Add `rai-status TASK-XXX` lightweight read-only command | `commands/` | Crash-recovery flow currently requires reading 3 files to reconstruct intent | One-tool-call recovery primer |

#### Short-term (Medium Priority)
| Recommendation | Component | Rationale | Expected Benefit |
|----------------|-----------|-----------|------------------|
| Make Execution State updates phase-boundary only (not per-step) for in-session builds | `commands/rai-build.md` State Tracking section | Per-step state writes are heavy for builds that take minutes | Less memory-bank churn, simpler commits |
| Document the "in-context execution vs spawn-agent" branching point | `commands/rai-build.md` | Sub-agent architecture went unused this session; the choice should be explicit | Clearer ergonomics for future builds |

#### Long-term (Strategic)
| Recommendation | Component | Rationale | Expected Benefit |
|----------------|-----------|-----------|------------------|
| Build-resume-from-crash sub-agent type | `agents/` | Crash recovery is a recurring pattern worth dedicated tooling | Faster, more reliable recovery |
| RuboCop cop banning `Time.zone.local` in tenant-scoped code | (project, not Claude) | Bug class encountered in this task | Prevents future TZ regressions |

### Patterns Worth Codifying

1. **Insert-marker-row-first idempotency for recurring jobs.** `WeeklyDigestDelivery.create!` first; only deliver mailer on save success. Unique constraint is the lock. Generalizes to any "once per period per entity" job.

2. **Pure value-object services on top of stateful entry points.** Mailbox / Job / Controller layers stay thin; service classes return Structs. Specs hit the values; mocks are unnecessary.

3. **Single-controller, query-param-state walkthroughs.** `?step=` + state-driven short-circuit is simpler than per-step routes for resumable multi-step flows where most users complete in one shot.

4. **Pre-generate Message-IDs for outbound mail that will be replied to.** Persist the ID on the related domain row before delivery. Inbound resolution becomes deterministic and race-free.

5. **FlowEvent as the audit trail.** Single `flow_events` table with `event_type` + `tenant_id` + `subject_*` + `payload` JSONB columns. Same write path as the domain mutation; atomic with it. Avoids a separate audit service.

6. **Recoverable build cadence.** Spec → implement → lint → memory-bank → commit. Working tree is the source of truth; Execution State is supplementary. Survives mid-build interruption gracefully.

## Extractable Learnings

These are condensed, actionable directives intended for `memory-bank/agent-rules/_learned/` extraction (per `/rai-reflect` Step 3.5):

- **idempotency** (paths: `app/jobs/`, `app/mailboxes/`, `app/services/`, topics: idempotency, recurring-jobs): Recurring jobs and inbound handlers must establish idempotency via a unique-constraint marker row (`find_or_create_by!` or `create!` with rescue of `RecordNotUnique`) BEFORE any side effects fire. **Why**: protects against re-deliveries, concurrent workers, and accidental re-runs without distributed locks. **How to apply**: any job declared in `config/recurring.yml`, any Action Mailbox `process` method, any webhook handler.
- **time-zones** (paths: `app/services/`, `app/models/`, topics: time-zones, scheduling): When constructing dates/times in tenant-scoped code, derive the zone from the tenant or from a TimeWithZone you received — never from `Time.zone` (the application default leaks UTC). **Why**: scheduled timestamps cross calendar boundaries and land on the wrong day. **How to apply**: anywhere you call `Time.zone.local`, `Date.current`, or `.beginning_of_*` inside a method that takes a Tenant or a `time_zone:` argument.
- **service-shape** (paths: `app/services/`, topics: service-classes, testing): Pure service classes should return typed value objects (Struct with `keyword_init: true`) not raw values; callers branch on the value, not on multiple return types or exceptions. **Why**: makes the call site greppable, mockable, and testable without database state. **How to apply**: any service that has more than one outcome (success/failure/skip), any service whose result is consumed by a view or controller branch.
- **audit-trail** (paths: `app/mailboxes/`, `app/services/`, `app/jobs/`, topics: audit-logging, observability): Record domain events through a single `FlowEvent.record!` call inside the same transaction that performs the domain mutation; do not build a separate audit service. **Why**: keeps the audit and the mutation atomic, and makes "what happened to X on Y" a one-query lookup. **How to apply**: any state transition, any external-traffic acknowledgment, any cross-cutting domain event.

## References

- **Plan + roadmap**: `memory-bank/tasks/TASK-001.md`
- **Architecture decisions**: `memory-bank/creative/TASK-001-architecture.md` (A1-A4)
- **User-journey decisions**: `memory-bank/creative/TASK-001-user-journey.md` (J1-J5)
- **Algorithm decisions**: `memory-bank/creative/TASK-001-algorithm.md` (L1-L2)
- **Build phase summaries**: `memory-bank/progress.md`
- **Phase commits**: `60f83f6` (P1) → `acf56c0` (P2) → `edb06de` (P3) → `6a3e395` (P4) → `94623f2` (P5) → `241a73e` (P6)
- **Final state**: 307 RSpec examples / 0 failures / 0 RuboCop offenses on `feature/FEAT-001-tenant-gm-email-onboarding`
