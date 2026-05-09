# User Journey Design: Cc'd Contact Self-Verification

**Created**: 2026-05-09
**Status**: DECIDED
**Decision Type**: User Journey
**Task**: TASK-008 (FEAT-006)
**Resolves**: Q1 (Trigger), Q5 (Re-prompt cadence)

## Journey Overview

**Feature**: A newly-CC'd contact (promoted from a GM reply) is invited to self-serve their identity (first name, last name, phone) via a magic-link email so future submission prompts and escalations can address them confidently.

**Primary Persona**: The CC'd Contact — e.g., *Linda*, the marketing assistant the GM CC'd into a question email. She has never heard of Rogue. She has an inbox, an email signature, and zero appetite for "create an account" friction.

**Journey Type**: Asynchronous (push-triggered email → on-demand web form → silent background gating)

**Orchestration Pattern**: **Push trigger (mailer) → single-screen no-login form**, layered into the existing `Setup::WalkthroughsController` walkthrough as Step 1 of 4 — with a thin standalone access path for contacts who haven't been issued a Source yet (e.g., the GM CC'd them but the question turned out to be `:skip` on a sibling thread).

### Success Statement

> Linda gets one email titled "Confirm your details so [Dealership] can route data assignments to you", clicks a button, fills three fields on a single page, and is done — with zero passwords, zero account creation, and her next interaction with Rogue (the submission prompt) addresses her by first name on the right phone number.

## Persona Context

### Primary User: The CC'd Contact ("Linda")

- **Who**: Marketing-coordinator-or-equivalent at a dealership, or a vendor account manager. The GM CC'd her on the marketing-strategy question reply.
- **Goal**: Find out what the dealership wants from her, do the minimum to acknowledge it, and get back to her actual work.
- **Context**: Reading email between meetings on a desktop or phone. First-time contact with Rogue. Trust is fragile — anything that smells like a phishing-account-creation flow gets archived.
- **Proficiency**: Email-fluent. Web-form-fluent. Zero patience for SaaS onboarding rituals.
- **Mental model**: "Someone CC'd me — what do I need to do?" The GM has already implied "this is legit, just answer them" by CC'ing her in the original thread.

### Secondary User: The GM ("Rachel")

- **Who**: General Manager. Different journey: she's the *causal trigger*, not the recipient.
- **Different needs**: Rachel needs **visibility** that Linda's identity completion is in flight — but she does not want a new chore. The existing in-thread acknowledgment to Rachel ("Welcome Linda — we're walking her through setup") already covers this; verification adds nothing for Rachel at MVP.

### Tertiary user: Rogue ops staff

- **Who**: Anyone debugging "why didn't Linda get her prompt?" three weeks from now.
- **Different needs**: Wants the verification state visible in `flow_events` so they can answer "did Linda ever verify?" without admin tooling.

## Journey Map

### Entry Points

| Entry | Context | User Intent |
|-------|---------|-------------|
| **Setup email "Set up your assignment" button** | Linda's inbox, sent immediately after GM reply parse | "What do I need to do for Rachel?" |
| Resumed setup link in any later mail | Linda's inbox (a re-send or escalation that names her) | "I think I missed something" |
| (Out of MVP scope) Direct URL share | n/a | n/a |

### State Diagram (chosen flow)

```
[GM CC's Linda in onboarding reply]
    │
    ▼
[OnboardingMailbox#handle_assignment]
    │  Contact.find_or_create_for_email
    │  Responsibility.create!  Source.find_or_create_by!
    │
    ▼
[OnboardingMailer#invitee_setup_email — UNCHANGED entry]
    │  to: linda@dealer.com  signed_id (purpose: :invitee_setup, 7 days)
    │
    ▼
[Linda clicks "Set up your assignment"]
    │
    ▼
[Setup::WalkthroughsController#show step="identity"]   ← NEW first step
    │
    ├──[Linda submits first_name + last_name + phone]
    │     ▼
    │  [Setup::WalkthroughsController#update]
    │     PATCH writes to Contact; FlowEvent "contact.verified"
    │     ▼
    │  redirect → step="summary"   (existing Step 1 of 3, now Step 2 of 4)
    │     ▼
    │  [Step "method" — existing]
    │     ▼
    │  [Step "done" — existing]
    │
    └──[Linda submits with blank first_name]
          ▼
       [422; re-render :identity with inline errors]
          ▼
       [Linda corrects; resubmits]
```

Sub-decision: if Linda lands on `/setup/:signed_id` and her contact is **already verified**, the controller short-circuits straight past `:identity` to `:summary` (the existing template_for_step short-circuit pattern, extended).

### Step-by-Step Journey

#### Step 0: Trigger — GM CC promotes Linda

