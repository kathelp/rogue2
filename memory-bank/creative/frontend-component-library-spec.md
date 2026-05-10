# Rogue — Frontend Component Library Specification

> **Audience for this document**: a designer or design-generation tool (e.g., Claude Design) producing the first visual design for the Rogue web UI. The spec defines *what we are designing, for whom, with what voice, and within what constraints*. It does not prescribe pixel-exact layouts — those are the design output.
>
> **Status of the project today**: a Rails 8 monolith with three minimal, inline-styled web surfaces (a read-only accountability dashboard, a single-purpose submission form, and link-expired pages). Tailwind is not yet installed. This spec is the brief for the first real visual pass that establishes the platform's design language.

---

## 1. Product Context

Rogue is a **multi-tenant data-collection and standardization platform for automotive dealerships**. Dealers (rooftops) define what data they need, from whom, and on what cadence; Rogue collects it through frictionless no-login submission paths and normalizes it into per-domain canonical schemas.

The MVP focuses on the marketing domain: lead ingestion via ADF-XML email + raw HTTP POST, plus recurring metric submissions (form, CSV, API) from internal staff and third-party vendors.

**The product's defining bet** is that GMs and submitters are saturated with apps but fluent in email. Email is the primary interaction surface. The web UI is a *complement to email*, not a replacement for it: web pages exist to handle moments where richer interaction beats a reply-by-email (filling in a number, configuring a source, drilling into a dashboard), and they always arrive via a magic link from an email — never through a login screen.

This shapes everything about the design language:

- **Web pages are single-purpose, arrived-at, and disposable.** The user clicked a link in an email five seconds ago. They have one task. We must not make them figure out navigation, accounts, or hierarchy.
- **The web aesthetic should feel continuous with email** — calm, typographic, low-chrome, no marketing flourish.
- **Trust is more important than delight.** This is B2B accountability software for an industry that has been burned by flashy SaaS that didn't deliver. Design to *reduce skepticism*, not to wow.

---

## 2. Personas Who See These Surfaces

The component library has to serve four distinct readers. Each one arrives with different assumptions and stays for different lengths of time.

**The General Manager (GM).** Mid-50s, runs a dealership rooftop, lives in email and on the phone. Reads on an iPhone between meetings. Will skim, not read. Wants to know *who is on top of what, and what's slipping*. Visits the web dashboard maybe once a month, when something in the weekly digest catches their eye. Does not want to learn a new tool — every web visit must answer a question in under 30 seconds.

