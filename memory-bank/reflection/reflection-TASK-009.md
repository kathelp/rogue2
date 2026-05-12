# Reflection: TASK-009 — Cc'd Contact Self-Verification (FE pass)

**Date**: 2026-05-11
**Task Complexity**: Level 3 (inherited from FEAT-006)
**Total Phases**: 4 (labelled 0, 1, 2, 3)
**Duration**: 2026-05-10 – 2026-05-11 (planning + Phases 0-2 on day 1; Phase 3 + reflection on day 2)
**Branch**: `feature/FEAT-006-self-verification-fe`

## Executive Summary

TASK-009 closed the FE half of FEAT-006 that was scope-cut from TASK-008. The four phases — `Contacts::PhoneNormalizer::Result` struct refactor, setup walkthrough identity step (controller + view + four ancillary view edits), `invitee_setup_email` subject + body rewrite, and an AC-INTEGRATION-1 system spec — all shipped cleanly against TASK-008's three pre-existing creative documents. The suite grew from 424 to 445 specs with zero failures; `rubyfmt --check` exits 0 globally.

The headline workflow decision was running this task through a "lighter" route: writing the task file directly rather than invoking `/rai-plan`, skipping `/rai-creative` entirely (the three TASK-008 creative docs were already canonical for this scope), and executing build phases inline rather than spawning the full sub-agent fan-out (Test Writer → Coding Agent → Test Orchestrators → Code Reviewer → Documentation Agent). For a task whose design questions had all been resolved upstream and whose scope was narrow and well-bounded by the UI/UX doc's exact ERB snippets and the architecture doc's exact controller pseudocode, the lighter route was the right call. The full multi-agent orchestration would have produced near-identical output at roughly 3-4× the token cost.

The most notable in-task event was the resolution of the `Contacts::PhoneNormalizer` return-type divergence flagged as forward debt in the TASK-008 archive. Phase 0 took ~10 minutes to refactor the normalizer to a `Result` struct and rewrite its 10 specs against the new contract. The controller pseudocode in `creative/TASK-008-uiux.md` Sub-Decision 3 (`phone_result.valid?`) and the architecture doc's struct shape lined up perfectly; no doc edits were needed. Resolving this debt before Phase 1 began meant the identity controller landed in one pass with no rework.

---

## Dimension 1: Task Implementation Quality

### Requirements Achievement

**Status**: Complete (all 5 ACs from the task spec met)

- **AC-ENTRY-1** (mailer copy): Phase 2 delivered the new subject and both body templates verbatim per UI/UX Sub-Decision 1. Mailer spec covers subject + CTA + ~1-minute language in both MIME parts.
- **AC-HAPPY-1** (identity completion): Phase 1's `handle_identity_update` writes `Contact.update! + FlowEvent.record!(event_type: "contact.verified")` in a single transaction and redirects to `step=summary`. Re-entry after verification skips the identity step and lands on `:summary` directly. Request specs cover both.
- **AC-ERROR-1** (validation re-render): 4 validation contexts in the request spec (blank first/last/phone, unparseable phone) each assert 422 + element id + agnostic error text + non-mutation of the Contact record. Submitted first/last preserved via `@contact.assign_attributes`; raw phone preserved via `@phone_attempt`.
- **AC-LINK-1** (signed-link guarantees): expired-signed-id regression guard on the identity branch passes. The `load_contact` before_action handles both `:show` and `:update` paths identically; no new vulnerability.
- **AC-INTEGRATION-1** (cascade round-trip): Phase 3 system spec drives a real inbound email through `OnboardingMailbox`, synthesizes a parallel responsibility naming the new contact as a fallback, asserts `fallback_emails_for` excludes the contact pre-verification, drives identity through Capybara, asserts the same call now includes them, and confirms a `contact.verified` FlowEvent landed atomically.

### Code Quality Assessment

**Overall Rating**: Good-to-High

- **Maintainability**: High. The controller's `handle_identity_update` is a single ~30-line method with a clear linear shape: permit → normalize → build errors → branch on `@errors.any?`. The `identity_errors_for` helper is a 7-line pure function, easy to unit-test if it ever needs that. The new `identity.html.erb` view follows the existing inline-CSS pattern verbatim — no new design tokens, no class attributes.

