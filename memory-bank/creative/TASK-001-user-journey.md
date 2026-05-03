# User Journey Design: TASK-001 — Tenant + GM Email-First Onboarding

**Created**: 2026-05-03
**Status**: DECIDED
**Decision Type**: User Journey
**Task**: TASK-001 (FEAT-001)

## Journey Overview

**Feature**: End-to-end email-first onboarding for a new dealer rooftop — Tenant seed (Rogue Staff) → single-click confirm (GM) → paced question/reply loop (GM) → invitee setup (Invited Contact) → recurring weekly digest (GM).

**Primary Persona**: Dealership GM. Saturated with apps, fluent in email, time-poor. Productivity ceiling is "what fits in the inbox they're already reading at 7:15am between sales meetings."

**Secondary Personas**:
- **Rogue Staff** — at MVP, a small ops crew (≤5 people, includes non-engineer founders). Needs the seed action to be a real URL they can use without shell access, but not exposed publicly.
- **Invited Contact** — internal staff or vendor user, lower-trust than the GM, web-walked.

**Journey Type**: Hybrid — synchronous web touches at the bookends (admin form, single-click confirm, web walkthrough) bracket a long-running asynchronous email conversation that can span days to weeks.

**Orchestration Pattern**: **Asynchronous email thread with sync web edges** — the email thread is the system of record for the GM's onboarding decisions; web surfaces exist only to (a) seed the Tenant, (b) take a single confirm click, (c) walk an invitee through submission setup, (d) drill into a digest.

### Success Statement

> Rogue Staff submits three fields on a form; the GM clicks one link from their inbox; over the following days, the GM answers paced one-question emails by replying with the right people on CC; each invitee gets walked through setup on the web; the GM gets a weekly accountability digest in their inbox without ever logging in.

---

## Scope of This Document

This document resolves the five LOW/MEDIUM-confidence user-journey questions flagged in the Specification:

- **J1** — Tenant seed surface (Rogue Staff)
- **J2** — First-question delivery delay after confirm (GM)
- **J3** — Question pacing scheduler (GM, ongoing)
- **J4** — Empty-state weekly digest behavior (GM, ongoing)
- **J5** — Resend-link UX for expired tokens

The remaining LOW-confidence items (Action Mailbox addressing scheme, Reply parser algorithm, Question Catalog data model, Vendor roster seed, In-thread ack subject discipline) are out of scope for this document and resolved in `TASK-001-architecture.md` and `TASK-001-algorithm.md`.

---

## J1. Tenant seed surface (Rogue Staff persona)

### Context

Rogue Staff at MVP is a tiny ops crew — likely the founding team plus one or two early ops hires, possibly including non-engineer founders who do not have shell access to a production console. The Spec proposes `/admin/tenants/new` (Hotwire form, three fields, HTTP basic auth, env-driven allowlist) as the default; rake task as a fallback for tests/scripts.

The question this resolves: is the controller-as-default the right primary surface, or should it be rake-only (engineer ops), or both side by side?

The constraints that matter most here:

- **Friction-minimization for Rogue Staff** — this is the only manual step on Rogue's side per productBrief. Three fields, one button. Repeating the seed is the ops team's most-frequent action in the product's first 6 months.
- **Email-first ethos doesn't apply to Rogue Staff** — the email-first ethos is about *GM* time, not internal ops. Rogue Staff using a web form is fine; the productBrief is silent on the internal surface.
- **Misuse/leak risk** — `/admin/tenants/new` is a real URL. If basic auth is the only gate and credentials leak, the failure mode is creating spam Tenants and emailing strangers. Rate-limiting and visibility controls matter more than they would for a rake task.
- **Testability** — system tests can drive a controller with Capybara. They cannot drive a rake task without shelling out.
- **Evolution** — when Rogue ops grows past 3 people, the surface needs to upgrade to a proper SSO-gated internal admin without a rewrite of the seed flow itself.

### Options

#### Option A: Controller only (`/admin/tenants/new`, basic auth, env allowlist)
- **Pros**:
  - Real URL the non-engineer ops team can use without shell access.
  - Drivable by Capybara system tests.
  - Natural evolution path: swap basic auth → internal SSO → keep the controller, change the auth concern.
  - Audit-able: every seed produces a controller log line with the basic-auth username, IP, and timestamp.
- **Cons**:
  - Public URL surface, even if locked. Credentials must be rotated when ops people leave.
  - Tests need to set up basic-auth headers (minor ceremony).
- **Friction**: lowest for the actual user. Three fields, submit, done.

#### Option B: Rake task only (`bin/rails rogue:tenants:seed[name,gm_name,gm_email]`)
- **Pros**:
  - No public URL surface to lock down.
  - Trivially scripted from CI/CD or a deploy hook.
  - Auth is "do you have shell access to production" which is already gated by hosting infra.
- **Cons**:
  - **Excludes non-engineer ops** — a founder who can't run rake on prod is shut out of the only manual operational step. This is a real failure mode given the Spec's persona description.
  - Bracketed args in rake tasks are notoriously fragile (commas in dealership names break the call; `'Smith, Toyota of Austin'` requires careful quoting).
  - System tests cannot drive it; we'd lose the "click-through-the-form" assertion that catches the most regressions.
- **Friction**: high for non-engineers; low for engineers but with the bracket-arg quoting trap.

#### Option C: Both (controller as primary, rake as fallback for tests/scripts)
- **Pros**:
  - All the wins of A.
  - Rake remains available as a scriptable surface for fixtures, integration test setup, and emergency manual seeding when the web auth is broken.
  - System tests can use the controller (for happy-path coverage) and the rake task (for fast non-system seeding in unit/integration tests).
- **Cons**:
  - Two code paths to keep in sync. Mitigation: rake delegates to the same `Tenant::Seeder` service that the controller calls. Both surfaces exercise one piece of business logic.
- **Friction**: same as A for the user; engineers get a scriptable extra.

#### Option D: Minimal Hotwire form on a non-admin route gated by allowlist (e.g., `/_seed`)
- **Pros**:
  - Slightly obscure URL.
  - Same Hotwire experience.
- **Cons**:
  - Security through obscurity is not security. Once a real ops team exists, they'll all share the URL anyway.
  - No upgrade path to proper SSO without re-namespacing the route.
  - No clear pattern for "this route is internal-only."
- **Friction**: same as A for the user; worse for ops culture (no clear boundary between "public" and "internal" surfaces).

### Evaluation

| Criterion | Opt A (controller) | Opt B (rake) | Opt C (both) | Opt D (obscure) |
|-----------|---|---|---|---|
| Accessible to non-engineer ops | High | None | High | High |
| Misuse risk | Low (basic auth) | None | Low | Medium (no clear boundary) |
| Testability | High | Low | High | Medium |
| Evolution path | Clear (swap auth) | None on web | Clear | Muddled |
| Implementation cost | Low | Lowest | Low+ | Low |

### Decision