**The Internal Submitter** (e.g., the dealership's marketing coordinator). Younger, comfortable with web apps, but not invested in Rogue. Lands on a magic-link form, types a number, hits submit, closes the tab. Their entire experience of the product is one page, used once a month for 90 seconds. The form must feel obvious, fast, and forgiving (don't lose their input on a validation error, don't make them re-read instructions).

**The Vendor User** (e.g., a marketing-agency rep covering 30 rooftops). Power user. Submits across many tenants. Will eventually want richer multi-rooftop views. Today, behaves like an Internal Submitter but at higher volume. Same single-purpose page, just visited more often. Their longer-term needs (dashboards filtered to their assignments) inform the dashboard component design but not the MVP entry point.

**Rogue Staff (internal admin).** Operates the platform day-to-day: seeds tenants, monitors deliverability, watches for adapter failures. Will eventually have a fuller admin console. Out of scope for this first design pass *except* insofar as the component library should be reusable for it later.

> **Design priority order** (when components must trade off): GM > Internal Submitter > Vendor User > Rogue Staff.

---

## 3. Design Principles

These are non-negotiable. Every component decision must visibly honor at least one; none may contradict any.

1. **Single task per page.** Every web surface answers exactly one question or accepts exactly one input. No global navigation. No sidebars. No "while you're here, also do X." If a page needs a second action, that's a sign the flow is wrong, not that the page needs more chrome.

2. **Email-first, web-as-affordance.** The web design must feel like the email did: same voice, same restraint, same trust signals. A user who has been in their inbox five seconds before should not feel like they walked into a different product.

3. **Status is the headline.** The accountability dashboard exists so a GM can answer "what's slipping?" in one glance. Status — color, weight, position — is the most important information on every page that has any. Names and dates are secondary; descriptive prose is tertiary.

4. **Trust through restraint.** No gradients, no glassmorphism, no animated illustrations, no emoji as decoration. One brand color, used sparingly. Generous whitespace. Quiet borders. The product earns trust by looking calm and competent — like a financial statement, not like a consumer app.

5. **Mobile-first, even though the dashboard is dense.** GMs read on phones. Tables must collapse gracefully into stacked rows. Forms must work with fat thumbs. Touch targets ≥44px. Every page must look good at 360px wide before it looks good at 1440px.

6. **Forgiving inputs.** A submitter typing a number on a flaky connection cannot lose their work. Validation runs on submit, errors are inline + preserved, the field keeps the value the user typed (not the parsed value). Magic links are reusable until expiry — landing on the same page twice is a non-event, not an error.

7. **Honest empty states.** When there is no data yet ("no responsibilities configured", "no submissions on file"), the empty state explains *why* and what will change it ("once your team starts answering onboarding questions, they'll appear here") — never a generic "Nothing here yet" with a sad icon.

---

## 4. Visual Language

### 4.1 Color Palette

The palette is **monochrome plus four semantic accents**. No decorative color. No second brand color.

**Foundation — neutrals (warm-leaning grays):**

| Token | Hex | Usage |
|-------|-----|-------|
| `ink` | `#0F172A` | Primary text, headings, dark surfaces |
| `ink-muted` | `#334155` | Secondary text |
| `ink-subtle` | `#64748B` | Tertiary text, captions, helper text, table column headers |
| `paper` | `#FFFFFF` | Default page surface |
| `paper-warm` | `#F8FAFC` | Alternate surface (zebra rows, panel backgrounds) |
| `border` | `#E2E8F0` | Default borders, divider lines |
| `border-strong` | `#CBD5E1` | Borders on interactive elements (input outlines), focus halo base |

**Brand — single accent:**

| Token | Hex | Usage |
|-------|-----|-------|
| `brand` | `#1E40AF` | Primary action buttons, magic-link buttons, focus rings, brand wordmark |
| `brand-hover` | `#1E3A8A` | Hover state of `brand` |
| `brand-tint` | `#EFF6FF` | Brand-tinted surface (e.g., subtle banner bg, selected row bg) |

> Why `#1E40AF` (Tailwind blue-800)? It is dark enough to feel substantial against `paper`, distinct enough from the semantic blues used elsewhere on the web that it reads as "Rogue's blue", and gives strong WCAG AAA contrast against white for body text or button labels.

**Semantic — status accents:**

These map directly to the existing `AccountabilityHelper::STATUS_BADGES` model. The color tokens here are the *design-system version* of those colors, tuned for both screen and email. They must be visually distinguishable from `brand`.

| Status meaning | Token | Hex (bg / fg) | Maps to |
|---------------|-------|---------------|---------|
| Healthy / on time | `status-success` | `#DCFCE7` / `#14532D` | `on_time` |
| Awaiting / not yet actionable | `status-neutral` | `#F1F5F9` / `#334155` | `pending_setup`, `pending_first_submission` |
| Caution / due soon / late | `status-warning` | `#FEF3C7` / `#78350F` | `late`, `due_soon` (escalation) |
| Failure / overdue / blocked | `status-danger` | `#FEE2E2` / `#991B1B` | `overdue`, `fallback_fanout`, `gm_nudge` |

Each status pair must achieve **≥4.5:1 contrast** between bg and fg. The fg color is also the color of any associated icon. Statuses are never communicated by color alone (see §10 Accessibility).

> The pairs above are deliberately *softer* than Tailwind's default 100/800 pairs — Rogue's surfaces should feel like a printed report, not a dashboard. If Claude Design wants to nudge these for visual harmony with the chosen brand blue, that is welcome, provided contrast and the four-bucket structure are preserved.

### 4.2 Typography

**Type stack:** `Inter, ui-sans-serif, system-ui, -apple-system, "Segoe UI", Roboto, "Helvetica Neue", Arial, sans-serif`.

Inter loaded as a self-hosted variable font (one weight axis, range 400–700). System stack as fallback so first paint is instant on mailer-arriving traffic.

**Scale** (mobile / desktop pairs; line-height in parentheses):

| Token | Size | Use |
|-------|------|-----|
| `display` | 28px / 32px (1.15) | Page H1 only — the headline of a single-purpose page |
| `title` | 22px / 24px (1.25) | Card and section headings |
| `subtitle` | 18px / 18px (1.4) | Subordinate headings; row primary text in dense tables |
| `body` | 15px / 16px (1.55) | Default body copy; default form input text |
| `small` | 13px / 14px (1.5) | Helper text, captions, table data when density matters |
| `micro` | 11px / 12px (1.4) | Status badge labels, table column headers (uppercase, tracked) |

**Weights used:** 400 (body), 500 (table column headers, badge labels, secondary buttons), 600 (titles, primary buttons, status badges), 700 reserved for the page H1 only.

**Tabular numerals:** every numeric display (status counts, dates, submitted values, table cells with numbers) uses `font-variant-numeric: tabular-nums`. Numbers that align in columns must visibly align.

### 4.3 Spacing & Sizing

**Spacing scale** (use only these): `0 / 4 / 8 / 12 / 16 / 20 / 24 / 32 / 40 / 56 / 80` px. (Tailwind `0 / 1 / 2 / 3 / 4 / 5 / 6 / 8 / 10 / 14 / 20`.)

**Page max-widths:**
- Single-purpose form / confirmation page: `640px` (`max-w-2xl`)
- Read-only dashboard / data-table page: `960px` (`max-w-5xl`)
- Future admin / multi-tenant view: `1200px` (`max-w-6xl`)

**Vertical rhythm:** the page H1 sits `40px` below the top of the content area (mobile) / `56px` (desktop). Sections separate by `40px`. Paragraphs separate by `12px`.

**Touch targets:** every interactive element ≥`44 × 44`px on mobile.

### 4.4 Radii, Borders, Shadows

- **Radii:** only two — `4px` (inputs, buttons, table cells if rounded at all) and `999px` (status badges and avatar placeholders). No `8px`, no `16px`, no `24px`. Cards have square corners with a 1px border, *not* rounded panels.
- **Borders:** 1px, color from the neutral palette. No 2px borders. No double borders.
- **Shadows:** at most one elevation level system-wide: a subtle `0 1px 2px rgba(15, 23, 42, 0.06)` on cards that need to detach from the page. Most surfaces use a 1px border instead of a shadow. **No shadows on buttons.** No glow/halo effects except the focus ring (§10).

### 4.5 Iconography

- **Library:** Heroicons (outline by default, solid only inside filled buttons or status pills).
- **Size:** match adjacent text size; align vertically to text mid-height.
- **Color:** inherits `currentColor`. Status badges' icons inherit the badge's `fg`.
- Icons are *redundant with* text labels, never replacements. (Single iconographic affordance permitted: the close `×` on a banner.)

---

## 5. Component Inventory

For each component below: **Purpose** (when to use), **Anatomy** (parts), **States** (interactive states), **Variants** (named alternates), **Accessibility** (key requirements). Visual specifics derive from §4.

### 5.1 Button

**Purpose.** Trigger a single action. Primary button per page is reserved for the *one* action that completes the page's task ("Submit", "Confirm", "Save").

**Anatomy.** Label (required) + optional leading icon. No trailing icons (no caret, no arrow — the button is not a menu, not a navigation).

**States.** Default, hover, active (pressed), focus-visible (2px brand-colored ring offset 2px from button edge), disabled (50% opacity, `cursor: not-allowed`, no hover effect), loading (label replaced by spinner + "Submitting…", button disabled).

**Variants.**
- **Primary**: filled, `brand` background, white label, weight 600. One per page.
- **Secondary**: outlined, `border-strong` border, `ink` label, weight 500. Used for "Back", "Cancel", "Edit".
- **Ghost / link-style**: no border or fill, `brand` label, weight 500, underlined on hover. Used inside long body copy for actions that are textually "Reply to your most recent email" (which links back to email).
- **Destructive** (rare; reserved for future admin tooling): `status-danger` background, white label.

**Sizes.** Two: `default` (40px tall, 16px horizontal padding) and `large` (52px tall, 20px horizontal padding) — large is the default on mobile single-purpose pages.

**Accessibility.** Always a `<button>` for actions, `<a>` for navigation. Disabled state must include `aria-disabled="true"` when state is conveyed visually but the element remains focusable.

### 5.2 Form Inputs

**Common anatomy.** Label (always above input, weight 500, size `body`) → input → optional helper text (size `small`, color `ink-subtle`) → optional inline error (size `small`, color `status-danger` fg).

**Common states.** Default, focus (2px brand ring, no border color change), error (1px `status-danger` fg border + inline error message), disabled (paper-warm bg, `ink-subtle` text), readonly (paper-warm bg, `ink` text, no border-color change on focus).

**Components in this family:**

- **Text input** (`<input type="text">`). 44px tall on mobile / 40px desktop. Padding `10px 12px`. Border `border-strong`.
- **Number input** (`<input type="number">`). Same as text input. Tabular-nums. `inputmode="decimal"` on mobile so the numeric keypad opens. Default `min="0"`. **No spin buttons** (`appearance: none`) — the up/down chrome adds noise without value.
- **Textarea**. Same border/padding. Default 4 rows, resize vertical only.
- **Select**. Native `<select>` styled to match text input — no custom dropdown menu in MVP (custom dropdowns are an accessibility hazard and unnecessary for the data we collect).
- **File upload** (used for CSV uploads in source onboarding, future). Drag-and-drop drop zone with `border-strong` dashed border, 80px min-height, with a centered "Choose a file or drag it here" prompt. On hover/dragover: `brand-tint` background.
- **Checkbox / radio**. Native, with custom styles applied via `accent-color: brand`. Label sits to the right. Whole label is clickable.

**Validation behavior.** Server-side on submit; client-side only as progressive enhancement (HTML5 `required`, `min`, `pattern`). On submit failure: re-render the form with the user's typed values preserved, error messages inline beside the offending fields, and a summary banner (§5.5) at the top of the form listing the fields with errors as anchor links to those fields.

**Accessibility.** Label `for` attribute matches input `id`. Errors associated via `aria-describedby`. Error fields get `aria-invalid="true"`. Required fields use `aria-required` not just visual asterisk.

### 5.3 Status Badge

**Purpose.** Communicate the state of a responsibility, submission, or escalation in one tight visual unit.

**Anatomy.** Pill-shaped container (radius 999px), 2px vertical padding / 10px horizontal padding, `micro` size text, weight 600, optional 12×12px leading icon (Heroicon solid).

**Variants.** Five — one per semantic bucket plus a generic fallback. Each pairs a bg + fg from the §4.1 status palette.

| Variant | Default label | Icon |
|---------|--------------|------|
| `success` | "On time" | `check-circle` |
| `neutral` | "Awaiting setup" / "Pending first submission" | `clock` |
| `warning` | "Late" / "Due soon" | `exclamation-triangle` |
| `danger` | "Overdue" / "Escalated" | `exclamation-circle` |
| `default` (fallback) | the literal status string, hyphens-to-spaces, capitalized | none |

**Mapping to Rogue's status enum:** `on_time → success`, `pending_setup → neutral`, `pending_first_submission → neutral`, `late → warning`, `due_soon → warning`, `overdue → danger`, `fallback_fanout → danger`, `gm_nudge → danger`.

**States.** Static — badges do not have hover or focus states. They are never interactive elements.

**Accessibility.** The text label *is* the source of truth — color is decoration. Screen readers announce the label. Icon has `aria-hidden="true"`.

### 5.4 Data Table

**Purpose.** Display a list of responsibilities, submissions, or other tabular data on the read-only dashboard. The first table in the system is the GM's accountability table (Responsibility / Owner / Status / Next Due).

**Anatomy.**
- Column headers: `micro` size, uppercase, letter-spacing `0.05em`, color `ink-subtle`, weight 500. Bottom-bordered (1px `border` color).
- Rows: 1px top border between rows. No row hover background unless rows are clickable (today they aren't).
- Cells: `12px 16px` padding. Default left-aligned. Numeric and date columns right-aligned.
- First column ("Responsibility" or equivalent) carries the row's primary identity: `body` size, weight 500, color `ink`.
- Other columns: `body` size, weight 400, color `ink-muted`.

**Mobile collapse (≤640px).** Each row becomes a stacked card with two-line layout:
- Line 1: primary identity (left) + status badge (right)
- Line 2: secondary metadata as a single line of `small` text — "Owner • Next due: …"
The header row is hidden on mobile.

**Empty state.** A single centered paragraph (size `body`, color `ink-muted`) explaining why the table is empty and what will populate it. *No* generic "No data" with an icon. See §5.7 for the empty-state component pattern.

**Sortable headers** (future, not MVP). When implemented: header gains a sort caret to its right and is keyboard-focusable.

**Accessibility.** Always a real `<table>` with `<thead>` and `<tbody>` — the mobile collapse is a CSS transformation only; the underlying markup remains tabular for screen readers.

### 5.5 Banner / Alert

**Purpose.** Communicate page-level status above the main content. Used for: form-submit errors ("Please fix the highlighted fields below"), success confirmations after a destructive-but-undoable action (none currently exist), and informational notes ("Dashboard links are valid for 8 days").

**Anatomy.** Full-width strip inside the page content area. Tinted background per variant, 1px border in matching `fg` color, leading icon, body text, optional close `×` button.

**Variants.** `info` (`brand-tint` bg, `brand` fg/icon), `success`, `warning`, `danger` — using the same color tokens as status badges.

**States.** Static unless dismissible. Dismissible banners have a close button (top-right, `ink-subtle` color, hover to `ink`).

**Accessibility.** Use `role="status"` for info/success, `role="alert"` for errors/warnings that follow form submission. Live-region behavior so screen readers announce on appearance.

### 5.6 Card / Panel

**Purpose.** Group related content on a page. The dashboard's responsibility table sits in one. A future settings page would have multiple.

**Anatomy.** White (`paper`) background, 1px `border` color border, no shadow by default, `24px` internal padding (mobile) / `32px` (desktop). Optional title section at top: title + optional subtitle + optional right-aligned action button or status badge, separated from body by `24px` of vertical space.

**Variants.** `default` (as above), `tinted` (`paper-warm` bg, no border) for nested visual grouping.

**States.** Static.

### 5.7 Empty State

**Purpose.** Explain why a region is empty and what will fill it.

**Anatomy.** Centered within its container. Title (`title` size, `ink`, weight 600) + description paragraph (`body` size, `ink-muted`, max 2 sentences) + optional secondary button. **No illustration.** **No icon.** The product is too restrained for that.

**Variants.** Inline (sits inside a card where data would be), full-page (sits as the entire page content for the dashboard "no responsibilities yet" state).

### 5.8 Page Header

**Purpose.** Anchor every web page with the dealership context and the page's purpose.

**Anatomy.**
- Top line (`small` size, `ink-subtle`, weight 500): the dealership name. Always present so the user can see they landed in the right rooftop.
- H1 (`display` size, weight 700, `ink`): the page's purpose, in business language. Examples:
  - "Marketing strategy submission for May 2026" (submission form)
  - "Accountability dashboard" (with the dealership name above)
  - "This dashboard link has expired"
- Optional subtitle (`subtitle` size, weight 400, `ink-muted`): one sentence of orienting context. ("Read-only summary; we'll grow this view in upcoming releases.")
- No "back" button. No breadcrumbs. Single-purpose pages do not have hierarchy.

### 5.9 Magic-Link Landing Frame

This is not strictly a component but a **layout primitive** every web surface uses. It defines the page chrome.

**Anatomy** (top to bottom):
1. Top spacer: `40px` mobile / `56px` desktop
2. Optional Rogue wordmark (small, `ink-subtle`, top-left, fixed) — *omit on the submission form* to keep the page focused; *include* on the dashboard so brand presence exists for GMs who arrive at it
3. Centered content column (max-width per page type per §4.3)
4. Page header (§5.8)
5. Page content (the form, the table, the empty state — exactly one of these)
6. Bottom spacer: `40px`
7. Optional footnote (`small`, `ink-subtle`): one line of context per page, e.g., "This page is a snapshot. We'll send your next digest in seven days."

**No global navigation.** No top bar. No sidebar. No footer beyond the optional footnote. Login surfaces (when they eventually exist for power users) are explicitly opt-in and live elsewhere.

### 5.10 Loading & Async States

Submissions and dashboard renders are server-rendered Rails pages today, so blocking page transitions are acceptable. Where async behavior is added (Turbo Frame swaps, Stimulus-driven inline edits), use:

- **Inline spinner** inside primary buttons during submit — replace label with spinner + new label ("Submitting…")
- **Skeleton blocks** *only* on the dashboard if/when it does live-update — `border` color rectangles with subtle shimmer, height-matched to the content they will replace
- **No full-page loading overlays.** Ever.

---

## 6. Page Templates

Three templates cover MVP. Each derives from the Magic-Link Landing Frame (§5.9).

### 6.1 Single-Purpose Submission Form

**Use:** `/submissions/forms/:signed_id` — a vendor or staff submitter clicks the link in a prompt email and lands here to enter one number.

**Layout (mobile-first, max-w-2xl):**
- Page header: dealership name (small) + H1 in form "Marketing strategy submission for May 2026" + subtitle "Enter the value and any notes, then submit."
- Form card: number input (label = the metric name, capitalized, e.g. "Marketing strategy"), textarea ("Notes (optional)"), large primary submit button "Submit".
- On validation failure: error banner above the card; per-field errors inline.

### 6.2 Submission-Received Confirmation

**Use:** the `?submitted=true` state of the same URL, or the `already_submitted` page.

**Layout:**
- Page header: dealership name (small) + H1 "Got it — submission received." (no subtitle)
- Body: 1–2 short paragraphs confirming what was captured ("We have your *marketing strategy* for *May 2026*."), what the user can do now ("You can close this tab. We'll send the next prompt when it's due."), and how to amend ("Need to amend it? Reply to your most recent email from Rogue and we'll help.")
- No primary button — the page is a terminus.

### 6.3 Accountability Dashboard

**Use:** `/dashboards/:signed_id` — the GM clicks a magic link in their weekly digest and lands here.

**Layout (max-w-5xl):**
- Page header: small dealership name above + H1 "Accountability dashboard" + subtitle "Hi *Pat*. Read-only summary; we'll grow this view in upcoming releases."
- Content card: data table with columns Responsibility / Owner / Status / Next due, status badge in column 3, dates right-aligned.
- Empty state (when no responsibilities yet): inside the same card, replacing the table — "No responsibilities yet. Once your team starts answering onboarding questions, they'll appear here."
- Footnote: "This page is a snapshot. We'll send your next digest in seven days."

### 6.4 Link-Expired Page

**Use:** dashboards or submission links that have expired.

**Layout (max-w-2xl):**
- Page header: H1 "This dashboard link has expired." or equivalent; no dealership name (we don't reveal context for expired tokens).
- Body: one short paragraph explaining the expiry policy and what the user should do next ("Watch for your next weekly digest — it'll include a fresh link.")

### 6.5 Future Templates (mention only — not designing now)

- Source onboarding walkthrough (multi-step form for invitees)
- Adapter mapping review/approve (table + diff view)
- Vendor multi-rooftop overview
- Internal Rogue admin console

These are out of scope for this design pass but the component library should be extensible to them without re-foundational changes.

---

## 7. Voice & Tone

Drawn from the existing email copy and onboarding flows; this is what every component's default copy must match.

- **Direct.** "Got it." "Submission received." "Read-only summary; we'll grow this view." Short sentences. No "Welcome!" or "Thanks for using Rogue!"
- **Plain English, never jargon.** "Who controls your marketing strategy?" not "Configure your marketing accountability assignment."
- **First-person plural for Rogue, second-person for the user.** "We'll send your next prompt when it's due." "You can close this tab."
- **Honest about state.** "Late" means late. "Overdue and will be escalated tomorrow" names what happens next. No softening, no "oops!" framing for errors.
- **No exclamation points** outside literal celebratory contexts (none currently exist on web). No emoji. No animated copy.

---

## 8. Accessibility

Target: **WCAG 2.1 Level AA** across all surfaces, with these specific rules:

1. **Color contrast** ≥4.5:1 for body text, ≥3:1 for `large` (≥18px regular, ≥14px bold) text and UI components. The §4.1 palette is designed to meet AAA on default body, AA on every status pair.
2. **Color is never the only signal.** Every status pill carries a text label and an icon. Form errors are conveyed by inline text, not just border color.
3. **Keyboard navigability.** Every interactive element reachable in document order via Tab. `:focus-visible` shows a 2px `brand` ring with 2px offset on every focusable element (buttons, inputs, links). No `outline: none` without a replacement.
4. **Screen reader semantics.** Real headings (`<h1>`, `<h2>`), real tables, real labels, real buttons. ARIA only where native semantics are insufficient (banners with `role="alert"`, dynamic content with `aria-live`).
5. **Reduced motion.** All non-essential animation honors `prefers-reduced-motion: reduce`. The submit-button spinner reduces to a static "Submitting…" label.
6. **Form errors** are announced via the alert banner (§5.5) on submit, with field-level errors anchored from the banner.
7. **Touch targets** ≥44×44px on mobile.
8. **Language** declared on `<html>` (`lang="en"` at MVP).

---

## 9. Responsive Behavior

**Breakpoints** (Tailwind defaults retained):

| Token | Min width | Use |
|-------|-----------|-----|
| (default) | 0px | Mobile portrait — design baseline |
| `sm` | 640px | Mobile landscape, small tablet |
| `md` | 768px | Tablet portrait |
| `lg` | 1024px | Desktop |
| `xl` | 1280px | Wide desktop (rarely needed at MVP) |

**Behavior rules:**

- All page templates work down to **360px wide**.
- The data table collapses to stacked cards at `<640px` (§5.4).
- Page max-widths are caps; below them, content fills the viewport with `20px` horizontal padding (`16px` at <360px).
- Type scales as listed in §4.2 (mobile / desktop pair); switch at `md` (768px).
- Touch and pointer interactions are equivalent — no hover-only affordances.

---

## 10. Technical Constraints (relevant to design choices)

The component library will be implemented in this stack — design decisions must respect what the stack can do without fighting it:

- **Tailwind CSS v4** as the styling layer (will be installed as part of this effort).
- **Rails 8 ERB templates** as the rendering primitive, with **ViewComponents** for the reusable components defined in §5. Variants are passed as Ruby keyword args, not CSS class lookup tables.
- **Hotwire (Turbo + Stimulus)** for any client-side behavior. No React. No client-side framework. No build step beyond Tailwind's CLI — Importmap covers JS.
- **Server-rendered first.** A page that works without JavaScript is the requirement; Stimulus is progressive enhancement.
- **Email rendering** uses a *parallel* but visually consistent set of templates with inline styles, not the Tailwind utility classes. The component library does **not** need to render in email clients — that is `app/views/<mailer>/` territory. But the visual language (colors, type, status pills) must be **transferable** to inline-styled HTML email so the two surfaces feel like one product. The §4.1 palette is therefore expressed in literal hex values, not abstract Tailwind theme tokens, so the same values can be used in both places.

---

## 11. Out of Scope (this design pass)

- **Authenticated web app.** Login screens, session management, password + 2FA flows — deferred to a later pass.
- **Vendor multi-rooftop dashboards.** Acknowledged; not designed.
- **Source-onboarding walkthrough** (the invitee web flow). It exists conceptually in productBrief but is not built; design will follow the same library when it ships.
- **Adapter review/approval UI.** Deferred.
- **Marketing site / pricing page / landing page.** Rogue today is sales-led; no public marketing surfaces exist.
- **Dark mode.** Not required at MVP. Color tokens are named so they could be themed later, but no second palette is being defined now.
- **Internationalization.** English-only MVP; copy is not yet wrapped in i18n.

---

## 12. Deliverables Expected from Design

Given this brief, the design output should include:

1. **A component sheet** showing every component in §5 with all its variants and states laid out flat on a single canvas (Storybook-style).
2. **High-fidelity mockups of the four MVP page templates** in §6, at both **mobile (375px)** and **desktop (1024px)** widths. Show the data-table mobile collapse explicitly.
3. **A populated data-table mockup** with at least 6 rows covering all five status variants (so we see the full status palette in context).
4. **A populated submission form mockup** in three states: pristine, validation-error, post-submit confirmation.
5. **A swatch sheet** documenting the final color tokens (with hex), the typographic scale (rendered samples), and the spacing scale.

Designs should be deliverable as **Figma frames** or equivalent, with each component named consistently with the §5 inventory so the implementation pass can map 1:1 from design tokens / components to ViewComponent names.

---

## 13. Things the Design Should *Not* Do

A short list of common mid-2020s SaaS design moves that would be wrong for Rogue, called out so they can be avoided affirmatively rather than rediscovered:

- ❌ Gradients (no two-color buttons, no gradient page backgrounds)
- ❌ Glassmorphism / frosted blur panels
- ❌ Animated illustrations or Lottie loaders
- ❌ Decorative emoji in UI (✅ in *body copy* of an email is fine; in UI chrome it is not)
- ❌ Multiple brand colors (one accent only)
- ❌ Hero images on dashboard or form pages
- ❌ Dense feature-marketing chrome (sticky CTAs, "Try Pro" badges, etc.)
- ❌ Dark mode (deferred — do not deliver a dark variant)
- ❌ Floating action buttons
- ❌ Animated micro-interactions on every hover (a state transition can be a 100ms color change; it should not be a bounce)
- ❌ Sidebar navigation (no global nav exists; do not invent one)

The throughline: **Rogue's design earns trust by looking calm and competent, not by looking *current*.**