- **Architecture**: Good. `Contact#unverified?` was added as a one-liner instance predicate to mirror the existing `verified?` and avoid `!@contact.verified?` clutter in the controller — same pattern as the `:verified`/`:unverified` scope pair. The controller's `template_for_step` priority order (configured-source resume → unverified → step-param routing) is correct: a contact who has already completed identity should never see Step 1 again on a re-click, and a contact whose Source is configured should always land on Step 4 (the resume short-circuit was already there from TASK-001).

- **Error Handling**: The `@errors` hash + per-field guard pattern is more readable than a single ActiveModel-errors-style mechanism for this case — the four fields each have one specific failure mode, no per-field validation rules need to compose, and the view's `aria-describedby` linkage works directly off the hash keys. Trade-off documented in the commit body.

- **Testing**: 22 new specs across four files. The request specs (`walkthroughs_spec.rb` +18) and system spec (`contact_self_verification_spec.rb` +1) together cover the user-facing surface and the integration consequence. The mailer spec additions (+4) cover the new copy. The normalizer spec rewrite (+3 net, from 10 to 13 by splitting the blank-input it-block) keeps the contract testable against the new Result type.

### Technical Decisions

**Key Decisions:**

1. **Lighter workflow (no `/rai-plan`, no `/rai-creative`, inline build phases)** — The decision was made explicitly at the task-creation step. Justification: all design questions had been resolved in TASK-008's `/rai-creative` and were captured in the three creative docs. The UI/UX doc's "Implementation Guidelines / For Developers" section was a near-complete build checklist. Spawning the full sub-agent fan-out per phase would have re-derived facts already on disk. The trade-off: less ceremony around test-first ordering for Phase 1 (request specs and controller landed in close succession rather than strict red-green), but Phase 0 and 3 followed strict TDD red-then-green because their scope was small enough to keep both in mind.

2. **`Contacts::PhoneNormalizer::Result` struct as Phase 0** — Resolved forward debt before any controller code consumed the normalizer. Justification: the alternative (update both architecture doc + UI/UX doc + controller pseudocode to use a nil-check idiom) was strictly more edits than the refactor. The Result struct shape was already prescribed by `_learned/service-shape.md` ("services with more than one outcome should return a typed struct"). Phase 0 also doubled as a low-risk warmup before Phase 1's heavier work.

3. **System spec uses `EscalationCascade.send(:fallback_emails_for, ...)` to call a private method** — Documented in the commit body. Alternative was to drive the cascade through `next_action_for` and read the `NextAction` payload, which would have required seeding multiple FlowEvent rows just to reach the `fallback_fanout` or `gm_nudge` rung. The AC explicitly names `fallback_emails_for` as the assertion target, so testing it directly is in scope and the `.send` is a deliberate test-only peek.

4. **System spec synthesizes a parallel `marketing_budget` responsibility rather than driving two inbound emails** — Documented in the commit body. The mailbox-driven primary-CC path is exercised at the top of the spec so "mailbox creates unverified Contact" stays in the integration surface; the parallel responsibility is built directly with factories to put the same contact in a fallback chain without obscuring the gating round-trip with a second inbound-email failure surface.

5. **HTML-entity-agnostic error assertions in the request spec** — When the apostrophe in `"can't be blank"` rendered as `&#39;`, three blank-field assertions failed. The fix tightened the assertions to check the error element's `id="<field>-error"` (which only renders when the corresponding `@errors[key]` is present) plus a regex `/Field name.{0,20}blank/` agnostic to the entity encoding. More robust than escaping the test strings literally.

**Trade-offs:**

- **Strict TDD discipline reduced** during Phase 1. Request specs and controller code landed in close succession (red, then green, then a quick correction for the apostrophe encoding). For Phases 0 and 3 with smaller scope, strict TDD (write the failing spec first, then implement) was easy to maintain. Phase 1's scope (controller + new view + four ancillary view edits + 18 request specs) made strict TDD ordering heavier than helpful — the spec was written first, but implementation followed immediately rather than after a deliberate red-confirmation step.