- **System**: `OnboardingMailbox#handle_assignment` → `Contact.find_or_create_for_email` → `OnboardingMailer.invitee_setup_email.deliver_later`.
- **Source files**: `app/mailboxes/onboarding_mailbox.rb:106-111,144-148`
- **No new mailer**. The trigger surface is the existing `invitee_setup_email`. The verification step is layered into the page that the existing email already points at.
- **Idempotency**: `find_or_create_for_email` is already idempotent on `(tenant_id, email_normalized)`. The setup email goes out once on first promotion; on re-promotion, the same Contact is returned and a new invitee_setup_email fires (same as today). Re-promotion does not double-email *for verification specifically* because there is no separate verification email.

#### Step 1: Linda opens the setup email

- **System**: Linda's mail client. The email body is the existing `invitee_setup_email` view, with one **copy edit**: subject and body now say "Set up your details and how you'll send data" instead of "data collection assignment", to set the expectation that she'll fill in her name + phone.
- **User Sees**:
  - Subject: `[Dealer Co Onboarding] Set up your details and how you'll send data`
  - Body: "Rachel at Dealer Co asked you to handle marketing strategy reporting. Click below to confirm a few details and pick how you'll send data."
  - Single button: "Set up your assignment".
- **User Actions**: Click button.
- **Feedback**: Browser navigates.
- **Transitions**: → Step 2.
- **Data Flow**: Magic link carries `Contact#invitee_setup_signed_id`, 7-day expiry, purpose `:invitee_setup` (UNCHANGED).

#### Step 2: Identity step (NEW — Step 1 of 4 in the walkthrough)

- **System**: `Setup::WalkthroughsController#show` with `step="identity"` (new) or default-step routing when `@contact.verified? == false`.
- **Source files**: `app/controllers/setup/walkthroughs_controller.rb` (extended).
- **User Sees**: A single-screen form with three fields:
  - **First name** (text)
  - **Last name** (text)
  - **Mobile phone** (tel) — small helper text: "We'll text you links to submit data on your cadence — you'll never get a marketing message."
  - Continue button.
  - Top-of-page reassurance: "No password, no account. Just three details so [Dealer Co] knows it's you."
- **User Actions**: Type, tab, click Continue.
- **Feedback**: On blank submit, inline field errors render via 422 + `render :identity`. On valid submit, redirect to `step=summary`.
- **Transitions**: PATCH success → `redirect_to setup_walkthrough_path(step: "summary")`. Failure → 422 re-render.
- **Data Flow**:
  - On valid submit: `Contact.update!(first_name:, last_name:, phone:)` inside a transaction with `FlowEvent.record!(event_type: "contact.verified", subject: contact, payload: {via: "setup_walkthrough"})`.
  - The form POST goes to the same `Setup::WalkthroughsController#update` endpoint, branched on params shape (`params[:contact]` vs `params[:source][:submission_method]`).

#### Step 3-5: Existing summary / method / done

- **Unchanged**, except `summary.html.erb` step counter is bumped from "Step 1 of 3" to "Step 2 of 4" and similarly for method (3 of 4) and done (4 of 4).
- The `done` template now greets Linda by first name: "You're set up, Linda."

#### Step N: Success

- **User Sees**: `done.html.erb`, "You're set up, Linda. We'll prompt you to submit your first marketing strategy report on June 30."
- **Value Delivered**: Future submission-prompt and escalation emails address her by first name and (eventually) reach her by SMS on the verified phone.
- **Next Actions**: "You can close this tab." Same as today. No portal entry.

### What about contacts who land WITHOUT a Source/Responsibility yet?

The current `Setup::WalkthroughsController` short-circuits to a generic message when `@responsibility` is nil. With this change, if `@contact.verified? == false` and there is no responsibility, the controller **still shows the identity step** (because verification is contact-scoped, not source-scoped). After submission, redirect to a "Thanks — we'll be in touch" terminal page (re-uses the `summary.html.erb` no-responsibility branch).

This is the rare-but-possible edge case where the GM CC'd Linda into a question that the GM then re-routed by replying again (superseding the responsibility). Linda still got the setup email; she should still be able to verify. The journey degrades gracefully.

## Async Handling

### Operation Lifecycle

| Phase | Duration | User Experience |
|-------|----------|-----------------|
| Trigger (GM reply parse → setup email) | < 30s typical (Solid Queue) | Linda receives an email "shortly after Rachel CC'd her" — synchronous from her POV |
| Identity step click-through | Linda's choice | She clicks when ready; link is valid 7 days |
| Form submit → verified | Synchronous, <500ms | Inline form redirect to next walkthrough step |
| Downstream (gating effects) | Immediate | Subsequent submission prompts now feature `Hi Linda,` and SMS (when wired) goes to her number |

### Progress Communication