**Chosen**: **Option C — Controller as primary, rake task as fallback.**

- **Primary surface**: `/admin/tenants/new` Hotwire form, gated by `http_basic_authenticate_with` against `ROGUE_ADMIN_USERNAME` / `ROGUE_ADMIN_PASSWORD`. Lives under `Admin::TenantsController` extending `Admin::BaseController` (the auth concern). This is what non-engineer ops use day-to-day.
- **Fallback surface**: `bin/rails rogue:tenants:seed[name,gm_name,gm_email]`. Used by integration tests for fast Tenant creation and by ops engineers for batch / scripted seeding. Logs to stdout with the resulting Tenant ID and confirmation email Message-ID for grepping.
- **Single source of truth**: both surfaces call `Tenant::Seeder.new(dealership_name:, gm_name:, gm_email:).call`, which performs the validation, persistence, and `OnboardingMailer#confirmation_email.deliver_later` enqueue. The controller and the rake task carry no business logic — they just translate inputs.

This is the best fit because the persona description in the Spec explicitly includes "non-engineer founders" — Option B would shut them out of the most-frequent operational action, which contradicts the friction-minimization principle for Rogue Staff itself. Option D's security-through-obscurity isn't worth the loss of a clear admin namespace. Option A is fine but loses the scriptability that integration tests benefit from. Option C dominates.

### Implementation guidance

**Routes** (`config/routes.rb`):

```ruby
namespace :admin do
  resources :tenants, only: %i[new create show] do
    member do
      post :resend_confirmation
    end
  end
end
```

**Controller skeleton** (`app/controllers/admin/base_controller.rb`):

```ruby
class Admin::BaseController < ApplicationController
  http_basic_authenticate_with(
    name: ENV.fetch("ROGUE_ADMIN_USERNAME"),
    password: ENV.fetch("ROGUE_ADMIN_PASSWORD"),
  )
end
```

**Service** (`app/services/tenant/seeder.rb`):

```ruby
class Tenant::Seeder
  def initialize(dealership_name:, gm_name:, gm_email:)
    @dealership_name = dealership_name
    @gm_name = gm_name
    @gm_email = gm_email.downcase.strip
  end

  def call
    tenant = Tenant.create!(
      dealership_name: @dealership_name,
      gm_name: @gm_name,
      gm_email: @gm_email,
      status: "pending_confirm",
      confirmation_sent_at: Time.current,
    )
    OnboardingMailer.with(tenant: tenant).confirmation_email.deliver_later
    tenant
  end
end
```

**Rake task** (`lib/tasks/rogue.rake`):

```ruby
namespace :rogue do
  namespace :tenants do
    desc "Seed a Tenant: bin/rails rogue:tenants:seed[name,gm_name,gm_email]"
    task :seed, %i[dealership_name gm_name gm_email] => :environment do |_, args|
      tenant = Tenant::Seeder.new(**args.to_h).call
      puts "Seeded Tenant ##{tenant.id} (#{tenant.dealership_name}); confirmation queued."
    end
  end
end
```

**Confirmation email body** (exact copy):

```
Subject: Welcome to Rogue — confirm to begin

Hi <gm_name>,

Welcome to Rogue. We've set up your dealership (<dealership_name>) and we're ready to start.

To begin, click the link below:

  → Confirm and start onboarding
    <https://app.rogue.example/onboarding/confirm/<signed_id>>

This is the only click we'll ask of you on the web. Everything else happens in this inbox.

After you confirm, we'll send you one short question at a time over the next several days — things like "who controls your marketing strategy?" — and you can answer by replying and CC'ing the right person.

— The Rogue team
```

**Plain-text alternative**: identical content (no HTML); accessibility requirement.

**Flash on successful seed**: `"Seeded <Dealership Name> — confirmation email queued for <gm_email>."`

**Resend confirmation** (`POST /admin/tenants/:id/resend_confirmation`): reissues the confirmation email if `Tenant.status == "pending_confirm"`. Updates `confirmation_sent_at`. No-op (with flash notice) if already confirmed.

---

## J2. First-question delivery delay after confirm (GM persona)

### Context

After the GM clicks the confirmation link, `EnqueueFirstQuestionJob` runs and queues `OnboardingMailer#question_email` for the first marketing-catalog question. The Spec defaults to `0 minutes` (immediate), with a `Tenant.first_question_delay_minutes` field for per-Tenant override. The question this resolves: what's the right default?

The constraints that matter most here:

- **GM's emotional state at confirm-click**: they just committed. They expect *something* to happen. Total silence after a click is the "did anything actually work?" failure mode.
- **Pacing rhythm**: questions are spaced "over days" (productBrief). Day 1 is the confirm; the rest of the questions arrive over days 2-7+. The first question is the kickoff — what's the right gap between "confirm click" and "first question lands"?
- **Operational complexity**: timezone-aware delivery requires knowing the GM's timezone. The seed form does NOT collect this; productBrief is silent on it. Inferring it from email domain or IP at confirm-click is fragile and possibly creepy.
- **Email client noise**: emails sent within ~30 seconds of each other are sometimes threaded together by Gmail/Outlook. A confirmation email *and* a first question email both landing within a minute is plausibly indistinguishable from a single welcome with two messages — losing the "one question at a time" signal.

### Options

#### Option A: Immediate (0 minutes)
- **Pros**:
  - Simplest. No scheduling logic. No timezone tracking.
  - Gives the GM something to do right after the confirm — momentum is preserved.
  - The confirmation page already says "watch your inbox for our first question"; immediate delivery makes that promise tangible.
- **Cons**:
  - Risk of being threaded with the confirmation email by some clients (Gmail in particular threads on subject + sender).
  - Removes the "humanizing breath" — feels machine-paced from the very first interaction.
  - If the GM clicks confirm at 11pm, the first question lands at 11pm. The GM either ignores it overnight (and our pacing rhythm is already off) or feels surveilled by an after-hours email.

#### Option B: ~1 hour humanizing delay
- **Pros**:
  - Reads as "a person will get back to you" pacing rather than "a bot fired immediately."
  - 1 hour is short enough that the GM hasn't switched contexts entirely — they'll still recognize the email when it lands.
  - Avoids the Gmail threading edge case.
- **Cons**:
  - GM might be in flow when they confirm and want to keep going; 1h is enough to lose them to other tasks.
  - Still timezone-blind — a confirm at 11pm yields a question at midnight.

#### Option C: Wait until next business hour (most considerate, most complex)
- **Pros**:
  - Best emotional pacing — questions only land during the GM's working hours.
  - Sets up the rhythm for J3 (question pacing) — "we never ping you outside business hours" is a strong promise.
- **Cons**:
  - **We don't have the GM's timezone.** Best we can do is infer from email domain (TLD-based heuristic — bad) or IP at confirm-click (works once, fails on VPN/cell), or ask. Asking is friction. Not asking is operationally wrong.
  - "Business hours" itself isn't well-defined for a GM (dealership hours are 9am-9pm in many markets).
  - Can be hand-waved as "8am Eastern" or "morning Eastern" but that's a fiction.
  - High implementation cost for marginal gain at MVP.