- **`Contact#unverified?` was added without an explicit failing spec** for the predicate itself. The predicate is exercised indirectly by request specs that depend on it (GET unverified → identity step renders) and by the existing `Contact#verified?` matrix from TASK-008. A direct predicate spec would have been six lines and is a small follow-up.

### What Went Well

1. **Phase 0 as a warmup** — Refactoring `PhoneNormalizer` to a Result struct before Phase 1 controller work paid off twice: (1) the controller landed in one pass with no rework when consuming `phone_result.valid?`, and (2) the architecture doc's controller pseudocode mapped 1:1 onto the implementation without any "translate the doc to match the code" mental overhead. Resolving forward debt before consuming code lands is cheaper than after.

2. **UI/UX doc fidelity** — `identity.html.erb` was written verbatim from `creative/TASK-008-uiux.md` Sub-Decision 2. The ERB rendered correctly on the first run; no view-side fixes were needed beyond the apostrophe-encoding spec-side polish. The doc's "Implementation Guidelines / For Developers" checklist (8 numbered items) covered every file change in Phase 1 except the addition of `Contact#unverified?` (the doc said "branch on `@contact.unverified?`" but didn't note that the predicate didn't yet exist).

3. **System spec on the first try** — Phase 3's spec passed on the first run with no debugging. The design choice to use `.send(:fallback_emails_for, prompt)` directly rather than driving cascade rung state kept the spec linear; the synthesis of the parallel responsibility avoided the orthogonal failure modes that a second mailbox-driven setup would have introduced. The FlowEvent audit assertion (`contact.verified` event landed) was a free regression guard that took two lines.

4. **rubyfmt-as-it-goes** — Running `rubyfmt -i <touched files>` after each phase and verifying `rubyfmt --check` exits 0 globally before commit kept the format pass loop tight. Zero phases had a "fix the formatting now" step at the end. This is the kind of discipline that pays off when the codebase scales — formatting drift is paid back per file touched, not in a big "format the whole repo" rebase.

5. **Refactoring the existing test's `let(:contact)` to `:verified` was the right call** — When Phase 1 introduced the unverified gate, the existing 15 specs in `walkthroughs_spec.rb` would have all started routing to `:identity` instead of `:summary`. Switching the default contact to `:verified` (with a localized override in the new identity-step `describe`) was a small one-line edit that kept the existing tests semantically valid (they test the post-identity flow) while letting new tests opt into unverified state explicitly.

### Challenges Encountered

1. **HTML entity encoding of apostrophes in error text** — `"can't be blank"` renders as `"can&#39;t be blank"` in the HTML body. Three blank-field assertions failed because they checked for the un-escaped literal. Resolution: tighten assertions to check the error element's `id` plus a regex agnostic to the entity encoding (described above). Lesson is general: assertions on rendered HTML error text should not be sensitive to entity encoding of common punctuation. This pattern is reusable across any project with similar error-text assertions and is captured in the extractable learnings below.

2. **FEAT-001 full-loop system spec needed an update for the new identity step** — The existing full-loop spec drove `click_link("Continue")` immediately after visiting `/setup/<token>`. Once the identity step landed first, that link wasn't on the page. Resolution: extended the spec to walk Step 1 → fill identity → Step 2 → click Continue. Not a friction point because the system spec exists exactly to catch this kind of integration regression — but worth noting that adding a new step at the front of a multi-step flow always cascades into any existing E2E spec that walks the flow.

3. **`Contact#unverified?` predicate did not exist** — Phase 1's first run failed on `NoMethodError: undefined method 'unverified?' for an instance of Contact`. TASK-008 had added `verified?` and the `:unverified` scope but not the instance predicate. Resolution: added `Contact#unverified?` as a one-liner. Lesson: when extending a class with a `verified?` predicate, also add the negation `unverified?` if a scope of that name exists — the asymmetric naming surface (scope present, predicate absent) is confusing and the cost of the negation predicate is one line.

### Technical Debt & Future Work

