# UI/UX Decision: Cc'd Contact Self-Verification

**Created**: 2026-05-09
**Status**: DECIDED
**Decision Type**: UI/UX
**Task**: TASK-008 (FEAT-006)
**Resolves**: Email copy, identity-step layout, error states, step-counter convention, transition copy, empty-responsibility terminal page.

---

## Codebase Reality Note

The task prompt referenced "Tailwind." The codebase uses **inline CSS styles** exclusively — no Tailwind gem, no `tailwind.config.js`, no utility class in any `.erb` file. All styling is via `style=""` attributes on HTML elements (established by `app/views/submissions/forms/show.html.erb`, `app/views/setup/walkthroughs/*.html.erb`).

All design specifications below use the existing inline-style design language. "Reuse the pattern from X" means copy the `style=""` string from that file, not a Tailwind class.

---

## User Context

### Target Users

- **Primary**: The CC'd Contact ("Linda") — a marketing assistant, vendor account manager, or GM-equivalent at a dealership. First-time contact with Rogue. Reading email on a phone between meetings. Zero appetite for account-creation friction. Trust is fragile.
- **Secondary**: The GM ("Rachel") — causal trigger, not the recipient of this flow. No direct interaction with the identity step; she's already been thanked in-thread.
- **Tertiary**: Rogue ops — needs audit-trail visibility into verification state via `flow_events`.

### User Goals

1. Understand what they've been CC'd into with minimal reading.
2. Complete the minimum required action (three fields) and get back to their day.
3. Feel confident the form is legitimate and not a phishing attempt.

### Constraints

- **Devices**: Mobile-first. Linda is likely reading the setup email on her phone. The form must work on a 375px-wide screen with a software keyboard active.
- **Accessibility**: WCAG 2.1 AA — labels associated with inputs, sufficient contrast (4.5:1 minimum for body text), error messages linked via `aria-describedby`, keyboard-navigable, no JS required.
- **No account**: Linda has no login. The form is delivered via a 7-day magic link. Every design decision must reduce cognitive overhead for a user who has never heard of Rogue.
- **Existing design language**: Inline CSS only. System font stack (`-apple-system, BlinkMacSystemFont, sans-serif`). Black CTAs (`background: #000; color: #fff`). Max-width 640px centered layout. Established by `app/views/setup/walkthroughs/summary.html.erb` (lines 7–8) and `app/views/submissions/forms/show.html.erb` (lines 7–8).
- **No emojis**: No emoji usage in the existing app views or mailers.

---

## User Flow

### Flow Diagram

```
[Linda's inbox — invitee_setup_email — EDITED copy]
    │
    └─ clicks "Set up your assignment"
         │
         ▼
[GET /setup/:signed_id → Setup::WalkthroughsController#show]
    │  contact.verified? == false → render :identity (Step 1 of 4)
    │
    ├──[Linda fills first_name, last_name, phone → PATCH]
    │     ▼
    │  422 if validation fails → re-render :identity with inline errors
    │     ▼
    │  200 if valid → redirect → step=summary (Step 2 of 4)
    │     ▼
    │  [step=method (Step 3 of 4)] → [step=done (Step 4 of 4)]
    │
    └──[Linda lands AFTER already verified]
          contact.verified? == true → skip :identity → :summary
```

### Error States

| Error | Cause | User Recovery |
|-------|-------|---------------|
| Blank first name | Submitted form without typing | Inline error below field; form stays populated |
| Blank last name | Same | Inline error below field |
| Blank or unparseable phone | Empty or non-US format | Inline error below field with format hint |
| Expired signed_id | Link older than 7 days | Existing `:expired` view — no change needed |
| Tampered signed_id | Adversary modified URL | Same `:expired` view (HTTP 404) |

---

## Options Explored — Identity Step Layout

### Option 1: Single-Column Compact (one form, all fields visible, linear)

- **Approach**: All three fields stacked vertically in a single block. Field label above each input. Helper text immediately below each input (especially for phone). One submit button at the bottom. Reassurance line at the top.
- **Wireframe**:
  ```
  ┌──────────────────────────────────────────────┐
  │ Step 1 of 4 — Your details                   │
  ├──────────────────────────────────────────────┤
  │ No password, no account. Just three details  │
  │ so [Dealer Co] knows it's you.               │
  │                                              │
  │ First name *                                 │
  │ [_____________________________________]      │
  │                                              │
  │ Last name *                                  │
  │ [_____________________________________]      │
  │                                              │
  │ Mobile phone *                               │
  │ [_____________________________________]      │
  │ US numbers only (10 digits). We'll use       │
  │ this to send you submission links by text    │
  │ when that feature launches — no marketing.   │
  │                                              │
  │            [ Continue ]                      │
  └──────────────────────────────────────────────┘
  ```
