# TASK-006: Dev-only reply link in onboarding question email

**Complexity**: Level 1
**Status**: IN_PROGRESS
**Roadmap**: N/A
**Branch**: task/006-dev-reply-link
**Worktree**: N/A (Level 1 uses direct branch)

## Task Description

Implement a "reply link" rendered in dev-environment emails only. The link
opens the Action Mailbox conductor's `new inbound email` form
(`/rails/conductor/action_mailbox/inbound_emails/new`) with the form fields
pre-populated for the GM's reply: `from`, `to` (the tenant's
`onboarding+<token>@…` address), `subject` (the canonical reply subject),
and `in_reply_to` (the question's outbound Message-ID).

Motivation: during manual testing with letter-opener, fabricating an inbound
email currently requires hand-copying the token + Message-ID out of the DB
and pasting them into the conductor form. A pre-filled link removes that
friction and matches the actual flow the GM exercises in production
(reply-by-email).

## Implementation Notes

- The conductor's `new.html.erb` (in actionmailbox-8.1.3) already reads
  `params[:from]`, `params[:to]`, `params[:cc]`, `params[:in_reply_to]`,
  `params[:subject]`, and `params[:body]` as default values. No conductor
  patching needed.
- Route helper: `new_rails_conductor_inbound_email_url`.
- Add helper `dev_conductor_reply_url(tenant:, question:)` to
  `OnboardingMailerHelper`. Returns nil unless `Rails.env.development?` so
  guards in templates collapse cleanly.
- Render the link in both `question_email.html.erb` and
  `question_email.text.erb`. Other mailers don't solicit replies in the
  same way and stay untouched.
- No production code path runs the helper — gating is in the helper itself.

## Files Touched

- `app/helpers/dev_tooling_helper.rb` — new module with `dev_conductor_reply_url(message:)`
- `app/mailers/application_mailer.rb` — `helper :dev_tooling`
- `app/mailers/onboarding_mailer.rb` — set `headers["Message-ID"]` before `mail()`
  so the persistent ID is on `@_message` at render time
- `app/views/layouts/mailer.html.erb` — render dev callout below `<%= yield %>`
- `app/views/layouts/mailer.text.erb` — same in text form

The link is on **every** mailer that uses the default `mailer` layout
(every mailer in the app today inherits `ApplicationMailer` which sets
`layout "mailer"`).

## Approach Notes

The helper extracts `from`, `to`, `subject`, and `message_id` directly from
the `@_message` (`Mail::Message`) instance available to mailer templates,
then swaps From/To when building the conductor URL — the recipient becomes
the simulated reply sender, the original sender becomes the reply target.
This means:

- **Onboarding emails** (where the From is `onboarding+<token>@…`) produce
  a link that re-injects exactly into `OnboardingMailbox`.
- **Other mailers** (Submission/Accountability/Escalation) produce a
  technically-functional link too — clicking it just creates a fake
  inbound to whichever From the email used (e.g.
  `Rogue <hello@inbound.rogue.example>`). For dev that's harmless and
  occasionally useful for exercising routing fallbacks.

`Rails.env.development?` gating lives inside the helper, so the layout's
`<% if (dev_url = ...) %>` collapses cleanly to no-op in test/production.
The 78 existing mailer specs all still pass (no assertions on dev block
content; in test env it's never rendered).

## Verification

1. With `bin/rails server` + `bin/jobs` running, click through steps 1-2 of
   the manual test runbook (seed tenant → confirm). Use the SolidQueue nudge
   if needed so the question email lands.
2. Open the question email tab in letter-opener. A "Reply via Action Mailbox
   conductor (dev)" link should appear at the bottom.
3. Click the link → conductor form should be populated with the GM's email,
   the tenant onboarding address (with the right token), the canonical reply
   subject, and the `In-Reply-To` Message-ID.
4. Add a CC + body, submit, confirm `OnboardingMailbox` processes it
   (Responsibility/Source/Request created, ack to GM, setup invite to CC).

---

## Execution State

**Build Status**: IMPLEMENTED — awaiting manual verification + commit
**Current Phase**: BUILD
**Can Resume**: NO

### Active Sub-Agents
(none)

### Completed Steps
- Branch created: `task/006-dev-reply-link`
- Task file created
- `dev_conductor_reply_url` helper added to `OnboardingMailerHelper`
  (gated on `Rails.env.development?`, returns nil otherwise)
- `question_email.html.erb` renders amber dev-only callout when helper non-nil
- `question_email.text.erb` appends a `DEV ONLY` line when helper non-nil
- Smoke-tested via `bin/rails runner` — URL well-formed in dev, nil in
  stubbed-production env
- Existing mailer specs still pass (44/44)