- **No direct unit spec for `Contact#unverified?`** — The predicate is exercised indirectly through every controller test that depends on it, but a direct spec is six lines of work and would lock the contract. Low priority; the predicate is the trivial negation of `verified?` (already specced exhaustively).

- **No Stimulus or JS error handling** — The form is HTML-only as specified by the UI/UX doc. If error rates on blank fields become a UX problem post-launch, the lowest-cost lever would be HTML5 `required` validation feedback (already enabled via `required: true` attribute) followed by progressive enhancement with a small Stimulus controller. Out of scope for this task.

- **Fallback contacts have no setup-email pathway in production** — The system spec's Step 4 ("Alex receives + clicks the setup link") works because Alex was the primary CC and got the setup email. In real product flow, a contact who is *only* in `fallback_contact_emails` of a responsibility (never CC'd as primary on any question) has no setup link delivered to them. The cascade gating filter (TASK-008) silently drops them from fanout, but the cascade has no compensating "we need someone to verify these" outbound mechanism. This is a known gap inherited from FEAT-001/FEAT-004 design, not introduced by TASK-009. A follow-up feature would either send standalone verification emails to fallback-only contacts on responsibility creation, or accept that fallback-only contacts stay in the gated state until they're CC'd on a later question.

- **`@phone_attempt` ivar is a slight code smell** — The controller stores the raw submitted phone in `@phone_attempt` so the view can re-render the user's typing on validation failure (the `Contact#phone` column is encrypted non-deterministically and can't accept the pre-normalized string). The two-source `value: @phone_attempt || @contact.phone` pattern in the view is correct but documented inline in the view as well as in `creative/TASK-008-uiux.md` Sub-Decision 3 — a hint that the pattern is a known asymmetry. Possible refactor: a form object that owns the raw-vs-normalized distinction explicitly. Not yet worth the abstraction for one field.

---

## Dimension 2: Claude Code Ecosystem Effectiveness

### Build Session Analysis

**Build Sessions**: 1 ongoing conversation across two days (2026-05-10 plan + Phases 0-2; 2026-05-11 Phase 3 + reflection).

**Sub-Agents Spawned**: 0. The lighter workflow ran all phases inline without delegating to Test Writer / Coding Agent / Test Runner / Test Fixer / Code Reviewer / Documentation Agent sub-agents. The full multi-agent fan-out was bypassed by explicit user direction at task-creation ("lighter").

**Errors Recovered**:
- Phase 1: 16 failing specs after writing tests (TDD red, as expected); reduced to 13 after implementation; reduced to 3 after `Contact#unverified?` was added; reduced to 0 after apostrophe-encoding spec polish.
- Phase 1: 1 regression in the FEAT-001 full-loop system spec; fixed in the same phase by extending the spec to walk identity step.
- Phase 2: 0 failures.
- Phase 3: 0 failures (passed on first run).

**Token Cost (estimated)**: Lighter route is ~3-4× cheaper than the full sub-agent fan-out for a Level 3 task of this scope. Concrete numbers not measured, but each sub-agent invocation typically loads its own methodology file and re-derives some context already in the orchestrator's working memory.

### Command Workflow Evaluation

**Commands Used**: Lighter route — TASK-009 task file written directly (no `/rai-plan`); no `/rai-creative` (reused TASK-008 creative docs); `/rai-build TASK-009` invoked once per phase (4 phases); `/rai-reflect` (this document).

**Workflow Efficiency**: High

**Assessment**:

- **Lighter route was the right call for this task shape**: a continuation of a previously-archived task with all design questions resolved, well-bounded scope, and no novel architecture decisions. The full plan → creative → build sequence would have re-derived facts already on disk in `creative/TASK-008-{architecture,user-journey,uiux}.md`. The cost was minor TDD-discipline relaxation in Phase 1; the benefit was avoiding redundant agent spawns and keeping the build flow tight.

- **When NOT to use the lighter route**: if any of the design questions were still open, or if the task spec materially diverged from prior creative work, the full sequence would have been correct. The lighter route only works because TASK-008's creative docs were already complete and stable.