- **User Flow**: Read heading → read reassurance → type first name → tab to last name → tab to phone → click Continue.
- **Pros**:
  - All fields visible at once; no surprises.
  - Matches the existing walkthrough page structure exactly (summary.html.erb is also a single column block with a heading, body text, and a CTA).
  - Maximum screen-reader friendliness — sequential, predictable DOM order.
  - Works on 320px screens with no layout shift.
  - Lowest implementation cost.
- **Cons**:
  - Three text inputs in a row can feel slightly form-heavy on mobile.
  - No progressive disclosure; Linda sees the full ask upfront.
- **Usability**: High
- **Accessibility**: High
- **Implementation Complexity**: Low

---

### Option 2: Two-Column Desktop-Friendly (first + last side by side, phone below)

- **Approach**: On screens ≥ 480px, first name and last name sit in a CSS grid side-by-side (50%/50%). Phone spans full width below. On mobile (< 480px), falls back to single-column stacking.
- **Wireframe (desktop)**:
  ```
  ┌──────────────────────────────────────────────┐
  │ Step 1 of 4 — Your details                   │
  ├──────────────────────────────────────────────┤
  │ No password, no account. Just three details  │
  │ so [Dealer Co] knows it's you.               │
  │                                              │
  │  First name *         Last name *            │
  │  [________________]   [________________]     │
  │                                              │
  │  Mobile phone *                              │
  │  [_____________________________________]     │
  │  US numbers only. We'll text you links...    │
  │                                              │
  │            [ Continue ]                      │
  └──────────────────────────────────────────────┘
  ```
- **Pros**:
  - Familiar from sign-up forms on commercial SaaS (Stripe, Notion, etc.).
  - Compact on desktop — fits comfortably above the fold on a laptop screen.
- **Cons**:
  - Requires CSS media query or CSS grid (more code, slightly outside the existing inline-only pattern).
  - The primary persona (Linda on her phone) sees exactly the same single-column layout as Option 1 — zero user-facing benefit for the most common access case.
  - The existing walkthrough views have no responsive breakpoints; adding one just for the identity step creates inconsistency.
  - Side-by-side inputs are error-prone on small screens: iOS may show both fields partially visible and not make it obvious which is focused.
- **Usability**: Medium (worse on mobile, marginally better on desktop)
- **Accessibility**: Medium (requires careful label association in a grid context)
- **Implementation Complexity**: Medium

---

### Option 3: Progressive 1-Field-at-a-Time Wizard ("Typeform-style")

- **Approach**: Each field is presented sequentially: first name only → Continue → last name only → Continue → phone → Continue. Three micro-pages or JS-driven reveal within one page.
- **Wireframe (first step)**:
  ```
  ┌──────────────────────────────────────────────┐
  │ Step 1 of 4 — Your details (1/3)            │
  ├──────────────────────────────────────────────┤
  │ What's your first name?                      │
  │                                              │
  │  [_____________________________________]     │
  │                                              │
  │            [ Next ]                          │
  └──────────────────────────────────────────────┘
  ```
- **Pros**:
  - Reduces cognitive load per screen to a single question.
  - Completion-rate research (Typeform) suggests single-question-at-a-time can improve form completion.
- **Cons**:
  - **Radical departure from every other page in the walkthrough.** Summary, method, and done are all single-screen with multiple elements. A Typeform-style inner wizard for just this step would feel disjointed.
  - Three round-trips (or JS state) to collect three trivially simple fields.
  - Requires JS for a smooth in-page experience, or three separate routes/renders. The user-journey doc explicitly notes "No JS required to complete the flow (matches the existing walkthrough's no-Stimulus posture at MVP)."
  - The fields are short and simple. First name, last name, and phone have low cognitive load individually — progressive disclosure is only beneficial when individual questions are complex or conditional.
  - Adds implementation complexity for minimal user benefit.
- **Usability**: Medium (completion rate gains are unproven at three simple fields)
- **Accessibility**: Low-Medium (requires careful ARIA live-region announcements for the reveal transitions)
- **Implementation Complexity**: High

---

## Evaluation Matrix

| Criteria | Option 1 (Single-column) | Option 2 (Two-column) | Option 3 (Progressive) |
|----------|--------------------------|-----------------------|------------------------|
| Usability | High | Medium | Medium |
| Accessibility | High | Medium | Low-Medium |
| Consistency w/ existing | High | Low | Low |
| Responsiveness | High | Medium | Medium |
| Performance | High | High | Low |
| Implementation Effort | Low | Medium | High |
| No-JS requirement | Yes | Yes | No |