#### Option D: Adaptive — immediate during business hours, delayed if after-hours
- **Pros**:
  - Best of both worlds, sort of.
  - Compromise on timezone: assume Eastern at MVP (most US dealers are East Coast or operate on Eastern by convention for OEM reporting; productBrief is US-focused) and document the assumption.
- **Cons**:
  - Still timezone-fragile. A West Coast dealer confirming at 8am PT would get a same-day delivery 11am ET, fine — but a HI dealer at 8am HT would get a 1pm ET delivery, also fine. Most US edge cases are tolerable.
  - Logic is more complex than A or B; less complex than C.

### Evaluation

| Criterion | Opt A (immediate) | Opt B (1h) | Opt C (business hour) | Opt D (adaptive) |
|-----------|---|---|---|---|
| Implementation cost | Lowest | Low | High | Medium |
| Pacing feel | Robotic | Humanizing | Most considerate | Considerate |
| Timezone fragility | None | None | High | Medium |
| Risk of overnight delivery | High | High | None | Low |
| Confirmation-page promise | Strongest | Soft | Soft | Soft |
| GM-flow continuity | Best | OK | Worst | Good |

### Decision

**Chosen**: **Option B — ~1 hour humanizing delay (default `Tenant.first_question_delay_minutes = 60`).**

The 1-hour gap does three jobs:

1. **Avoids the Gmail/Outlook threading edge case** where two emails from the same sender within seconds get bundled.
2. **Reads as human-paced** — emails arriving "an hour later" feel like someone got to it, not like a bot fired on a webhook.
3. **Implementation is trivial** — `wait: 1.hour` on the Solid Queue enqueue; no timezone tracking, no business-hours logic, no per-region behavior.

The tradeoff against Option D is real but defensible at MVP: a GM confirming at 11pm gets the first question at midnight. This is suboptimal but not broken. The mitigation is in J3 — the *subsequent* questions in the cadence respect business hours via a calendar-aware envelope. So the worst-case pattern is "confirm at 11pm → first question at midnight (slightly weird) → second question at 9am next morning (good)." The first-question late-night anomaly is bounded to a single email and is recoverable.

We document `Tenant.first_question_delay_minutes` as the per-Tenant override (default 60). Rogue ops can lower it to 0 for demo/test Tenants and raise it to e.g. 720 (12 hours) for very-late-confirm scenarios. **Critical**: if the GM confirms within the first business hour of their day (assume Eastern at MVP), 60 minutes is fine. If they confirm late at night, J3's calendar-aware envelope catches subsequent questions; the first question is allowed to slip out into the night as the cost of simplicity.

The **confirmation web-page copy must reflect this delay**:

> "You're confirmed. Your first question will land in your inbox shortly — usually within an hour."

Note "shortly" + "usually within an hour" rather than "in an hour exactly." This sets the right expectation without making the system look broken if the queue is slightly backed up.

### Implementation guidance

**Default**: `Tenant.first_question_delay_minutes` integer column, default `60`, NOT NULL.

**Migration**:

```ruby
add_column :tenants, :first_question_delay_minutes, :integer, default: 60, null: false
```

**Confirmation flow** (`Onboarding::ConfirmationsController#show`):

```ruby
def show
  tenant = Tenant.find_signed!(params[:signed_id], purpose: :gm_confirm)
  if tenant.confirmed?
    render :already_confirmed
    return
  end
  tenant.update!(status: "confirmed", confirmed_at: Time.current)
  OnboardingFlow::EnqueueFirstQuestionJob
    .set(wait: tenant.first_question_delay_minutes.minutes)
    .perform_later(tenant_id: tenant.id)
  render :show
rescue ActiveSupport::MessageVerifier::InvalidSignature
  render :invalid_token
end
```

**Confirmation page copy** (`app/views/onboarding/confirmations/show.html.erb`):

```html
<h1>You're confirmed.</h1>
<p>Your first question will land in your inbox shortly — usually within an hour.</p>
<p>Everything from here happens by email. You don't need to log back in.</p>
```

---

## J3. Question pacing scheduler (GM persona, ongoing)

### Context

After the first question, subsequent questions are queued via `OnboardingFlow::EnqueueNextQuestionJob` with a default 24-hour delay per the Spec, with a flag for per-Tenant override. productBrief says questions are "spaced over days." Concretely: how does the cadence work between questions, and what happens when the GM is fast/slow/silent?

The constraints that matter most here:

- **GM responsiveness as a signal** — a GM replying in 10 minutes is in-flow and engaged; firing the next question 24 hours later loses momentum. A GM replying after 4 days is overloaded; firing the next question 24 hours after their reply piles on.
- **Risk of overwhelm vs. risk of stalling** — too fast = inbox fatigue, GM stops replying, onboarding stalls. Too slow = GM forgets the platform exists.
- **Vacations and silence** — what if the GM goes on vacation in the middle? Static cadence keeps firing into the void; emails pile up; when they come back they have 5 unanswered questions and they ignore all of them.
- **Calendar awareness** — questions arriving Saturday morning at 6am are noise. Questions arriving Tuesday at 9:30am ET are well-timed.
- **Operational complexity** — adaptive logic is testable but not trivial; calendar-aware logic is straightforward (cron-shaped).

### Options

#### Option A: Fixed 24h delay
- **Pros**: simplest. Predictable.
- **Cons**: Robotic. Ignores responsiveness and calendar. Breaks on vacations.

#### Option B: Fixed N-hour delay, per-Tenant config (`Tenant.next_question_delay_hours`)
- **Pros**: simplest with a knob. Lets ops customize per-Tenant for special cases.
- **Cons**: Same fundamental limitations. Just adds a knob.

#### Option C: Adaptive — accelerate when GM replies promptly, back off when they go quiet
- Concrete rule example:
  - If GM replies in <1h → next question in 12h
  - If GM replies in <24h → next question in 24h
  - If GM replies in <72h → next question in 48h
  - If GM has not replied in 72h → no new question fires until they do
- **Pros**:
  - Respects GM tempo — fast when they're engaged, slow when they're not, silent when they're absent.
  - Vacation-tolerant by construction (no replies = no questions = no pile-up).
- **Cons**:
  - More logic to test.
  - Risk of the GM never coming back from a long silence — but this is a feature, not a bug. The right intervention is a "still around?" nudge from Rogue Staff after a long silence, not more automated questions.
  - "Did the system break?" anxiety when a GM isn't sure why they're not getting questions. Mitigated by the in-thread ack always saying when the next question is coming.

#### Option D: Calendar-aware (no weekends, business-hours envelope)
- **Pros**: respects "don't email at 6am Saturday."
- **Cons**: alone, doesn't solve responsiveness. Best as a *modifier* to A/B/C, not a replacement.