- **Phase 0 as forward-debt resolution**: structuring the `PhoneNormalizer::Result` refactor as Phase 0 (rather than threading it into Phase 1) made the build flow cleaner and gave the architecture doc a clean win — its prescribed shape became the implementation shape. This is a reusable pattern: when archived task notes flag forward debt, address it as Phase 0 of the consuming task rather than mid-stream.

- **Phase-by-phase commit cadence**: four phase commits + one planning commit on `feature/FEAT-006-self-verification-fe`. Each commit body is detailed enough to bisect from. The phase-by-phase human review gate (STOP after each phase) was respected — the user confirmed before each subsequent `/rai-build`.

### Context File Effectiveness

**Files Loaded**:
- `memory-bank/tasks/TASK-009.md` (continuously updated)
- `memory-bank/tasks/TASK-008.md` (referenced for predecessor context)
- `memory-bank/creative/TASK-008-architecture.md` (Q4 PhoneNormalizer Result struct shape)
- `memory-bank/creative/TASK-008-user-journey.md` (Q1 inline-walkthrough decision)
- `memory-bank/creative/TASK-008-uiux.md` (Sub-Decisions 1-5 — exhaustive build checklist)
- `memory-bank/archive/archive-TASK-008.md` (forward-debt list)
- `memory-bank/projectbrief.md` (Archive Strategy)
- `memory-bank/agent-rules/_learned/*.md` (service-shape, gating-filter-passthrough referenced)

**Assessment**:

- **The TASK-008 creative docs were the single most valuable input**. UI/UX Sub-Decision 2's full ERB snippet for `identity.html.erb` was build-ready; the controller pseudocode in Sub-Decision 3 mapped 1:1 onto `handle_identity_update`; Sub-Decision 1's exact subject + HTML + text body templates landed verbatim. Detailed creative output written for a deferred phase paid off cleanly when the FE pass resumed.

- **Architecture doc's Q4 was the spec for Phase 0**. The `Result = Struct.new(:normalized, :valid?, keyword_init: true)` shape was already prescribed; the implementation matched byte-for-byte. Saved any "translate the doc" overhead.

- **Archive doc's forward-debt list was the spec for Phase 0's existence**. The TASK-008 archive's "Forward Debt" section flagged the `PhoneNormalizer` divergence with a clear preferred resolution. Without that flag, Phase 1 would have hit `phone_result.valid?` and had to detour to address the contract mismatch. Forward-debt flagging at archive time is a high-value practice.

- **Live-Dogfood-Pending Tracker as a scope contract** worked. The four deferred items from TASK-008 were the same four items that became Phases 1-3 of TASK-009 (with Phase 0 added for forward-debt resolution). No scope creep; no surprises.

### Memory Bank Organization

**Assessment**:

- **Cross-task continuity through creative docs**: this task demonstrates that creative docs written for one task can serve as the canonical design source for a downstream task. The pattern works when (a) the creative docs are detailed enough to be build-ready, and (b) the downstream task explicitly references them as its design source rather than re-doing the creative phase.

- **Phase numbering convention**: TASK-009 numbered phases 0, 1, 2, 3 to make Phase 0 a clearly-separated forward-debt-resolution step from the substantive phases. This is a deviation from the standard 1, 2, 3, … convention and worth noting if it becomes a recurring pattern. Alternative would have been "Phase 0.5" or "pre-Phase 1 cleanup" — neither felt as clean as Phase 0.