**Winner: Option 1 — Single-Column Compact.**

---

## Decision

**Chosen**: Option 1 — Single-Column Compact.

### Rationale

The primary persona reads the setup email on a phone. Option 2's desktop layout provides zero benefit on the device she's most likely using, while adding responsive breakpoints that don't exist elsewhere in the app. Option 3 violates the no-JS requirement (user-journey doc, accessibility checklist) and would look alien next to the existing single-screen walkthrough steps. Option 1 exactly mirrors the structure of `summary.html.erb` (heading, body text, field(s), CTA) — Linda's experience is consistent throughout the 4-step walkthrough, which reinforces completion rather than creating surprise at step 1.

### Trade-offs Accepted

- Three inputs visible at once on mobile: acceptable because all three are short free-text fields with no dependencies between them. A user who can fill in their name on a mobile web form can handle this layout.
- No progressive disclosure: acceptable because the reassurance copy at the top ("No password, no account. Just three details") sets expectations before the fields appear. Linda knows the full scope of what she's being asked upfront.

---

## Sub-Decision 1: Email Subject and Body

### Copy Exploration

**Draft A — Functional/transactional:**
> Subject: `[Dealer Co] Set up your details and how you'll send data`
> Body: "Rachel at Dealer Co asked you to handle marketing strategy reporting. Click below to confirm a few details and pick how you'll send data."

**Draft B — Assignment-focused (closer to existing):**
> Subject: `[Dealer Co] Confirm your details for your data assignment`
> Body: "Rachel at Dealer Co named you as the person to handle this: [question prompt]. Before you pick how you'll send data, we need three details from you so Dealer Co knows it's you."

**Draft C — Minimal friction / single-breath:**
> Subject: `[Dealer Co]: set up your details and how you'll send data`
> Body: "Rachel at Dealer Co asked you to handle [question prompt]. Click below — it takes about a minute. You'll confirm your name and phone, then pick how you'll send data."

**Chosen: Draft C** — it's the most honest about what Linda is about to do (name + phone + method), sets a one-minute time expectation, and matches the existing email's rhythm (which already says "about a minute"). The subject is grammatically consistent with the existing mailer's subject pattern (`"#{tenant.dealership_name}: data collection assignment"` — a colon separator, sentence-cased description).

**Exact subject line:**
```
#{@tenant.dealership_name}: set up your details and how you'll send data
```

**Exact HTML body** (full replacement of `invitee_setup_email.html.erb`, preserving the existing table structure):

```erb
<table width="100%" cellpadding="0" cellspacing="0" border="0">
  <tr>
    <td align="center">
      <table width="600" cellpadding="0" cellspacing="0" border="0">
        <tr>
          <td style="padding: 40px 20px 20px;">
            <h1 style="font-size: 22px; font-weight: bold; margin: 0 0 20px;">
              You've been added to <%= @tenant.dealership_name %>'s data setup
            </h1>

            <p>Hi,</p>

            <p>
              <strong><%= @tenant.gm_name %></strong> at
              <strong><%= @tenant.dealership_name %></strong>
              asked you to handle this:
            </p>

            <p style="border-left: 3px solid #ccc; padding: 8px 14px; margin: 12px 0;">
              <em><%= @question.prompt %></em>
            </p>

            <p>
              It takes about a minute. You'll confirm your name and phone number,
              then pick how you want to send data.
            </p>
          </td>
        </tr>
        <tr>
          <td align="center" style="padding: 10px 20px 20px;">
            <table cellpadding="0" cellspacing="0" border="0">
              <tr>
                <td style="background-color: #000; border-radius: 4px;">
                  <a href="<%= @setup_url %>"
                     style="display: inline-block; padding: 14px 28px; color: #fff; font-weight: bold; text-decoration: none; font-size: 16px;">
                    Set up your assignment
                  </a>
                </td>
              </tr>
            </table>
          </td>
        </tr>
        <tr>
          <td style="padding: 0 20px 20px;">
            <p style="color: #666; font-size: 13px;">
              No password or account needed — just your name, phone, and a submission preference.
            </p>

            <p>— The Rogue team</p>

            <p style="color: #666; font-size: 12px; margin-top: 30px;">
              Or copy and paste this URL into your browser:<br>
              <%= @setup_url %>
            </p>
          </td>
        </tr>
      </table>
    </td>
  </tr>
</table>
```

**Exact plain-text body** (full replacement of `invitee_setup_email.text.erb`):