- **Method**: Email (push) for trigger; web form (sync) for completion. No polling, no websocket, no in-app notifications. This matches Rogue's email-first DNA.
- **Frequency**: One trigger email. **No re-prompt at MVP** (see Q5 decision below).
- **Persistence**: `flow_events` carries `contact.verified` (and, if Q5 escalates: `contact.verification_unfinished` for ops queries). The `Contact` row is the durable state.

## Distributed System Flow

### System Boundaries

```
[GM Mail Client] ──reply──▶ [Action Mailbox] ──▶ [OnboardingMailbox]
                                                       │
                                                       ▼
                                    [OnboardingReplyParser]
                                                       │
                                                       ▼
                       [Contact.find_or_create_for_email] (no event)
                                                       │
                                                       ▼
                            [OnboardingMailer.invitee_setup_email]
                                                       │
                       (deliver_later → Solid Queue → SMTP)
                                                       │
                                                       ▼
                                          [Linda's Inbox]
                                                       │
                                       click magic link
                                                       │
                                                       ▼
                       [Setup::WalkthroughsController]
                          show :identity (NEW)
                          update → Contact.update! + FlowEvent
                                                       │
                                                       ▼
                          show :summary → :method → :done
```

### Responsibility Matrix

| Step | Owner | State Storage | Failure Handling |
|------|-------|---------------|------------------|
| Setup email dispatch | OnboardingMailbox + Solid Queue | n/a (idempotent on Contact) | Solid Queue retries; re-promotion sends a fresh setup email |
| Identity form GET | Setup::WalkthroughsController | none (read from Contact) | `find_by_invitee_setup_signed_id` returns nil on tamper/expiry → render `:expired` |
| Identity form POST | Setup::WalkthroughsController | Contact + FlowEvent (same txn) | 422 + `:identity` re-render with inline errors |
| Subsequent prompts | SubmissionPromptSenderJob (FEAT-002+) | reads Contact.verified? | Architecture agent's gating decision (Q2) determines pause/no-pause |

## Error Handling

### Error States