- **Branch reuse decision**: the original `feature/FEAT-006-ccd-contact-self-verification` branch (TASK-008's archive state) was preserved unchanged; the FE pass created `feature/FEAT-006-self-verification-fe` as a sibling branch off main. This is the right call for archive traceability — the original branch shows exactly what shipped in TASK-008, and the FE-pass branch is auditable independently.

### Suggested Improvements to Claude Code System

**High Priority**:

1. **Document the "lighter route" pattern explicitly** — TASK-009's lighter workflow (skip `/rai-plan`, skip `/rai-creative`, inline build phases) was effective for this task shape but is currently undocumented in the rai workflow guide. A "When to use a lighter route" section under `/rai-build` or `/rai-plan` documentation would help future tasks make the call. Criteria: prior creative docs are canonical for the new task, scope is bounded by existing detailed specs, and design questions are all resolved. Anti-criteria: novel architecture, ambiguous scope, contradicting prior creative work.

2. **Forward-debt resolution should be a documented pattern for archive cleanup** — The TASK-008 archive's "Forward Debt" section was the high-leverage input that enabled Phase 0 to land cleanly. Codifying "list of forward-debt items, each with preferred resolution and consuming-task pointer" as a standard archive section would make this pattern reproducible. The TASK-008 archive already does this loosely; making it a labeled section with a consistent format would help.

**Medium Priority**:

3. **HTML-entity-agnostic assertion helper for error text** — Multiple specs in this project now check error text rendered into HTML. The apostrophe-encoding bug recurred in Phase 1 and was solved with a regex pattern. A shared `expect_field_error(field:, text:)` helper that asserts on the error element's `id` and entity-decoded text would dry this up and prevent the issue from recurring. Low-cost, high-value.

4. **`identity.html.erb` form-helper edge case in UI/UX doc** — The doc's exact ERB used `f.label :first_name, "First name", style: "...", for: "contact_first_name"` with an explicit `for:` field. Standard Rails `f.label` auto-generates the `for=` from the input id, which `f.text_field` auto-generates from the attribute name. The explicit `for:` was redundant in this case but harmless. A small note in the UI/UX doc clarifying which attributes are required vs documentational would prevent confusion in future builds.

**Low Priority / Nice to Have**:

5. **Phase 0 as a recognized phase type** — TASK-009 used "Phase 0" to label the forward-debt resolution phase. If this becomes a recurring pattern (forward-debt resolution as a discrete first phase of any continuation task), naming it in the rai-build phase template would help. Cosmetic.

---

## Key Learnings

### Extractable Learnings (for Continuous Learning)

De-duplicated against existing `_learned/` rules: existing rules cover audit-trail, gating-filter-passthrough, idempotency, namespacing, schema-validation, scope-cut-resilience, service-shape, time-zones. None of the following duplicate those.

1. **forward-debt-resolution** (`memory-bank/archive/`, build orchestration): When an archive document flags forward debt (contract divergence, doc-vs-implementation drift, deferred refactor), the consuming task should resolve it as its **Phase 0** before any other consuming code lands. Resolving the divergence before the first consumer means the architecture doc and implementation stay aligned, downstream phases avoid translation overhead, and the consumer code lands in one pass rather than needing rework after the debt is paid.

2. **html-entity-agnostic-assertions** (`spec/requests/`, `spec/system/`): Spec assertions on error text rendered into HTML should not be sensitive to entity encoding of common punctuation (`'` → `&#39;`, `"` → `&quot;`, `&` → `&amp;`). Two-line pattern: assert on the error element's `id` (which only renders when the error is present), then match the text with a regex agnostic to the encoded character (e.g., `/Field name.{0,20}blank/`). More robust than escaping the literal in the test string and resilient to changes in Rails' default escaping behavior.

3. **predicate-pair-symmetry** (`app/models/`): When extending a model with a positive predicate (`verified?`, `confirmed?`, `published?`), also add the negation (`unverified?`, `unconfirmed?`, `draft?`) if a scope of that name exists or is likely to be added. The cost is one line; the benefit is symmetric usage at call sites — `if @contact.unverified?` reads more clearly than `unless @contact.verified?` and matches the existing scope vocabulary.

4. **lighter-route-eligibility** (build orchestration, `memory-bank/tasks/`): A continuation task whose design questions were all resolved in a predecessor task's `/rai-creative` and whose scope is bounded by existing detailed creative docs can run a "lighter route": skip `/rai-plan` (write the task file directly), skip `/rai-creative` (reference the predecessor's docs as the design source), and execute build phases inline rather than spawning the full sub-agent fan-out. Eligibility: prior creative docs are canonical for the new task, scope is bounded by existing detailed specs, design questions are all resolved. Anti-eligibility: novel architecture, ambiguous scope, contradicting prior creative work.