#### Option E: Combination — Adaptive (C) + Calendar-aware envelope (D)
- The most effective: adaptive cadence determines the *gap*; the calendar envelope determines the *delivery time within the gap*.
- Example: GM replies Friday 4pm. Adaptive says "next question in 24h" → would fire Saturday 4pm. Envelope shifts it to Monday 9:30am ET.
- **Pros**: best of both. Respects tempo and calendar.
- **Cons**: Two systems to test together. Boundary conditions need explicit specification (Friday-late replies, holiday handling).

### Evaluation

| Criterion | Opt A | Opt B | Opt C | Opt D | Opt E |
|-----------|---|---|---|---|---|
| Implementation cost | Lowest | Lowest | Medium | Low | Medium |
| Vacation tolerance | None | None | High | None | High |
| Inbox-noise risk | Medium | Medium | Low | Low | Lowest |
| Momentum preservation | Low | Low | High | Medium | Highest |
| GM "did it break?" risk | Low | Low | Medium | Low | Low (if ack always tells GM next-question timing) |
| Testability | Trivial | Trivial | Medium | Trivial | Medium |

### Decision

**Chosen**: **Option E — Adaptive cadence with calendar-aware envelope.**

Concretely the cadence (the gap between GM reply and next question):

| Time since GM reply | Next-question gap |
|---------------------|-------------------|
| < 1 hour | 12 hours |
| < 24 hours | 24 hours (the productBrief default) |
| < 72 hours | 48 hours |
| ≥ 72 hours since reply | **No question scheduled.** Wait for the GM to reply or for Rogue Staff to nudge. |

The calendar envelope:

- Computed delivery time = `gm_reply_time + cadence_gap`.
- Apply rules:
  - If computed time falls Saturday or Sunday → shift to Monday 9:30am ET.
  - If computed time falls before 8am ET on a weekday → shift to that day at 9:30am ET.
  - If computed time falls after 6pm ET on a weekday → shift to next weekday at 9:30am ET.
  - **Exception**: the *first* question (J2) is exempt from the envelope (it fires 1 hour after confirm, regardless). This is intentional — the GM just clicked, momentum matters more than calendar fit.

**Why this is the right fit for Rogue specifically**:

1. The productBrief specifically calls out that the platform's bet is meeting GMs in their existing rhythm. A static 24h cadence assumes a uniform rhythm; adaptive matches each GM's actual cadence.
2. The "no question after 72h silence" behavior turns silence into a real signal that a human (Rogue Staff) needs to notice. This is congruent with the productBrief's overall ethos: humans-in-loop where humans matter, automation everywhere else.
3. The calendar envelope is cheap and avoids the worst-feeling failure mode (Saturday-morning pings) without the complexity of full timezone tracking. We assume Eastern at MVP and document the assumption; per-Tenant timezone is a post-MVP knob.
4. The in-thread ack (already specified) tells the GM exactly when the next question is coming ("Next question coming in 24h" → "Next question coming Monday morning"), which neutralizes the "did the system break?" anxiety.

**Important**: this decision adds a new field `Tenant.last_gm_reply_at` (timestamp) and a new state where the next-question job is *not* scheduled if the GM is silent. The `EnqueueNextQuestionJob` becomes a smart job that consults `last_gm_reply_at` rather than blindly running on a `wait:` interval.

### Implementation guidance

**Schema additions**:

```ruby
add_column :tenants, :last_gm_reply_at, :datetime
add_index :tenants, :last_gm_reply_at
```

`last_gm_reply_at` is updated by `OnboardingMailbox#process` when a GM reply is parsed (regardless of intent — assign / self_assign / skip / unparseable all count).

**Cadence calculation** (`Tenant#next_question_cadence_gap`):

```ruby
def next_question_cadence_gap
  return nil if last_gm_reply_at.nil? # no first reply yet — defer to first-question logic
  delta = Time.current - last_gm_reply_at
  case delta
  when 0..1.hour then 12.hours
  when 0..24.hours then 24.hours
  when 0..72.hours then 48.hours
  else nil # silence — do not schedule
  end
end
```

**Calendar envelope** (`OnboardingFlow::DeliveryEnvelope`, service object):

```ruby
class OnboardingFlow::DeliveryEnvelope
  EASTERN = ActiveSupport::TimeZone["America/New_York"]
  BUSINESS_OPEN_HOUR = 9.5  # 9:30am
  BUSINESS_CLOSE_HOUR = 18  # 6pm

  def self.shift(target_time)
    eastern = target_time.in_time_zone(EASTERN)
    return next_business_open(eastern) if weekend?(eastern) ||
                                          before_open?(eastern) ||
                                          after_close?(eastern)
    target_time
  end

  def self.weekend?(t) = t.saturday? || t.sunday?
  def self.before_open?(t) = (t.hour + t.min / 60.0) < BUSINESS_OPEN_HOUR
  def self.after_close?(t) = t.hour >= BUSINESS_CLOSE_HOUR

  def self.next_business_open(t)
    # advance to next weekday morning at 9:30am ET
    candidate = t.beginning_of_day + BUSINESS_OPEN_HOUR.hours
    candidate += 1.day until candidate.on_weekday? && candidate > t
    candidate
  end
end
```

**Job enqueue** (after a GM reply is parsed in `OnboardingMailbox`):

```ruby
gap = tenant.next_question_cadence_gap
if gap.present?
  target = OnboardingFlow::DeliveryEnvelope.shift(Time.current + gap)
  wait = target - Time.current
  OnboardingFlow::EnqueueNextQuestionJob
    .set(wait: wait)
    .perform_later(tenant_id: tenant.id)
end
# If gap is nil (silence > 72h since last reply), no enqueue. The next reply
# from the GM re-arms the cadence.
```

**In-thread ack copy must name the timing**:

For prompt replies:
> "Got it — Alex (alex@smithtoyota.com) is on the hook for marketing strategy. They'll receive setup instructions shortly. Next question coming in 12 hours."

For Friday-late or weekend-trapped scheduling:
> "Got it — Alex (alex@smithtoyota.com) is on the hook for marketing strategy. They'll receive setup instructions shortly. Next question coming Monday morning."

The mailer needs a small helper that humanizes the next-question delivery time relative to the ack send time. Implementation pattern:

```ruby
def humanize_next_question_at(time)
  return "shortly" if time.nil?
  delta = time - Time.current
  case delta
  when 0..18.hours then "in #{(delta / 1.hour).round} hours"
  when 0..36.hours then "tomorrow morning"
  else time.in_time_zone("America/New_York").strftime("%A morning")
  end
end
```

**No-cadence (silence) state**:

When `last_gm_reply_at > 72.hours.ago` and there's still an un-answered question outstanding, `EnqueueNextQuestionJob` does not fire. The system goes quiet. Rogue Staff observability needs (covered in `TASK-001-architecture.md` audit trail) include surfacing "Tenants in onboarding silence > 7 days" as a queryable view so ops can manually nudge or reach out.

---

## J4. Empty-state weekly digest behavior (GM persona, ongoing)