| Error Type | When | User Sees | Recovery |
|------------|------|-----------|----------|
| Validation (blank first/last/phone) | Linda submits empty | Inline field error, "First name can't be blank" | Fix and resubmit; same form |
| Invalid phone format | Architecture agent decides validation flavor | Inline "Please enter a valid mobile number" | Fix and resubmit |
| Expired signed_id | Linda clicks 8 days later | `:expired` page with "Reply to Rachel's last email and we'll resend you a fresh link." | She replies; GM forwards; she gets a fresh setup email (manual process at MVP — same as today's invitee setup expiry behavior) |
| Tampered signed_id | Adversary substitutes another contact's signed_id | `:expired` page (HTTP 404, no enumeration) | Same as expired — no information leakage |
| Server error during submit | Rare | Browser sees 500 page (Rails default at MVP); Contact unchanged | Linda refreshes; her form is empty but she retries |

### Partial Failure

- **Scenario**: Linda submits her identity, then closes the tab before reaching `:method`.
- **User Experience**: She is verified. Her next click on the same magic link lands directly on `:method` (because `@contact.verified?` short-circuits past `:identity`).
- **Recovery**: None needed; the verification work product is independent of the submission-method choice.

- **Scenario**: Linda fills `:method` first (e.g., a stale tab from someone else's session — vanishingly rare given signed_id), then comes back later and verifies.
- **User Experience**: Both states coexist. The walkthrough shows `:done` once the source is configured AND identity is filled. If only one is done, the controller routes her to whichever is missing. (Implementation detail: `template_for_step` extends to also short-circuit on `@contact.verified?`.)

## Options Explored

### Option A: Dedicated verification email, sent immediately on contact promotion

- **Orchestration**: New mailer action (`OnboardingMailer#contact_verification_email` or new `ContactVerificationMailer`). New controller (`Contacts::VerificationsController`). New route (`/contacts/:signed_id/verify`). New signed_id purpose (`:contact_verification`).
- **Trigger**: From `OnboardingMailbox#handle_assignment` immediately after `Contact.find_or_create_for_email`, *in addition to* `invitee_setup_email`.
- **Flow Summary**: Linda receives **two** emails within seconds of each other: "Confirm your details" + "Set up your assignment."
- **Wireframe (email)**:
  ```
  ┌───────────────────────────────────────────────────────┐
  │ Subject: Quick details for Dealer Co's data routing    │
  │                                                        │
  │ Rachel just CC'd you about marketing strategy data.    │
  │ Before we finish setup, can you confirm three things?  │
  │                                                        │
  │      [ Confirm my details (30 seconds) ]               │
  └───────────────────────────────────────────────────────┘
  ```
- **Pros**:
  - Identity is decoupled from source setup — Linda can verify without committing to a submission method.
  - Verification works for the rare edge case of "GM mentions Linda in a thread but the responsibility is then superseded" — a dedicated email still reaches her.
  - Easy to A/B test verification copy independently of setup copy.
- **Cons**:
  - **Two emails for the same person about the same thing**, sent within seconds. High annoyance. Cognitive load: "Wait, which one do I click first?"
  - Linda is a first-time contact. *Two* unfamiliar magic-link emails make this look like a phishing volley.
  - Doubles the mailer surface area (new mailer, new controller, new route, new view set, new signed_id purpose, new spec files).
  - Re-sending the setup email on responsibility supersede is already a known case (`OnboardingMailbox` re-promotion); now we'd also have to make the verification email idempotent on its own axis. Two axes of idempotency, twice the bugs.
- **Best For**: A world where Rogue had a portal Linda would log into. Then "verify your account" makes sense as a standalone action. Rogue does not have such a portal.
- **Friction Points**: First-time contact, two magic-link emails, dealer's IT spam filter eats one of them, Linda thinks the surviving one is suspicious.

### Option B: Inline prompt layered into the existing setup walkthrough

- **Orchestration**: No new email. No new controller. Add an `:identity` step to `Setup::WalkthroughsController` BEFORE the existing `:summary` step. The setup email's button still goes to `/setup/:signed_id`; the page she lands on now starts with three identity fields.
- **Flow Summary**: Linda receives the existing `invitee_setup_email`, clicks "Set up your assignment", lands on Step 1 of 4 (identity), submits, advances through steps 2-4 (summary, method, done) as today.
- **Wireframe (page 1)**:
  ```
  ┌─────────────────────────────────────┐
  │  Step 1 of 4 — Your details         │
  ├─────────────────────────────────────┤
  │  No password, no account. Just      │
  │  three details so [Dealer Co]      │
  │  knows it's you.                    │
  │                                     │
  │  First name   [_________________]   │
  │  Last name    [_________________]   │
  │  Mobile phone [_________________]   │
  │                                     │
  │            [ Continue ]             │
  └─────────────────────────────────────┘
  ```
- **Pros**:
  - **One email, one click, one flow**. Linda's mental model stays simple: "Rachel CC'd me → click → done."
  - Reuses *every* piece of infrastructure already in place: signed_id (`:invitee_setup`), controller, expired view, route. **Zero net-new surfaces** outside the new view + controller branch.
  - Naturally idempotent: if Linda hits the page after verifying, the controller short-circuits past `:identity`. No "did the verification email already fire" bookkeeping needed.
  - Verification is *sequenced before* method-picker, which is the right order: the GM nominated her as a person; that personhood is filled in before she configures how she'll send data.
  - Setup-walkthrough completion rate becomes a single funnel metric — fewer KPIs to monitor.
- **Cons**:
  - The setup email subject line must change ("Set up your details and how you'll send data" instead of "data collection assignment") — a copy migration but minor.
  - Linda's three identity fields are gated behind the same expiry as her setup link (7 days). If she ignores both, both expire together. (Acceptable: the same person was going to ignore both anyway.)
  - The rare edge case where Linda is mentioned but loses her active responsibility means her setup link still works, but the page below `:identity` shows a "no active assignment" branch. Adequate but lukewarm UX. Mitigation: the `summary.html.erb` already handles this branch.
- **Best For**: An email-first product where the contact has exactly one entry-point and zero other touch surfaces. Rogue.
- **Friction Points**: One — Linda gets the setup email, sees a longer form than she expected (4 steps not 3). Mitigated by the explicit "Step 1 of 4" counter and the reassuring copy.

### Option C: Hybrid — setup email first, then a chase-up verification email after N days

- **Orchestration**: Option B's inline path is the primary. If Linda goes silent for N days *without* verifying, a recurring `ContactVerificationReminderJob` (modeled on `EscalationDetectorJob`) sends a reminder mail.
- **Flow Summary**: Same as Option B for the happy path. Adds a reminder ladder for the unhappy path.
- **Pros**:
  - Catches the "ignored the email" case without requiring a brand-new dedicated trigger.
  - Reuses the inline form path; the reminder is just another vector to the same `/setup/:signed_id`.
- **Cons**:
  - Adds an entire new job + scheduling decision (frequency, max retries, escalation to GM). This is most of the cost of Option D's entire feature.
  - Re-sending magic-link emails to people who haven't engaged with Rogue is a deliverability risk — repeated unread mails to a fresh address train spam filters.
  - The product hasn't yet established whether unverified contacts are *blocked* from anything. If they're not (Q2 candidate D), the reminder serves no business purpose.
- **Best For**: A future iteration where we have data on actual verification rates and a confirmed gating policy.
- **Friction Points**: Reminder emails feel like nagging if the gating is soft. If the gating is hard (suppressed prompts), the reminder is *necessary* — but then Q2 has already pre-decided we need this.

### Option D: Defer (no verification, ship gating only)

- **Orchestration**: Skip the entire feature; only the gating side ships.
- **Pros**: Fastest to delivery.
- **Cons**: This is the spec for TASK-008. Skipping it = canceling the task. Not a real option, listed for completeness.

## Evaluation Matrix

| Criterion | Option A (Dedicated email) | Option B (Inline) | Option C (Hybrid) |
|-----------|----------|----------|----------|
| Discoverability | M (two emails compete) | H (one email, one path) | H |
| Learnability | M (two flows) | H (one flow, sequenced) | H |
| Efficiency (clicks) | L (extra email + click) | H | H |
| Error Prevention | M | H (sequenced before method) | H |
| Error Recovery | M | H | H |
| Consistency w/ existing patterns | L (new mailer + controller) | H (extends existing) | M (extends existing + new job) |
| Accessibility | M | H (single sub-page form, plain HTML) | H |
| Build cost | High (new mailer + controller + route + signed_id purpose) | Low (one new step, one new view) | Medium-High |
| Email-first ethos | M (more emails) | H (fewer emails) | M |
| Idempotency complexity | High (two axes) | Low (one axis: verified? predicate) | Medium |

## Decision

### Q1 — Trigger

**Chosen**: **Option B — Inline prompt layered into the existing setup walkthrough.**

#### Rationale

Rogue's "people providing data should never need an account" directive (productBrief) and the existing `Setup::WalkthroughsController` together make this a near-trivial choice. Linda is *already* receiving the `invitee_setup_email`; *already* clicking through to a magic-link no-login walkthrough; *already* in a 3-step UI that has explicit step-of-N counters. Adding identity capture as Step 1 of 4 reuses every piece of infrastructure already in place — the signed_id purpose (`:invitee_setup`), the controller, the expired view, the route — and avoids the cardinal sin of email-first products: sending two unfamiliar magic-link emails to a first-time contact within seconds of each other. The sequencing is also semantically right: the GM nominated Linda as a *person*; her personhood is filled in before she configures *how* her data flows. Idempotency falls out of the existing `verified?` predicate (the controller short-circuits past `:identity` on subsequent visits) without needing to track "was a verification email already sent?" — a class of bug that Option A introduces.

### Q5 — Re-prompt cadence

**Chosen**: **Option D — No re-prompt at MVP.**

#### Rationale

Three reinforcing reasons. (1) **The trigger doesn't expire on its own clock**: the verification surface piggybacks on `invitee_setup_signed_id` (7-day expiry). When that expires, Linda's setup *as a whole* is in limbo, not specifically her verification — the cure is the same forward-pressure mechanism the platform already has (the GM resending or re-CC-ing, which produces a fresh setup email by way of `find_or_create_for_email` returning the existing Contact + dispatching a fresh `invitee_setup_email`). Layering a separate verification reminder on top of that is double-reminding. (2) **The cost-of-being-wrong is small at MVP**: an unverified contact still has an email address; submission prompts can still address them as "Hi there" (or with `display_name` if present); SMS is not yet wired so the missing phone doesn't currently break anything. The escalation cascade exists and will eventually surface `gm_nudge` to Rachel if Linda never engages — **the GM-nudge IS the implicit Q5 escalation** (Architecture agent should verify this). (3) **Reminder emails to disengaged first-time contacts are a deliverability footgun**: training the dealer's spam filter that "we send repeated magic-link emails to people who don't click" is the wrong long-term posture. Reach for this only when we have data showing a real verification gap.

If post-launch metrics show >X% of CC'd contacts never verifying, Phase 5 (a `ContactVerificationReminderJob` modeled on `EscalationDetectorJob`) becomes a focused follow-up — but the cascade infrastructure is already proven, so deferring costs us nothing later.

### Trade-offs Accepted

- **Setup email subject changes**: minor copy migration. The new subject must communicate that filling in identity is part of the click-through. Mitigation: UI/UX agent owns the copy in the next phase.
- **Linda's identity fate is tied to her setup-link expiry**: 7 days. If she sleeps on it, both expire together. Acceptable: the same person was going to sleep on a separate verification email too.
- **No automatic GM visibility into "Linda hasn't verified yet"**: the existing escalation cascade catches the symptom (no submission), not the cause (no identity). Acceptable until live-dogfood shows otherwise.

## Implementation Guidelines

### Backend Requirements

#### 1. `OnboardingMailbox` — **NO new code path needed**

The existing trigger (`OnboardingMailer.invitee_setup_email.deliver_later` at `app/mailboxes/onboarding_mailbox.rb:144-148`) is the right entry point. The setup email already carries the magic link. No mailbox changes for trigger; the only mailbox-adjacent change is upstream: the mailer's subject and body copy (UI/UX agent's responsibility).

**One small backend addition recommended**: emit a `contact.invited_for_setup` FlowEvent inside `handle_assignment` when a *new* Contact is created (vs. found existing). This event is the audit trail anchor for "did Linda ever get her invitation?" — independent of whether the email actually delivered. This is a one-line addition next to the existing `responsibility.created` event emit.

#### 2. `OnboardingMailer#invitee_setup_email`

- **Subject change**: from `"#{tenant.dealership_name}: data collection assignment"` to `"#{tenant.dealership_name}: set up your details and how you'll send data"` (final wording per UI/UX agent).
- **Body change**: the current body says "data collection assignment"; needs a one-line addition naming the three details Linda will fill (per UI/UX agent).
- **No new mailer action.**

#### 3. `Setup::WalkthroughsController`

- Add `:identity` to the step routing in `template_for_step`. Logic:
  - If `@contact.first_name.blank? || @contact.last_name.blank? || @contact.phone.blank?` AND `step != "method"` AND `step != "done"`, render `:identity`.
  - The `step="method"` and `step="done"` short-circuits remain (allows resuming).
  - On `step="done"` with `@source.submission_method.present?`, render `done` regardless (post-completion access).
- Branch the `update` action on params shape:
  - `params[:contact]` present → handle identity submission: `@contact.update(contact_identity_params)` inside a transaction with `FlowEvent.record!(event_type: "contact.verified", subject: @contact)`. On success: `redirect_to setup_walkthrough_path(signed_id: ..., step: "summary")`. On failure: `render :identity, status: :unprocessable_entity`.
  - `params[:source]` present → existing source-completion path (unchanged).

#### 4. `Contact` model

- New columns per Architecture agent's Q3 schema decision (Architecture-led; this journey assumes columns named `first_name`, `last_name`, `phone` for narrative purposes).
- Predicate: `Contact#verified?` returns `[first_name, last_name, phone].all?(&:present?)`.
- Strong params helper or form object to whitelist `:first_name, :last_name, :phone`. Phone validation per Architecture agent's Q4 decision.

#### 5. View files

- **NEW**: `app/views/setup/walkthroughs/identity.html.erb` — single-screen form, three fields, post to `setup_walkthrough_path(signed_id:)` with `local: true`, scope `:contact`. Tailwind styling per UI/UX agent.
- **EDIT**: `summary.html.erb`, `method_picker.html.erb`, `done.html.erb` — bump step counters from "Step 1/2/3 of 3" to "Step 2/3/4 of 4". `done.html.erb` adds first-name greeting.
- **NEW**: empty-responsibility branch in `identity.html.erb` to handle the "verified but no active assignment yet" terminal copy.

#### 6. FlowEvent taxonomy additions

| New event_type | Subject | Payload | When |
|---|---|---|---|
| `contact.invited_for_setup` | Contact | `{responsibility_id, via: "onboarding_mailbox"}` | When a *new* Contact is created in `handle_assignment` (recommended optional addition for audit trail) |
| `contact.verified` | Contact | `{first_name_present: true, last_name_present: true, phone_present: true, via: "setup_walkthrough"}` | When Linda's PATCH succeeds and all three fields go from blank to filled |

These slot cleanly into the existing taxonomy (`tenant.*`, `question.*`, `reply.*`, `responsibility.*`, `vendor.*`, `source.*`, `submission.*`, `escalation.*`, `digest.*`). The new prefix `contact.*` is consistent with the noun-verb pattern.

**No `contact.verification_invited` event** is needed because there is no separate verification trigger. `contact.invited_for_setup` and `contact.verified` together tell the story.

#### 7. No new jobs

Q5 → Option D. No `ContactVerificationReminderJob`. The escalation cascade already handles the downstream (silence → eventual GM nudge). If Phase 5 gets re-scoped post-launch, the precedent is `EscalationDetectorJob` — same pattern, separate phase.

### Integration Points

| System | Interface | Data Exchanged |
|--------|-----------|----------------|
| Action Mailbox | unchanged | inbound CC reply |
| OnboardingMailbox | unchanged trigger | calls `OnboardingMailer.invitee_setup_email` (existing line) |
| OnboardingMailer | content edit only | new copy in `invitee_setup_email` view |
| Setup::WalkthroughsController | extended | new `:identity` step + branched `update` |
| Contact model | new columns + predicate | `Architecture-Q3` |
| FlowEvent | new event_types | `contact.verified` (+ optional `contact.invited_for_setup`) |
| EscalationCascade | (unchanged at this phase) | reads `Contact#verified?` only if Q2 chooses gating candidate A or B |

## Cross-Dependencies for Sibling Agents

### For the Architecture Design agent

- **Q2 (gating)**: This journey makes Q2 candidate A (suppress fanout) and B (suppress submission prompts) **harder to justify at MVP** because we have no re-prompt cadence to break the deadlock — gating + no-reminder = limbo. Recommend Architecture agent leans toward **candidate D (visual flag in admin views) + candidate C (`:pending_verification` digest status)**, both of which are non-blocking. If Architecture *does* pick A or B, that retroactively makes Q5 Option D a problem and we may need to revisit Phase 5.
- **Q3 (schema)**: This journey assumes column names `first_name`, `last_name`, `phone` for narrative purposes only. The journey is invariant under schema choice as long as `Contact#verified?` exists.
- **Q4 (phone validation)**: The form copy says "Mobile phone — we'll text you links." The form validation level (free-form, E.164, or hybrid) is owned by Architecture but should match this user-facing promise.

### For the UI/UX Design agent

- **Email subject + body copy** for the modified `invitee_setup_email`. Must communicate "fill in your details + pick a submission method" in one breath.
- **Identity form layout** — three fields, single screen, Tailwind, mobile-first (Linda is on her phone).
- **Step counter convention** — "Step 1 of 4" through "Step 4 of 4". Reaffirms a finite, short journey.
- **Reassurance copy** at the top of the identity form explaining no-account-no-password.
- **Empty-responsibility terminal page** copy for the rare "verified but no active assignment" landing.

### For the Build agent (downstream)

- **No new mailer.** Resist the temptation to spin up `ContactVerificationMailer`.
- **No new controller.** Extend `Setup::WalkthroughsController`.
- **No new route.** `/setup/:signed_id?step=identity` is the surface.
- **No new signed_id purpose.** `Contact#invitee_setup_signed_id` is the only token.
- **Idempotency comes for free** from `Contact#verified?` short-circuiting in `template_for_step`.

## Acceptance Criteria

### AC-ENTRY-1: Linda finds the verification entry from the existing setup email

**Priority**: MUST

**Given** Rachel (the GM) has CC'd Linda on a question reply that was parsed as `:assign`, and `OnboardingMailbox#handle_assignment` has dispatched the existing `invitee_setup_email` to Linda's address
**When** Linda opens the email and clicks "Set up your assignment"
**Then** she lands on `/setup/:signed_id` and sees the identity form (Step 1 of 4) with three labeled fields: First name, Last name, Mobile phone

**Verification**:
- [ ] System spec: GM CC reply → Action Mailbox → ActionMailer outbox contains `invitee_setup_email` to Linda's address
- [ ] System spec: clicking the magic link visits the controller and renders `:identity`
- [ ] Request spec: `GET /setup/:signed_id` for an unverified contact returns the identity template

### AC-HAPPY-1: Linda completes verification and proceeds through setup

**Priority**: MUST

**Given** Linda is on `/setup/:signed_id` with `@contact.verified? == false`
**When** she:
  1. Types "Linda" in First name
  2. Types "Sanchez" in Last name
  3. Types "+1 555 010 1234" in Mobile phone
  4. Clicks Continue
**Then**:
  - The `Contact` row updates with first_name="Linda", last_name="Sanchez", phone normalized per Architecture-Q4
  - A `FlowEvent` row is written with `event_type="contact.verified"`, `subject_id=contact.id`, `subject_type="Contact"`, in the same DB transaction
  - The browser redirects to `/setup/:signed_id?step=summary`
  - From there, the existing summary → method → done flow proceeds unchanged

**Verification**:
- [ ] Request spec: PATCH with valid params writes contact + flow_event + redirects
- [ ] System spec: full happy-path from email click to `:done` greeting Linda by first name

### AC-HAPPY-2: Idempotent re-entry on a second click

**Priority**: MUST

**Given** Linda has already verified
**When** she clicks the same magic link again
**Then** she sees `:summary` (or the next incomplete step), NOT `:identity`. Her stored fields are unchanged.

**Verification**:
- [ ] Request spec: GET `/setup/:signed_id` for a verified contact renders summary (or method or done depending on source state)

### AC-ERROR-1: Inline validation when a field is blank

**Priority**: MUST

**Given** Linda is on the identity step
**When** she submits with blank first_name (or last_name, or phone)
**Then**:
  - HTTP 422
  - The same `:identity` template re-renders
  - An inline error appears next to the offending field ("First name can't be blank")
  - The Contact is NOT updated; no FlowEvent is written
  - Her other typed values are preserved

**Verification**:
- [ ] Request spec: PATCH with blank first_name returns 422 and the form re-renders
- [ ] Request spec: no `contact.verified` flow_event is created on validation failure

### AC-ERROR-2: Tampered or expired signed_id

**Priority**: MUST

**Given** an attacker substitutes `:signed_id` with garbage (or 8 days have passed)
**When** the controller is hit
**Then** the `:expired` template renders with HTTP 404, no information about whether the contact exists, no Contact mutation

**Verification**:
- [ ] Request spec: tampered signed_id renders `:expired` 404
- [ ] Request spec: expired signed_id renders `:expired` 404

### AC-INTEGRATION-1: Verification gates downstream behavior per Architecture-Q2

**Priority**: MUST (subject to Architecture decision)

**Given** the gating candidates Architecture selects (this journey recommends C + D)
**When** Linda has not yet verified
**Then** the digest assembler reflects `:pending_verification` status for her responsibilities, and admin views flag her row visually

*Specific verification owned by Architecture's gating decision.*

## Test Scenarios

### Happy Path Tests

1. **AC-ENTRY-1**: System test — GM CC reply triggers setup email; clicking link lands on identity form
2. **AC-HAPPY-1**: System test — full flow from email click to `:done` template, including FlowEvent emit
3. **AC-HAPPY-2**: Request test — verified contact short-circuits past `:identity`

### Error Tests

1. **AC-ERROR-1**: Request test — each blank field returns 422 with field-level error
2. **AC-ERROR-2**: Request test — tamper and expiry both render `:expired` 404

### Edge Case Tests

1. **No active responsibility**: verified contact with no Responsibility lands on a terminal "thanks" page
2. **Re-promotion idempotency**: GM re-CC's Linda; the `find_or_create_for_email` returns the existing contact; a fresh `invitee_setup_email` fires; her existing identity remains intact

## Accessibility Checklist

- [ ] Single-screen form has labeled inputs (`<label for>`)
- [ ] Phone input uses `type="tel" inputmode="tel"` for mobile keyboard
- [ ] Validation errors associated with inputs via `aria-describedby` or proximity
- [ ] Focus moves to first error on 422
- [ ] No JS required to complete the flow (matches the existing walkthrough's no-Stimulus posture at MVP)
- [ ] Form is keyboard-navigable (Tab through inputs, Enter to submit)
- [ ] Color is not the only error signal (text + iconography per UI/UX)

## Analytics & Observability

### Key Metrics

| Metric | Source | Target |
|--------|--------|--------|
| Setup email click-through rate | (mail provider analytics, future) | > 70% within 7 days |
| Identity completion rate | `flow_events WHERE event_type='contact.verified'` ÷ contacts created | > 80% within 7 days |
| Step-1-to-step-2 drop-off | session-correlated FlowEvents | < 10% |
| Time from CC to verified | `flow_events.contact.verified.occurred_at` − `flow_events.responsibility.created.occurred_at` | < 24h median |

### Instrumentation Points

- **`contact.verified`** FlowEvent: emitted in PATCH txn. Payload includes `via: "setup_walkthrough"` so future SMS or admin-overrided verification paths can be distinguished.
- **`contact.invited_for_setup`** FlowEvent (recommended): emitted on new-contact create in mailbox. Payload includes responsibility id + tenant question id for funnel analysis.

## Validation Checklist

- [x] Journey delivers stated value (Linda's identity captured before her first prompt)
- [x] Primary persona can complete journey on a phone (Linda's likely device)
- [x] Errors are recoverable (422 with inline messages, identity step re-tries)
- [x] Async states are clear (none — the user-facing surface is synchronous)
- [x] Consistent with existing patterns (extends `Setup::WalkthroughsController`, no new top-level surfaces)
- [x] Accessible per requirements (no-JS form, labeled inputs, keyboard-navigable)
- [x] Testable with defined scenarios (5 ACs, all mappable to existing spec patterns)

## Next Steps

1. **Architecture agent finishes Q2/Q3/Q4** — schema and gating must land before Phase 1 can proceed.
2. **UI/UX agent owns**: identity form Tailwind layout, modified `invitee_setup_email` copy (subject + body), step counter convention, terminal-page copy for the "verified-but-no-responsibility" branch.
3. **Build agent (Phase 1)**: schema migration + `Contact#verified?` predicate.
4. **Build agent (Phase 2)**: extend `Setup::WalkthroughsController` with `:identity` step + branched `update`. New `identity.html.erb`. Step-counter edits in three existing views.
5. **Build agent (Phase 3 trigger integration)**: add the optional `contact.invited_for_setup` FlowEvent emit in `OnboardingMailbox#handle_assignment` for the new-contact branch. Subject/body copy edit on `invitee_setup_email`.
6. **Phase 5 (re-prompt cadence)**: **OUT OF SCOPE** for this build. Will be revisited if post-launch verification rates indicate a gap.

---

USER JOURNEY CREATIVE COMPLETE
Document: memory-bank/creative/TASK-008-user-journey.md
Journey: GM CC reply → existing setup email → /setup/:signed_id?step=identity → first/last/phone form → existing summary → method → done
Pattern: Push-trigger (mailer) + single-screen no-login form, layered into the existing setup walkthrough as Step 1 of 4