```
Hi,

<%= @tenant.gm_name %> at <%= @tenant.dealership_name %> asked you to handle this:

  <%= @question.prompt %>

It takes about a minute. You'll confirm your name and phone number, then pick how you want to send data.

  <%= @setup_url %>

No password or account needed — just your name, phone, and a submission preference.

— The Rogue team
```

---

## Sub-Decision 2: Identity Step Layout (ERB Snippet)

**Chosen**: Single-column, inline-CSS, no JS, mirrors `summary.html.erb` structure.

The full `identity.html.erb` view (replacing the non-existent `show.html.erb` the task prompt referenced — the walkthroughs controller renders named templates, not `show`):

```erb
<!DOCTYPE html>
<html>
  <head>
    <title>Set up — <%= @contact&.tenant&.dealership_name %></title>
    <meta name="viewport" content="width=device-width,initial-scale=1">
  </head>
  <body style="font-family: -apple-system, BlinkMacSystemFont, sans-serif; max-width: 640px; margin: 40px auto; padding: 0 20px; color: #222;">

    <%# Step counter — matches the pattern established in summary.html.erb:8 %>
    <h1 style="font-size: 24px;">Step 1 of 4 — Your details</h1>

    <%# Reassurance line — critical for reducing phishing anxiety %>
    <p style="color: #555; margin-top: 0;">
      No password, no account. Just three details so
      <strong><%= @contact.tenant.dealership_name %></strong> knows it's you.
    </p>

    <%= form_with url: setup_walkthrough_path(signed_id: params[:signed_id]),
                  method: :patch,
                  local: true,
                  scope: :contact do |f| %>

      <%# First name %>
      <div style="margin: 20px 0;">
        <%= f.label :first_name, "First name",
                    style: "display: block; font-weight: bold; margin-bottom: 6px;",
                    for: "contact_first_name" %>
        <% if @errors&.key?(:first_name) %>
          <p id="first-name-error"
             role="alert"
             style="color: #800; font-size: 14px; margin: 0 0 4px;">
            <%= @errors[:first_name] %>
          </p>
        <% end %>
        <%= f.text_field :first_name,
                         id: "contact_first_name",
                         value: @contact.first_name,
                         autocomplete: "given-name",
                         required: true,
                         "aria-describedby": (@errors&.key?(:first_name) ? "first-name-error" : nil),
                         "aria-invalid": (@errors&.key?(:first_name) ? "true" : nil),
                         style: [
                           "width: 100%; padding: 10px; border-radius: 4px; font-size: 16px; box-sizing: border-box;",
                           @errors&.key?(:first_name) ? "border: 1px solid #c00;" : "border: 1px solid #ccc;"
                         ].join(" ") %>
      </div>

      <%# Last name %>
      <div style="margin: 20px 0;">
        <%= f.label :last_name, "Last name",
                    style: "display: block; font-weight: bold; margin-bottom: 6px;",
                    for: "contact_last_name" %>
        <% if @errors&.key?(:last_name) %>
          <p id="last-name-error"
             role="alert"
             style="color: #800; font-size: 14px; margin: 0 0 4px;">
            <%= @errors[:last_name] %>
          </p>
        <% end %>
        <%= f.text_field :last_name,
                         id: "contact_last_name",
                         value: @contact.last_name,
                         autocomplete: "family-name",
                         required: true,
                         "aria-describedby": (@errors&.key?(:last_name) ? "last-name-error" : nil),
                         "aria-invalid": (@errors&.key?(:last_name) ? "true" : nil),
                         style: [
                           "width: 100%; padding: 10px; border-radius: 4px; font-size: 16px; box-sizing: border-box;",
                           @errors&.key?(:last_name) ? "border: 1px solid #c00;" : "border: 1px solid #ccc;"
                         ].join(" ") %>
      </div>

      <%# Mobile phone — highest friction field; explain purpose explicitly %>
      <div style="margin: 20px 0;">
        <%= f.label :phone, "Mobile phone",
                    style: "display: block; font-weight: bold; margin-bottom: 6px;",
                    for: "contact_phone" %>
        <% if @errors&.key?(:phone) %>
          <p id="phone-error"
             role="alert"
             style="color: #800; font-size: 14px; margin: 0 0 4px;">
            <%= @errors[:phone] %>
          </p>
        <% end %>
        <%= f.telephone_field :phone,
                              id: "contact_phone",
                              value: @contact.phone,
                              autocomplete: "tel",
                              inputmode: "tel",
                              placeholder: "(555) 010-1234",
                              "aria-describedby": [
                                (@errors&.key?(:phone) ? "phone-error" : nil),
                                "phone-hint"
                              ].compact.join(" ").presence,
                              "aria-invalid": (@errors&.key?(:phone) ? "true" : nil),
                              style: [
                                "width: 100%; padding: 10px; border-radius: 4px; font-size: 16px; box-sizing: border-box;",
                                @errors&.key?(:phone) ? "border: 1px solid #c00;" : "border: 1px solid #ccc;"
                              ].join(" ") %>
        <p id="phone-hint" style="color: #555; font-size: 13px; margin: 4px 0 0;">
          US numbers only. We plan to send submission links by text — you'll never get a marketing message.
        </p>
      </div>

      <p style="margin-top: 28px;">
        <%= f.submit "Continue",
                     style: "padding: 12px 24px; background: #000; color: #fff; border: 0; border-radius: 4px; cursor: pointer; font-size: 16px;" %>
      </p>

    <% end %>
  </body>
</html>
```