**Limits**: Level 3 tasks may extract 2–4 learnings. Four learnings extracted; all are genuinely reusable patterns that surfaced concretely in this task.

### Learned Rules Applied

- **`_learned/service-shape.md`**: Applied directly in Phase 0. The architecture doc's prescribed `Result = Struct.new(:normalized, :valid?, keyword_init: true)` follows this rule; the previous implementation (nil-or-String) diverged. Phase 0 brought the implementation back into compliance.
- **`_learned/gating-filter-passthrough.md`**: Applied via the existing cascade gating (TASK-008). Phase 3's system spec exercises the rule end-to-end: present-and-unverified Contact → dropped; present-and-verified → kept; the cascade preserves the verified contact's email post-identity.
- **`_learned/audit-trail.md`**: Applied in Phase 1. `handle_identity_update` writes `Contact.update! + FlowEvent.record!(event_type: "contact.verified")` inside a single `ActiveRecord::Base.transaction` block. Phase 3's system spec asserts the FlowEvent landed atomically.
- **`_learned/schema-validation.md`**: Not directly applicable to this task (no schema changes), but indirectly reinforced — TASK-009 leaned on TASK-008's schema (the `first_name`, `last_name`, `phone` columns added there) without re-validation, which was the right call given those columns shipped and were exercised by the active cascade gating.
- **`_learned/namespacing.md`**: Applied indirectly. `Contacts::PhoneNormalizer::Result` lives under the existing `Contacts::` namespace (plural, per the rule) so the nested struct doesn't collide with anything.

### For Claude Code Workflow

1. **Forward-debt resolution as Phase 0** is a reusable build pattern for continuation tasks. Codify the pattern in archive-time guidance: every "Forward Debt" archive section should name the consuming task's Phase 0 candidate.

2. **Lighter-route eligibility checks** for `/rai-build` would help future tasks decide whether to spawn the full sub-agent fan-out or run phases inline. A 30-second checklist at task-creation time (design questions resolved? scope bounded? prior creative docs canonical?) would let the right route be picked deliberately rather than by default.

3. **Cross-task creative-doc reuse** worked cleanly here because TASK-008's creative docs were detailed enough to be build-ready. The pattern of "deferring FE work, writing the UI/UX doc anyway, picking it up in a separate task" is a useful scope-management tool — particularly when a backend-frontend split makes sense for shipping cadence.

---

## Conclusion

TASK-009 closed FEAT-006 with all five acceptance criteria met, 22 new specs, and a green suite of 445/445 with global rubyfmt compliance. The lighter workflow (no fresh `/rai-creative`, inline build phases, Phase 0 forward-debt resolution before consuming code lands) was the right shape for a continuation task whose design questions were all resolved upstream. The four phase commits on `feature/FEAT-006-self-verification-fe` are reviewable phase-by-phase.

The most reusable patterns surfaced by this task are: (1) **forward-debt resolution as Phase 0** of a consuming task, before any other code consumes the diverged contract; (2) **lighter-route eligibility** for continuation tasks with already-resolved design questions; (3) **HTML-entity-agnostic error-text assertions** to avoid brittleness around Rails' default escaping; (4) **predicate-pair symmetry** when adding model predicates that have corresponding scopes.

The deferred-from-TASK-008 items (the four entries in TASK-008's Live-Dogfood-Pending Tracker) all landed in this task. No forward debt is being carried out of TASK-009 — the one minor item (missing direct unit spec for `Contact#unverified?`) is small enough to fold into a future small-fix task or address in a single-line spec addition during archive.

**Overall Task Success**: Full Success (all 5 ACs met, 0 deferred phases, 0 forward debt carried)

**Overall Workflow Effectiveness**: High (lighter route appropriate for task shape; phase-by-phase human gate respected; commits clean and bisect-friendly)

**Recommendation**: Ready to archive. No follow-up tasks blocked. The FEAT-006 feature is now backend + FE complete on `feature/FEAT-006-self-verification-fe` (this branch) plus the already-merged TASK-008 backend on `main`.