### Context

Once the Tenant is `confirmed` and ≥7 days have passed, `WeeklyDigestJob` fires. In week 1 specifically, the GM may have:

- Replied to 1-2 questions (so 1-2 Responsibilities exist), but
- Invitees have not yet completed setup (`Source.configured_at` is null), so
- No `SubmissionPrompt` has fired, no submissions exist.

Or even more sparsely: the GM has replied to nothing yet, has 0 Responsibilities, and the digest job runs at the 7-day mark. Spec defaults to "always send the digest with empty-state copy."

The question this resolves: is "always send" the right default, or should we suppress / substitute / gate?

The constraints that matter most here:

- **Habit formation** — the digest is the GM's primary accountability surface. They need to know it exists, when it lands, what it looks like. Silence in week 1 means the GM may not realize they get a digest at all.
- **Inbox fatigue** — a digest that says "nothing happened this week" is at risk of being marked spam, banner-ignored, or filtered to a sub-folder.
- **Accountability narrative** — productBrief explicitly says the digest "is reliable cadence even when there's no data." This frames cadence reliability as a product virtue. A digest that *sometimes* sends contradicts that.

### Options

#### Option A: Always send the digest, with empty-state copy
- **Pros**:
  - Cadence is a promise. Always-send keeps the promise.
  - Habit-formation: the GM learns "Tuesday morning, Rogue digest" within two weeks.
  - Empty-state copy can carry useful info ("here's what we're waiting on").
- **Cons**:
  - In a worst case where the GM has answered 0 questions, the digest has very little to say.

#### Option B: Suppress digest until ≥1 submission has happened
- **Pros**:
  - Avoids the "nothing to report" digest.
- **Cons**:
  - Breaks cadence reliability.
  - GM doesn't learn the digest exists until the platform is already deeply set up — by which point they might assume there's no digest.
  - Contradicts productBrief's explicit framing.

#### Option C: Different "still setting up" email instead of the standard digest
- **Pros**:
  - Tailors the message to the stage.
  - Could carry stage-specific calls to action ("4 questions still pending — answer them in your inbox").
- **Cons**:
  - Two email templates instead of one — more to maintain.
  - The transition from "still setting up" to "first real digest" is a UX cliff. The GM gets a different-shaped email each Tuesday for the first 4 weeks; pattern recognition never solidifies.

#### Option D: Send standard digest only if ≥N configured Responsibilities (e.g., N=1 or N=3)
- **Pros**:
  - Threshold-based gating — avoids the "0 responsibilities, 0 submissions" emptiest case.
- **Cons**:
  - Arbitrary threshold. Why 1 vs. 3?
  - Still breaks cadence reliability.
  - Same UX-cliff problem as C.

### Evaluation

| Criterion | Opt A | Opt B | Opt C | Opt D |
|-----------|---|---|---|---|
| Habit formation | Highest | Lowest | Medium | Low |
| Cadence reliability | Highest | Broken | Mixed | Broken |
| Inbox-fatigue risk | Medium | None | Medium | Medium |
| Implementation cost | Lowest | Low | Medium | Low |
| Aligns with productBrief | Yes (explicit) | No | Partial | Partial |

### Decision

**Chosen**: **Option A — Always send the digest, with explicit empty-state copy that carries useful information.**

Three sub-decisions on the empty-state content:

1. **Subject line never lies about there being content.**
   - With submissions: `"Smith Toyota — weekly accountability digest"`
   - Empty (no submissions yet, but ≥1 Responsibility): `"Smith Toyota — getting set up"`
   - Empty (0 Responsibilities, GM hasn't engaged): `"Smith Toyota — still waiting on you"`

2. **Body always shows the same shape** (responsibility table + dashboard CTA), but the row content is stage-aware:
   - 0 Responsibilities: table replaced with a single line: "We haven't heard from you yet. We sent you <N> question(s); answering any of them gets your accountability set up. The most recent: <subject of latest pending question>."
   - ≥1 Responsibility, 0 submissions: table shows each Responsibility with status `pending_first_submission` and a `Next due: <date>` column. Empty-state line at the top: "No submissions yet — first one due <earliest date across responsibilities>."
   - Mixed status: standard table.

3. **The dashboard CTA is always present**, but its label changes:
   - Empty / partial: `"Open dashboard"` (same as default — the dashboard still has *something* to show even with 0 submissions).

This is the best fit because the productBrief is unusually explicit on this point: "digest is reliable cadence even when there's no data." Reliable cadence is the product's commitment. Options B/C/D all break that commitment in some way. The only real cost of Option A is "an email that has nothing useful to say," and we mitigate that by making the empty-state copy itself useful (calling out specific pending questions, calling out specific upcoming due dates).

The "still waiting on you" subject for the GM-has-0-Responsibilities case is a deliberate choice: it's more pointed than the default subject, and it surfaces social pressure without being preachy. This matches the tone of the productBrief's accountability language ("the named-callout is deliberate; it surfaces social pressure without preaching").

### Implementation guidance

**Digest job logic** (`AccountabilityMailer#weekly_digest`):

```ruby
def weekly_digest(tenant)
  @tenant = tenant
  @responsibilities = tenant.responsibilities.includes(:requests)
  @pending_questions = tenant.pending_question_emails  # un-answered question emails sent ≥48h ago
  @latest_submissions = tenant.submissions.recent_in_window(1.week)

  subject = compose_subject(@tenant, @responsibilities, @latest_submissions)
  mail(to: @tenant.gm_email, subject: subject)
end

private

def compose_subject(tenant, responsibilities, submissions)
  return "#{tenant.dealership_name} — still waiting on you" if responsibilities.empty?
  return "#{tenant.dealership_name} — getting set up" if submissions.empty?
  "#{tenant.dealership_name} — weekly accountability digest"
end
```

**Empty-state copy in the body** (`app/views/accountability_mailer/weekly_digest.html.erb`):

```erb
<% if @responsibilities.empty? %>
  <p>We haven't heard from you yet this week.</p>
  <p>We sent you <%= @pending_questions.size %> question<%= "s" if @pending_questions.size != 1 %> — answering any of them gets your accountability set up. The most recent: <strong>"<%= @pending_questions.last.question.text %>"</strong></p>
  <p>Reply to that email with the right person on CC, and we'll take it from there.</p>
<% elsif @latest_submissions.empty? %>
  <p>No submissions yet — first one due <%= @responsibilities.map(&:next_due_date).compact.min&.strftime("%B %-d") || "(setup pending)" %>.</p>
  <h2>Your responsibilities</h2>
  <%= render "responsibility_table", responsibilities: @responsibilities %>
<% else %>
  <h2>This week</h2>
  <%= render "responsibility_table", responsibilities: @responsibilities %>
<% end %>

<p style="margin-top: 2em;">
  <a href="<%= dashboard_url(@tenant.signed_id(purpose: :dashboard_drilldown, expires_in: 8.days)) %>">
    Open dashboard
  </a>
</p>
```

**Plain-text alternative** mirrors the same content (accessibility / non-HTML-clients).

**Idempotency**: digest is idempotent on `(tenant_id, week_starting)` — late re-runs (e.g., if the worker drops mid-job) do not double-send. Implementation: a `SentDigest` row created BEFORE the mailer is enqueued; the job short-circuits if the row already exists for the current week. This applies to all three subject variants.

---

## J5. Resend-link UX for expired tokens

### Context

Three magic-link surfaces have expiry:

- **Confirmation token** — 72h, single-use, only meaningful for the GM.
- **Setup token** — 7 days, reusable until expiry, meaningful for an Invited Contact.
- **Dashboard token** — 8 days, reusable, meaningful for the GM.

The Spec proposes "self-serve resend form" for each surface. The question this resolves: what's the right resend UX for each, and how do we handle enumeration risk?

The constraints that matter most here:

- **Enumeration risk** — a self-serve resend form keyed on email could leak which addresses are registered Tenants. This is a real but low-impact leak (Rogue is B2B; the universe of dealership GM emails is not a privacy honeypot like a consumer service). Still, the form should not say "no Tenant found for this email" — it should always say "if that email is registered, a new link is on the way."
- **GM-only-recovery for confirmation** — only the GM should be able to request a new confirm link. If anyone with the GM's email address could trigger a resend, they could potentially intercept the new link if they have inbox access. Mitigated by sending the new link only to the registered `Tenant.gm_email` (which is the only address that ever sees the link).
- **Operational simplicity** — three different flows = three different forms = three different controllers. Lots of surface area.
- **Copy** — must not make the GM/invitee feel like the system is broken. "This link expired" is fine; "We couldn't find your account" is hostile.

### Options

#### Option A: Self-serve resend form (single form per surface, no rate limit)
- **Pros**: simple. Three controllers, three forms.
- **Cons**: no rate limit → a determined attacker can hit the resend endpoint at scale, both for enumeration and for spam-emailing-the-GM-address. Trivially mitigated.

#### Option B: Self-serve with rate limit (e.g., 3 per email per hour)
- **Pros**: same shape as A, but with a guardrail that prevents abuse.
- **Cons**: marginal extra implementation (Rails 8 ships a rate-limit primitive in `ActionController::RateLimit` since 7.2). Cheap.

#### Option C: GM-mediated for confirmation; self-serve for setup/dashboard
- The GM cannot self-resend the confirmation link via a public form. Instead, an expired confirmation link displays a page that says "ask Rogue ops to send you a new one" with a `mailto:` to support, OR the GM goes back to Rogue Staff who reissues via the admin surface (`POST /admin/tenants/:id/resend_confirmation`).
- Setup and dashboard are self-serve.
- **Pros**: hardens confirmation against any misuse.
- **Cons**: wildly inconsistent UX — GMs hit different surfaces for different expirations. The "this is broken" feeling is high.

#### Option D: Magic-link-style URL re-issue (`?resend=1` query param triggers resend form)
- **Pros**: auto-fills the email on the form (less typing).
- **Cons**: clever for clever's sake. The GM clicked an expired link; the URL probably contains a tenant signed_id we can decode for context; we can pre-fill the form anyway without a separate URL pattern.

### Evaluation

| Criterion | Opt A | Opt B | Opt C | Opt D |
|-----------|---|---|---|---|
| Implementation cost | Lowest | Low | Medium | Low |
| Enumeration leak | Mild | Mild | None for confirm | Mild |
| Abuse resistance | Low | Medium | High for confirm | Low |
| UX consistency | High | High | Low | High |
| Friction | Lowest | Low | High | Low |

### Decision

**Chosen**: **Option B — Self-serve resend form with rate limit, identical UX shape across all three surfaces.**

Specifically:

1. **One controller per surface, all three forms identical in shape**:
   - `Onboarding::ConfirmationsController#new_resend` (GET) and `#resend` (POST)
   - `Setup::WalkthroughsController#new_resend` (GET) and `#resend` (POST)
   - `DashboardsController#new_resend` (GET) and `#resend` (POST)
   Each form: one email field + "Send me a new link" button.

2. **Rate limit**: 3 requests per email-address-per-hour, per surface. Implementation: Rails 8 `ActionController::RateLimit` keyed on `(controller_name, params[:email].downcase)`. Excess requests render a "too many requests" page with retry-at time.

3. **Anti-enumeration response copy is identical regardless of whether the email matches**:
   - On submit: render a confirmation page that says: `"If <email> is registered, we just sent a new link. Check your inbox in the next few minutes."` Always say this. Never say "no account found."

4. **For confirmation specifically (the highest-stakes surface)**:
   - The new confirm link is sent to `Tenant.gm_email`, NOT to the email address the user typed in the form. The form's email field is used only as a lookup key. If the email matches a Tenant's `gm_email`, that Tenant's `gm_email` (the same address) gets the new link. If someone types `attacker@example.com` because they're trying to hijack, no email is sent and they get the same "if registered, sent" message.
   - Effectively this is "self-serve, but the destination is hard-coded to the registered address." This neutralizes the hijack vector.

5. **For setup**: the lookup key is the contact's email; the new setup link goes to that contact's registered email. Same hijack mitigation.

6. **For dashboard**: same shape — the new dashboard link goes to `Tenant.gm_email`.

7. **Copy on the expired-link landing page** (the page the user actually sees when they click an expired link):

   For confirmation:
   > **This confirmation link is no longer valid.**
   >
   > Confirmation links expire 72 hours after they're sent.
   >
   > If you'd like a fresh one, enter your email below and we'll send you a new link.
   >
   > [email field] [Send me a new link]

   For setup:
   > **This setup link has expired.**
   >
   > Setup links are valid for 7 days. Drop your email below and we'll send you a fresh one.
   >
   > [email field] [Send me a new link]

   For dashboard:
   > **This dashboard link has expired.**
   >
   > Each weekly digest includes a fresh link. If you'd like one now, enter your email and we'll send it.
   >
   > [email field] [Send me a new link]

8. **Already-confirmed branch (confirmation surface only)**: a separate copy:
   > **You've already confirmed <Dealership Name>.**
   >
   > Watch your inbox for the next question — that's where everything happens from here.

The right fit for Rogue specifically: Option C's hardening for confirmation is overkill at MVP (Rogue is B2B with a small number of registered Tenants; phishing attack-surface is tiny), and the UX inconsistency cost is real. Option B captures the security wins (rate limit + hijack-proof destination) without the UX cost.

The implementation simplicity is also worth noting: one shared `ResendForm` partial template, three thin controllers each delegating to a `<Surface>::Resender` service. If the rate-limit logic shifts to Rack-Attack later, the controllers don't need to change.

### Implementation guidance

**Routes**:

```ruby
# Confirmation resend
get  "/onboarding/confirm/resend", to: "onboarding/confirmations#new_resend"
post "/onboarding/confirm/resend", to: "onboarding/confirmations#resend"

# Setup resend
get  "/setup/resend", to: "setup/walkthroughs#new_resend"
post "/setup/resend", to: "setup/walkthroughs#resend"

# Dashboard resend
get  "/dashboard/resend", to: "dashboards#new_resend"
post "/dashboard/resend", to: "dashboards#resend"
```

**Rate-limit middleware** (per controller):

```ruby
class Onboarding::ConfirmationsController < ApplicationController
  rate_limit to: 3,
             within: 1.hour,
             only: :resend,
             by: ->(req) { req.params[:email].to_s.downcase },
             with: -> { render :rate_limited, status: :too_many_requests }

  # ... actions ...
end
```

**Resender service** (`app/services/onboarding/confirmation_resender.rb`):

```ruby
class Onboarding::ConfirmationResender
  def initialize(email)
    @email = email.to_s.downcase.strip
  end

  def call
    tenant = Tenant.where(gm_email: @email, status: "pending_confirm").first
    return :no_match if tenant.nil?

    tenant.update!(confirmation_sent_at: Time.current)
    OnboardingMailer.with(tenant: tenant).confirmation_email.deliver_later
    :sent
  end
end
```

**Anti-enumeration response (controller)**:

```ruby
def resend
  Onboarding::ConfirmationResender.new(params[:email]).call
  # Always render the same template regardless of result.
  render :resend_sent
end
```

**Resend confirmation page copy** (`app/views/onboarding/confirmations/resend_sent.html.erb`):

```erb
<h1>Check your inbox.</h1>
<p>If <%= h params[:email] %> is registered, we just sent a new link. It should arrive in the next few minutes.</p>
<p>Confirmation links expire after 72 hours.</p>
```

**Audit logging**: every resend attempt — successful or not — logs to `Rails.logger.tagged(flow: :onboarding, action: :resend)` with the email (lowered), result (`sent | no_match | rate_limited`), and timestamp. This gives ops a way to spot enumeration attempts without surfacing them to the requester.

---

## Acceptance criteria additions

These ACs emerge from the J1-J5 decisions and extend the Spec's existing AC list. Build phase tests should cover all of them.

### AC-J1-1: Rake task seeds an identical Tenant to the controller path
**Priority**: SHOULD
- **Given**: a fresh database.
- **When**: `bin/rails rogue:tenants:seed[Smith Toyota,Jane Smith,jane@smithtoyota.com]` runs.
- **Then**: a `Tenant` row is persisted with the same fields and `status="pending_confirm"`, and `OnboardingMailer#confirmation_email` is enqueued — equivalent to a controller submission.
- **Verification**:
  - [ ] Rake task test using `Rake.application.invoke_task` or equivalent.

### AC-J2-1: First question fires 1 hour after confirm by default
**Priority**: MUST
- **Given**: GM clicks confirm at time T.
- **When**: `EnqueueFirstQuestionJob` is enqueued.
- **Then**: the job's `scheduled_at` is between `T + 59m` and `T + 61m`.
- **Verification**:
  - [ ] Job test asserting `wait` argument equals `tenant.first_question_delay_minutes.minutes` (default 60).

### AC-J2-2: Confirmation page copy mentions the ~1h delay
**Priority**: MUST
- **Given**: GM lands on `/onboarding/confirm/<signed_id>` with a valid token.
- **When**: page renders.
- **Then**: visible body contains the literal string `"shortly — usually within an hour"`.
- **Verification**:
  - [ ] System test asserting page text.

### AC-J3-1: Adaptive cadence accelerates on prompt GM reply
**Priority**: MUST
- **Given**: GM replied <1h after receiving a question.
- **When**: `OnboardingMailbox` finishes processing.
- **Then**: `EnqueueNextQuestionJob` is enqueued with `wait: 12.hours` (subject to envelope shifting).
- **Verification**:
  - [ ] System test with a fixture reply timed at 30m post-question; assert the enqueued wait.

### AC-J3-2: Adaptive cadence backs off on slow GM reply
**Priority**: MUST
- **Given**: GM replied 50h after receiving a question.
- **When**: `OnboardingMailbox` finishes processing.
- **Then**: `EnqueueNextQuestionJob` is enqueued with `wait: 48.hours` (subject to envelope shifting).
- **Verification**:
  - [ ] System test with a fixture reply timed at 50h post-question.

### AC-J3-3: GM silence > 72h does not enqueue a next question
**Priority**: MUST
- **Given**: it has been 72h since `Tenant.last_gm_reply_at` and a question is outstanding.
- **When**: any logic that would normally enqueue a next question runs.
- **Then**: no `EnqueueNextQuestionJob` is enqueued.
- **Verification**:
  - [ ] Unit test on `Tenant#next_question_cadence_gap` returning nil.
  - [ ] System test asserting no enqueue.

### AC-J3-4: Calendar envelope shifts weekend deliveries to Monday morning ET
**Priority**: MUST
- **Given**: cadence calculation yields a target delivery time of Saturday 10am ET.
- **When**: `OnboardingFlow::DeliveryEnvelope.shift` runs.
- **Then**: the returned time is Monday at 9:30am ET that same week.
- **Verification**:
  - [ ] Unit test on `DeliveryEnvelope.shift` with weekend, before-open, and after-close fixtures.

### AC-J3-5: In-thread ack names the next-question timing in human-friendly terms
**Priority**: MUST
- **Given**: GM reply parsed and next-question enqueued.
- **When**: `in_thread_ack` mailer renders.
- **Then**: body contains a phrase like `"Next question coming in 12 hours"`, `"Next question coming tomorrow morning"`, or `"Next question coming Monday morning"` — derived from the actual scheduled time.
- **Verification**:
  - [ ] Mailer test with multiple fixture send-times.

### AC-J4-1: Empty-state digest with 0 Responsibilities uses the "still waiting on you" subject
**Priority**: MUST
- **Given**: Tenant `confirmed` ≥7 days; 0 Responsibilities; ≥1 outstanding question.
- **When**: `WeeklyDigestJob` runs.
- **Then**: email subject is `"<Dealership> — still waiting on you"` and body names the most recent pending question.
- **Verification**:
  - [ ] Mailer test with 0-responsibility fixture.

### AC-J4-2: Empty-state digest with Responsibilities-but-no-submissions uses the "getting set up" subject
**Priority**: MUST
- **Given**: Tenant `confirmed` ≥7 days; ≥1 Responsibility; 0 Submissions.
- **When**: `WeeklyDigestJob` runs.
- **Then**: email subject is `"<Dealership> — getting set up"` and body shows the responsibility table with `pending_first_submission` status and explicit next-due dates.
- **Verification**:
  - [ ] Mailer test with mid-state fixture.

### AC-J4-3: Digest is idempotent on (tenant_id, week_starting)
**Priority**: MUST
- **Given**: `WeeklyDigestJob` has already run for tenant T in week W.
- **When**: the job runs again for the same (T, W).
- **Then**: no second email is sent.
- **Verification**:
  - [ ] Job test running twice in the same week-window.

### AC-J5-1: Resend form returns identical response regardless of whether email matches
**Priority**: MUST
- **Given**: an expired confirmation token surface.
- **When**: the resend form is submitted with email A (registered) and email B (not registered).
- **Then**: the rendered page is byte-identical (anti-enumeration).
- **Verification**:
  - [ ] System test driving both submissions and asserting matching response bodies.

### AC-J5-2: New confirmation link is sent only to the registered GM email
**Priority**: MUST
- **Given**: an attacker submits the confirmation resend form with email `attacker@example.com` while the GM's registered email is `jane@smithtoyota.com`.
- **When**: the request is processed.
- **Then**: no email is sent to `attacker@example.com`. The registered Tenant is not affected.
- **Verification**:
  - [ ] Controller test asserting no enqueued mail.

### AC-J5-3: Rate limit blocks the 4th request from the same email within an hour
**Priority**: SHOULD
- **Given**: 3 resend requests for the same email in the last hour.
- **When**: a 4th request arrives.
- **Then**: response is 429 with a "too many requests" page; no email is enqueued.
- **Verification**:
  - [ ] Controller test simulating 4 rapid requests.

### AC-J5-4: Already-confirmed branch shows a distinct page
**Priority**: MUST
- **Given**: GM clicks a previously-used confirmation link (Tenant already `confirmed`).
- **When**: `Onboarding::ConfirmationsController#show` runs.
- **Then**: page renders the "You've already confirmed <Dealership>" copy with a pointer to the inbox, not the resend form.
- **Verification**:
  - [ ] Controller test for the already-confirmed branch.

---

## Cross-cutting journey concerns

These themes tie J1-J5 together and need to be visible to the build phase as a unit:

### Theme 1: The "pacing model" is a system, not a parameter

J2 (first-question delay) and J3 (between-question cadence) are not independent settings — they are two parts of one pacing model:

```
[Confirm click]
     │
     │ + 60 min (J2 default)
     ▼
[First question delivered]
     │
     │ ... GM replies ...
     ▼
[Reply parsed; in-thread ack sent]
     │
     │ + cadence_gap(time_since_reply) (J3)
     │    + envelope shift to next business window (J3)
     ▼
[Next question delivered]
     │
     │ ... loop ...
```

The `Tenant.last_gm_reply_at` field is updated on every parsed reply (regardless of intent). The `Tenant.first_question_delay_minutes` field is exempt from the calendar envelope (first question intentionally fires "shortly" regardless of time-of-day); subsequent questions go through the envelope. **Build phase MUST treat first-question delay and inter-question cadence as a single feature, with shared tests.**

### Theme 2: Email-as-narrative — every outbound email tells the GM what's next

A through-line across all the mail templates: every outbound email (confirmation, in-thread ack, digest) names the next thing the GM should expect. This is the "did the system break?" mitigation. Concretely:

- Confirmation email: "we'll send you one short question at a time over the next several days" + confirmation page repeats "your first question will land in your inbox shortly."
- In-thread ack: "Next question coming <time>."
- Weekly digest (empty-state): "We sent you N questions; the most recent: <question>."
- Resend confirmation page: "Check your inbox in the next few minutes."

The build phase MUST audit every mailer template for this property. A template that does not tell the GM what's next is incomplete.

### Theme 3: Silence is a signal, not a failure

J3's "no question after 72h silence" decision changes how silence is treated. Instead of "the system gives up," it's "the system waits and surfaces this state to ops." Two implications:

1. **The build phase must add a queryable view** (model scope or DB view) for "Tenants in onboarding silence > 7 days." This is part of FEAT-001's observability surface, even though full ops dashboards are deferred. Concretely: `Tenant.in_onboarding_silence(threshold: 7.days)` scope.

2. **The weekly digest still fires** during silence — the empty-state copy is now load-bearing. Without the digest, a silent GM gets *zero* contact from Rogue. The digest's "still waiting on you" subject is the silence-breaker.

### Theme 4: Eastern Time as MVP timezone assumption

J3's calendar envelope assumes Eastern Time. This is documented MVP scope (most US dealers report on Eastern by OEM convention; per-Tenant timezone is post-MVP). Build phase MUST:

1. Hard-code `America/New_York` in `OnboardingFlow::DeliveryEnvelope`.
2. Add a `# TODO(post-MVP): per-Tenant timezone` comment.
3. Document the assumption in `systemPatterns.md` Open Decisions when this code lands.

### Theme 5: Resend is shaped identically across all three surfaces

J5 chose Option B specifically so that the resend UX is identical across confirmation, setup, and dashboard. Build phase MUST factor the form rendering into a shared partial (`app/views/shared/_resend_form.html.erb`) and the resender services into a common interface. Future surfaces (e.g., a vendor-facing magic link) plug into the same shape without introducing a new pattern.

---

## Validation Checklist

- [x] Journey delivers stated value (Tenant onboarded, GM never logged in, accountability cadence established)
- [x] All personas can complete journey (Rogue Staff via web or rake; GM via email; Invitee via web)
- [x] Errors are recoverable (resend forms on every magic-link surface; non-GM-sender bounce; unparseable reply ack)
- [x] Async states are clear (every email names what's next; in-thread acks land within 5 minutes)
- [x] Consistent with existing patterns (signed_id per purpose, Action Mailbox, Solid Queue)
- [x] Accessible per requirements (plain-text alternatives on every mailer; keyboard-navigable forms)
- [x] Testable with defined scenarios (every J-decision has matching ACs)

## Next Steps

1. Architecture creative phase resolves Action Mailbox addressing, Question Catalog data model, and audit-event shape — those decisions feed directly into Phase 1 and Phase 4.
2. Algorithm creative phase resolves reply-parser internals — feeds Phase 4.
3. Build phase 1 (Foundation) implements `Tenant.first_question_delay_minutes`, `Tenant.last_gm_reply_at`, and `Tenant.in_onboarding_silence` scope — adopted from J2 / J3 / Theme 3.
4. Build phase 2 (Seed + Confirm) implements the rake task alongside the controller per J1, plus the J5 confirmation-resend flow.
5. Build phase 3 (First Question) implements the J2 1h delay.
6. Build phase 4 (Inbound Reply) implements the J3 adaptive cadence + delivery envelope.
7. Build phase 5 (Invitee Setup) implements J5 setup-resend.
8. Build phase 6 (Digest + Dashboard) implements J4 empty-state copy and J5 dashboard-resend.

---

USER JOURNEY CREATIVE COMPLETE
Document: memory-bank/creative/TASK-001-user-journey.md
Journey: [Rogue Staff seeds at /admin/tenants/new] → [GM clicks confirm] → [first question +1h] → [adaptive paced Q&A loop with calendar envelope] → [invitee web setup] → [weekly digest with stage-aware empty-state copy]
Pattern: Asynchronous email thread with sync web edges