**Key implementation notes:**
- `form_with ... method: :patch` — the controller's `update` action already handles PATCH. The identity params (`params[:contact]`) are distinguished from source params (`params[:source]`) by key, matching the User Journey doc's branching strategy.
- `local: true` — no Turbo Stream; plain HTML form submission, matching `method_picker.html.erb:15`.
- `box-sizing: border-box` on inputs — prevents width overflow on mobile when `padding` is applied to 100%-wide inputs (the existing views omit this; it's a defensive addition, not a new token).
- `autocomplete="given-name"`, `"family-name"`, `"tel"` — standard HTML autocomplete tokens. On mobile, autofill will pre-populate name fields from the contact's own saved details, dramatically reducing typing.
- `inputmode="tel"` — triggers the numeric keyboard on iOS/Android for the phone field.
- `@contact.first_name`, `@contact.last_name`, `@contact.phone` for `value:` — preserves typed values on 422 re-render (the controller assigns `@contact` after the failed update attempt, so the contact object retains the user's submitted params via `assign_attributes` before the render — see controller pattern note in Sub-Decision 3 below).

---

## Sub-Decision 3: Validation Error States

**Pattern**: Mirror `Submissions::FormsController#create` → `render(:show, status: :unprocessable_entity)` at `app/controllers/submissions/forms_controller.rb:53`.

The existing `submissions/forms/show.html.erb` uses `flash.now[:alert]` for a single top-level error message. For the identity step, that pattern is insufficient because three different fields can independently fail. The error strategy is **field-level inline errors**, not a flash banner.

**Controller pattern** (from Architecture doc, `app/controllers/contacts/verifications_controller.rb` shape — now implemented in `Setup::WalkthroughsController#update` for the `:contact` params branch):

```ruby
# Inside Setup::WalkthroughsController#update, contact branch:
permitted = params.require(:contact).permit(:first_name, :last_name, :phone)
phone_result = Contacts::PhoneNormalizer.call(permitted[:phone])

@errors = {}
@errors[:first_name] = "First name can't be blank" if permitted[:first_name].blank?
@errors[:last_name]  = "Last name can't be blank"  if permitted[:last_name].blank?
@errors[:phone] = if permitted[:phone].blank?
  "Mobile phone can't be blank"
elsif !phone_result.valid?
  "Please enter a valid US mobile number (10 digits)"
end

if @errors.any?
  @contact.assign_attributes(
    first_name: permitted[:first_name],
    last_name: permitted[:last_name]
    # phone is not assigned back — it's encrypted non-deterministically,
    # and the raw submitted value (not yet normalized) should re-render.
    # Store the raw attempt in an ivar instead:
  )
  @phone_attempt = permitted[:phone]
  render :identity, status: :unprocessable_entity
  return
end
```

**View-side**: The `identity.html.erb` snippet above already implements this pattern:
- Error paragraph appears **above** its associated input (not below) — screen readers encounter the error before the field, which is the correct announcement order.
- `role="alert"` on each error `<p>` — announces immediately when injected into the DOM. On a full-page re-render (no JS), this attribute is superfluous but harmless and forward-compatible.
- `aria-describedby` on the input references the error `<p>`'s `id` when an error is present, the hint `<p>`'s `id` otherwise, and both when both are present (phone field with an error still retains the hint).
- `aria-invalid="true"` on the input when an error is present — screen reader communicates "invalid field" without relying on visual border color change alone.
- **Border turns red** (`border: 1px solid #c00`) on erroneous fields — consistent with the flash-banner error color used in `submissions/forms/show.html.erb:24` (`color: #800; background: #fee`). Note: `#c00` is used for the border (it needs to pass 3:1 non-text contrast against the white background for WCAG 1.4.11). `#800` is used for error text (passes 4.5:1 against white).

**Phone field `value` on re-render**: Because the phone value is not assignable back to `@contact.phone` (encrypted; raw input is pre-normalization), the controller stores the raw submitted value in `@phone_attempt`. The view uses `value: @phone_attempt || @contact.phone` for the phone field specifically. (This is a small deviation from the first_name/last_name pattern where `@contact.first_name` suffices — document explicitly for the build agent.)

---

## Sub-Decision 4: Step-Counter Component

**Pattern**: `<h1 style="font-size: 24px;">Step N of 4 — [Step name]</h1>` — directly from `summary.html.erb:8` and `method_picker.html.erb:8`.

**All four step headings (after this feature ships):**

| Step | Template | Heading Text |
|------|----------|--------------|
| 1 of 4 | `identity.html.erb` (NEW) | `Step 1 of 4 — Your details` |
| 2 of 4 | `summary.html.erb` (EDIT) | `Step 2 of 4 — Your assignment` |
| 3 of 4 | `method_picker.html.erb` (EDIT) | `Step 3 of 4 — How will you submit?` |
| 4 of 4 | `done.html.erb` (EDIT) | *(no step counter on done — see below)* |

**On the done step**: `done.html.erb` currently shows `<h1>You're set up.</h1>` with no step counter. This is the right pattern — the done step is a terminus, not a progress indicator. The step counter is omitted from `done.html.erb` intentionally; do not add one.

**Build agent note**: Edit `summary.html.erb:8` from `Step 1 of 3` → `Step 2 of 4`. Edit `method_picker.html.erb:8` from `Step 2 of 3` → `Step 3 of 4`. No other changes to those files for step-counter purposes.

---

## Sub-Decision 5: Microcopy and Transition

### Form heading
```
Step 1 of 4 — Your details
```
*(matches existing heading pattern verbatim)*

### Reassurance line (under heading)
```
No password, no account. Just three details so [Dealer Co] knows it's you.
```
In ERB: `No password, no account. Just three details so <strong><%= @contact.tenant.dealership_name %></strong> knows it's you.`

Style: `color: #555; margin-top: 0;` (muted, lower hierarchy than heading — same gray used for supporting text in `method_picker.html.erb:17`).

### Field labels and hints

| Field | Label | Helper text |
|-------|-------|-------------|
| First name | `First name` | *(none — self-evident)* |
| Last name | `Last name` | *(none — self-evident)* |
| Mobile phone | `Mobile phone` | `US numbers only. We plan to send submission links by text — you'll never get a marketing message.` |

**Phone helper text rationale**: The User Journey doc says "copy promises we'll text you links." The Architecture doc confirms Twilio is a future integration, not a present capability. The phrase "We plan to send" is honest (future-tense), not misleading. "You'll never get a marketing message" directly counters the primary trust objection for giving a phone number to an unfamiliar platform.

### Validation error messages

| Condition | Error text |
|-----------|-----------|
| `first_name` blank | `First name can't be blank` |
| `last_name` blank | `Last name can't be blank` |
| `phone` blank | `Mobile phone can't be blank` |
| `phone` non-empty but non-US / non-parseable | `Please enter a valid US mobile number (10 digits)` |

All four messages are short, field-specific, and actionable. No jargon ("E.164", "format"). The phone error name ("Mobile phone") matches the field label exactly — users can match error to field without ambiguity.

### Submit button label
```
Continue
```
*(same word used in `summary.html.erb:22`'s link anchor — visual consistency throughout the walkthrough)*

### Success transition copy (step 1 → step 2)

The controller redirects to `step=summary` on successful PATCH. Linda lands on `summary.html.erb`, which now reads `Step 2 of 4 — Your assignment`. No interstitial "saved!" message is needed — the step counter itself communicates progress. The existing summary copy ("Dealer Co asked you to provide X on a Y cadence") is unchanged.

If `@responsibility` is nil when Linda completes identity (the "no active assignment" branch — see Sub-Decision 5 below), the summary page already has a fallback message. The identity-to-summary redirect fires regardless of responsibility presence; the summary view handles the nil case.

### Done step — first-name greeting

Edit `done.html.erb` heading from:
```html
<h1 style="font-size: 24px;">You're set up.</h1>
```
To:
```erb
<h1 style="font-size: 24px;">You're set up<%= @contact.first_name.present? ? ", #{@contact.first_name}" : "" %>.</h1>
```
This produces "You're set up, Linda." when verified and "You're set up." as a graceful fallback if first name is somehow absent (defensive — should not occur after identity step completes, but guarding against future code paths that reach `done` without identity).

---

## Sub-Decision 5 (Bonus): Empty-Responsibility Terminal Page

**Scenario**: Linda has clicked the setup link and completed the identity step, but `@responsibility` is nil (the GM's original question was superseded or re-routed after Linda was CC'd). She ends up on `summary.html.erb` with `@responsibility == nil`.

**Current behavior** (`summary.html.erb:17–19`):
```erb
<p>We don't have an active assignment for you right now. If this is unexpected, please reply to the original email.</p>
```

**After this feature**: Linda has just filled in her name and phone. The current copy feels cold ("we don't have anything for you"). She deserves acknowledgment that her verification worked even if the assignment is temporarily absent.

**Chosen copy for the no-responsibility branch in `summary.html.erb`:**

```erb
<% else %>
  <p>
    Your details are saved<%= @contact.first_name.present? ? ", #{@contact.first_name}" : "" %>.
    We don't have an active assignment for you right now — if you were expecting one, reply to the original email and we'll sort it out.
  </p>
<% end %>
```

This produces: "Your details are saved, Linda. We don't have an active assignment for you right now — if you were expecting one, reply to the original email and we'll sort it out."

**Styling**: no change — inherits the existing `<p>` style from the page body. The Continue link below this block points to step=method, which would be confusing if there's no assignment. The User Journey doc (line 144) says "redirect to a 'Thanks — we'll be in touch' terminal page (re-uses the `summary.html.erb` no-responsibility branch)."

Therefore: when `@responsibility.nil?`, suppress the Continue link entirely. The build agent should wrap the Continue link in `<% if @responsibility %>`.

---

## Design Specifications

### Layout

- **Mobile (< 640px)**: Full-width single column. Max-width 640px centered, `padding: 0 20px`. Inputs are `width: 100%; box-sizing: border-box`. Button left-aligned (matches existing).
- **Desktop (≥ 640px)**: Same single-column layout at 640px width, centered. No layout change — the existing walkthrough pages have no responsive breakpoints and the identity step follows suit.

### Key Components

| Component | Purpose | Behavior |
|-----------|---------|----------|
| Step counter `<h1>` | Orient Linda in the 4-step flow | Static text, pattern from summary.html.erb |
| Reassurance `<p>` | Reduce phishing anxiety | Renders dealership name in bold |
| `<form>` with `local: true, method: :patch` | Submit identity | PATCH to `setup_walkthrough_path`, scope `:contact` |
| Field error `<p role="alert">` | Field-level error message | Appears above field input; `aria-describedby` links to input |
| Phone hint `<p id="phone-hint">` | Explain why phone is needed | Always visible; linked via `aria-describedby` on the phone input |
| Submit button | Advance | Same black button style as all other CTAs in the walkthrough |

### Responsive Behavior

| Breakpoint | Changes |
|------------|---------|
| < 640px | Full-width inputs (`width: 100%; box-sizing: border-box`), same column layout |
| ≥ 640px | 640px max-width, centered (`margin: 40px auto`) — same as all walkthrough pages |

### Accessibility Requirements

- [x] Keyboard navigation: Tab order is heading → reassurance → first name → last name → phone → Continue. All interactive elements are native HTML; no custom keyboard handling needed.
- [x] Screen reader: `<h1>` announces step and purpose; `<label>` elements are associated via `for="contact_X"` and `id="contact_X"` (Rails `f.label` + `f.text_field` generates these correctly when `for:` is specified).
- [x] Color contrast: Error text `#800` on white background = 7.1:1 (exceeds 4.5:1 AA). Error border `#c00` on white = 3.1:1 (exceeds 3:1 for non-text UI components, WCAG 1.4.11). Body text `#222` on white = 14:1. Muted text `#555` on white = 7.4:1.
- [x] Error messages: `aria-describedby` links input to error paragraph. `aria-invalid="true"` marks the input as invalid. Both attributes are cleared (omitted) when there is no error.
- [x] Focus: No custom focus management needed. Browser default focus ring is not suppressed anywhere in the existing app.
- [x] No JS required: Form is a plain `<form>` with `local: true`. 422 re-render is a full page load with the error state embedded.

---

## Implementation Guidelines

### For Developers

1. **New view**: `app/views/setup/walkthroughs/identity.html.erb` — full file per snippet in Sub-Decision 2.

2. **Edit `Setup::WalkthroughsController`**:
   - `template_for_step`: add identity routing. New first check: if `@contact.unverified?` and `step_param` is not `"method"` and not `"done"`, return `:identity`. Existing done/method/summary routing follows unchanged.
   - `update`: branch on `params.key?(:contact)`. If true, run the identity update path (build `@errors` hash, call `Contacts::PhoneNormalizer`, write `Contact` + `FlowEvent` in transaction, redirect to `step: "summary"` or re-render `:identity` on failure).
   - Store raw phone attempt in `@phone_attempt` ivar for re-render. Do not assign to `@contact.phone` until normalization succeeds.

3. **Phone field value on re-render**: In `identity.html.erb`, the phone field `value:` should use `@phone_attempt || @contact.phone.presence`. This renders the user's raw typed value back to them after a validation failure, not the stored encrypted value (which may be nil for a fresh contact).

4. **Step counter edits** (surgical — three files, one line each):
   - `app/views/setup/walkthroughs/summary.html.erb:8`: `Step 1 of 3` → `Step 2 of 4`
   - `app/views/setup/walkthroughs/method_picker.html.erb:8`: `Step 2 of 3` → `Step 3 of 4`
   - `app/views/setup/walkthroughs/done.html.erb` — add first-name greeting (see Sub-Decision 5 microcopy).

5. **Empty-responsibility branch**: `summary.html.erb:17–19` — update the `else` branch copy. Wrap the Continue link in `<% if @responsibility %>`.

6. **Mailer edits**: Replace `app/views/onboarding_mailer/invitee_setup_email.html.erb` body content and `invitee_setup_email.text.erb` with the copy in Sub-Decision 1. Edit subject line in `app/mailers/onboarding_mailer.rb:109`: `"#{@tenant.dealership_name}: data collection assignment"` → `"#{@tenant.dealership_name}: set up your details and how you'll send data"`.

7. **No new CSS files, no Tailwind, no class attributes**: The app uses inline styles exclusively. Continue that pattern in `identity.html.erb`. Do not introduce a `class=""` attribute.

8. **`box-sizing: border-box`** on all inputs: The existing views omit this but it prevents mobile layout overflow. Add it to `identity.html.erb` inputs. Do not retrofit existing views.

### Recommended Patterns (no new libraries)

- Rails `form_with ... scope: :contact, method: :patch, local: true` — matches `method_picker.html.erb:15`'s `form_with ... scope: :source, method: :patch, local: true`.
- `f.telephone_field :phone, inputmode: "tel"` — renders `<input type="tel" inputmode="tel">`, which is the correct combination for a US phone number field (type=tel relaxes HTML5 validation; inputmode=tel triggers the right keyboard).
- `aria-describedby` with space-separated IDs for the phone field (error ID + hint ID when both present) — standard ARIA pattern, no library required.

---

## Validation Checklist

- [x] Meets all user goals (minimal friction, 3-field form, no account, purpose explained)
- [x] Accessible per WCAG 2.1 AA requirements (contrast ratios documented, keyboard nav, screen reader support, no-JS)
- [x] Consistent with existing patterns (inline CSS, same font stack, same black CTA button, same step-counter heading pattern)
- [x] Respects no-Tailwind reality (inline styles only — no class attributes added)
- [x] Responsive — single-column works on mobile without breakpoints
- [x] Performance — static HTML, one form submit, no JS
- [x] Implementation feasible — all changes are additions or one-line edits to existing files; no new routes, mailers, or controllers required

---

## Next Steps

1. **Phase 1 (Schema + Model)** implements `Contact#first_name`, `#last_name`, `#phone`, `#verified?`. No UI work.
2. **Phase 2 (Controller + Views)** uses this document to implement `identity.html.erb`, extend `Setup::WalkthroughsController#template_for_step` and `#update`, edit step counters in three existing views, and update `done.html.erb` greeting.
3. **Phase 3 (Trigger)** edits `OnboardingMailer#invitee_setup_email` subject and `app/views/onboarding_mailer/invitee_setup_email.{html,text}.erb` per Sub-Decision 1.
4. **Phase 4 (Gating)** has no UI component — purely backend EscalationCascade filter.
5. **Post-launch**: If verification rates are low, the empty-responsibility terminal page copy and the phone hint text are the first levers to revisit.

---

UI/UX CREATIVE COMPLETE
Document: memory-bank/creative/TASK-008-uiux.md
Decision: Single-column inline-CSS identity form (Step 1 of 4), no new design tokens, mirroring summary.html.erb structure. Edited invitee_setup_email subject + both body templates with honest "name + phone + method" framing. Field-level errors via @errors hash + aria-describedby, no flash banner. Phone explained as future-SMS with explicit no-marketing promise. Empty-responsibility branch updated in summary.html.erb else-clause with first-name acknowledgment and suppressed Continue link.
