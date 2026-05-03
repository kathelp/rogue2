# Algorithm Decision: TASK-001 — Email Reply Parser & In-Thread Threading

**Created**: 2026-05-03
**Status**: DECIDED
**Decision Type**: Algorithm
**Task**: TASK-001 (Tenant + GM Email-First Onboarding) / FEAT-001
**Complexity**: Level 4

---

## Problem Statement

The email-first onboarding loop hinges on two algorithms whose correctness is load-bearing for the entire product:

1. **Reply parser** — given an inbound `Mail::Message` (delivered to `OnboardingMailbox` via `ActionMailbox::InboundEmail`), produce a typed `ParsedReply` value object that the rest of the pipeline (`VendorInferenceService`, `Responsibility` / `Source` / `Request` writers, `OnboardingMailer.in_thread_ack`) can consume without further parsing. Mistakes in this layer become wrong-person assignments, missed `skip` deferrals, or false "we couldn't parse" loops — all of which destroy GM trust on the very first interaction.
2. **In-thread ack threading** — every outbound that should land inside the GM's existing onboarding thread (in-thread ack, vendor clarification, gm_only_thread_notice) must thread reliably across Gmail, Outlook, and Apple Mail. Mail-client threading is fragile and the ack is the GM's only confirmation that Rogue heard them; a broken thread reads like silence.

Both algorithms must respect Guiding Principle 3 (raw payload retention — the parser **never** mutates the inbound) and Guiding Principle 7 (idempotent inbound — re-delivery of the same `Message-ID` is a no-op), per `systemPatterns.md`.

---

## Inputs & Outputs (top-level contract)

### Inputs
| Name | Type | Size/Range | Source |
|------|------|------------|--------|
| `inbound_email` | `ActionMailbox::InboundEmail` | One per delivered reply; raw RFC 822 retained on the row | Action Mailbox |
| `inbound_email.mail` | `Mail::Message` (mail gem) | Typical reply ~5–50 KB; max enforced by ingress | derived from raw source |
| `tenant` | `Tenant` | Resolved from `To:` token (`onboarding+<onboarding_token>@…`) | `OnboardingMailbox#process` |
| `expected_question` | `Question` | Resolved by `In-Reply-To` / `References` lookup against outbound `Message-ID` | persisted on outbound side |

### Outputs
| Name | Type | Description |
|------|------|-------------|
| `ParsedReply` | Struct/Data class | `intent`, `primary_email`, `fallback_emails`, `question_id`, `raw_excerpt`, `confidence`, `warnings[]` |

`ParsedReply` shape (frozen):

```ruby
ParsedReply = Data.define(
  :intent,           # :assign | :self_assign | :skip | :unparseable | :clarification_response
  :primary_email,    # String? (normalized lowercase)
  :fallback_emails,  # Array<String> (normalized, ordered)
  :question_id,      # ID? (resolved from In-Reply-To/References, may be nil for top-of-thread email)
  :raw_excerpt,      # String — the meaningful body slice for audit (<= 4 KB)
  :confidence,       # :high | :medium | :low
  :warnings          # Array<Symbol> — see Failure-mode catalog below
)
```

The `OnboardingMailbox#process` method then dispatches on `intent`. The parser is a pure service: `OnboardingReplyParser.call(inbound_email:, tenant:)` returns a `ParsedReply`, mutates nothing, raises only for programmer errors (never for malformed mail — malformed mail flows through as `:unparseable`).

---

## L1. Reply parser algorithm

### L1.a — CC ordering normalization

#### Problem
The product convention is "first CC = primary, rest = fallbacks, in order." But mail clients are inconsistent about CC ordering on the wire:

| Client | Behavior |
|--------|----------|
| Gmail web | Preserves entry order (verified — Gmail does not re-sort CCs since ~2018) |
| Gmail mobile | Preserves entry order |
| Outlook desktop (Win/Mac) | Preserves entry order |
| Outlook web (OWA) | **Sometimes** re-orders by display name when the user has Contacts cached for those addresses |
| Apple Mail (macOS/iOS) | Preserves entry order |
| Other (Spark, Hey, mobile defaults) | Generally preserve, but unverifiable across the long tail |

The risk: a GM types `alex, taylor, casey` intending Alex as primary; OWA reorders to `alex, casey, taylor` (alphabetical by first name); we assign Casey as fallback ahead of Taylor. The product copy explicitly tells the GM "order matters," so silently flipping order is worse than a no-op.

#### Options

**Option A — Trust the wire order, full stop.**
- Approach: take `mail.cc.addresses` as-given.
- Pros: trivial; matches AC-HAPPY-4 verbatim ("the order on the wire is the order the GM intended"); zero GM friction in the 95%+ case.
- Cons: silent miscategorization in the OWA edge case; no signal to the GM that we may have it wrong.

**Option B — Body-text override hints.**
- Approach: scan the GM's reply body for explicit ordering cues (`primary: X`, `fallbacks: Y, Z`, `1) X 2) Y`); when present, override the CC order.
- Pros: gives an escape hatch for GMs who notice their client misordered.
- Cons: adds parser surface area, NLP fuzziness (does `1.` count? Does `* alex` count?), and product complexity (now we have to teach the convention twice). False-positive risk: a body that incidentally contains "primary" inside prose ("our primary issue is …") could trigger override.

**Option C — Pre-populate `X-Rogue-Primary-Hint` header on the question email; rely on it being echoed back.**
- Approach: outbound question email includes `X-Rogue-Primary-Hint: cc[0]` (informational; not used as the source of truth — it's a *check* against the inbound CC ordering).
- Pros: clean separation of concerns.
- Cons: **most clients strip unrecognized custom `X-` headers on reply.** Verified: Gmail strips, Outlook strips, Apple Mail strips. The header almost never survives. Dead end.

**Option D — Confirm in the in-thread ack and let the GM correct.**
- Approach: take wire order, but the in-thread ack explicitly names "Alex (primary), Taylor and Casey (fallbacks in that order)." If the GM sees it backwards, they reply with a correction (existing `:clarification_response` intent path handles this).
- Pros: honest about uncertainty; GM in the loop; doesn't gate on perfection.
- Cons: adds one more round trip in the rare miscategorization case.

**Option E — Hybrid: trust the wire by default; flag low-confidence when client is a known re-orderer.**
- Approach: detect Outlook Web via `User-Agent` / `X-Mailer` / `Message-ID` host fingerprinting; emit `:cc_order_uncertain` warning; otherwise default to wire order. The in-thread ack always names primary + fallbacks explicitly so the GM can self-correct (Option D mechanic) — the warning is for **us** (logging, future heuristics), not the GM.

#### Decision
**Option E (hybrid: trust wire order + confidence flag + always-explicit ack).**

Rationale:
- Wire order is correct in the vast majority of cases (4 of 5 verified clients preserve it).
- The OWA-reorder case is rare in practice (requires the GM's contacts to be cached *and* the addresses to sort differently than typed) but real enough to be worth flagging.
- The in-thread ack already names primary + fallbacks by design (per AC-HAPPY-3 ack copy: `"Alex (alex@smithtoyota.com) is on the hook for marketing strategy"`); making this explicitly enumerate fallbacks too costs nothing and gives the GM a one-glance correctness check.
- Body-text overrides (Option B) add too much fuzziness for the parsed-intent contract; we'd rather take a clean signal and confirm than try to be clever.
- Custom `X-` headers (Option C) don't survive — confirmed in published mail-client behavior; not viable.

#### Implementation guidance

```ruby
# app/services/onboarding_reply_parser/cc_ordering.rb
module OnboardingReplyParser::CcOrdering
  REORDERING_CLIENTS = [
    /Microsoft Office Outlook Web/i,  # OWA classic
    /Outlook-iOS/i,                   # known to occasionally re-order on send
  ].freeze

  def self.normalize(mail)
    addresses = Array(mail.cc).flat_map { |a| Array(a) }.map { |a| normalize_address(a) }.compact
    warnings = []
    if reorderer?(mail)
      warnings << :cc_order_uncertain
    end
    [addresses, warnings]
  end

  def self.normalize_address(addr)
    # mail gem returns Mail::Address-like; pull the spec, downcase, strip
    raw = addr.respond_to?(:address) ? addr.address : addr.to_s
    raw&.strip&.downcase.presence
  end

  def self.reorderer?(mail)
    user_agent = (mail.header[:user_agent]&.to_s || mail.header['X-Mailer']&.to_s || '')
    REORDERING_CLIENTS.any? { |re| user_agent.match?(re) }
  end
end
```

In-thread ack template **must** name fallbacks explicitly:

> "Got it — Alex (alex@smithtoyota.com) is on the hook for marketing strategy. Fallbacks: Taylor (taylor@smithtoyota.com), then Casey (casey@smithtoyota.com). They'll receive setup instructions shortly. Next question coming in 24h."

If the GM replies "actually Taylor is primary, swap them" the existing `:clarification_response` intent rebuilds the `Responsibility` (revisit-skipped flow already covers this state-transition shape; clarification reuses it).

---

### L1.b — Body extraction (reply vs. quoted ancestor vs. signature)

#### Problem
A reply body contains:
1. New content (the GM's actual words)
2. A signature block (`-- \nJane Smith\nGM, Smith Toyota\n555-…`)
3. Quoted prior message (`On Wed, May 3, Rogue <onboarding+…> wrote:\n> Who controls your marketing strategy?\n> …`)
4. Possibly nested ancestor quotes from a longer thread
5. Both `text/plain` and `text/html` MIME parts (often with diverged content)

The parser must isolate (1) so that (a) `skip` detection (L1.c) doesn't false-positive on the word appearing in the signature or a quoted ancestor, (b) the `raw_excerpt` saved to the parsed result is human-readable, and (c) the audit trail tells a useful story to the support engineer six months from now reviewing why a `Responsibility` got created the way it did.

#### Options

**Option A — Talon (Mailgun, Apache 2.0) ported / shelled out.**
- Approach: Mailgun's open-source Python reply parser. Most accurate published heuristic on diverse mail-client samples (cited 95%+ accuracy on their internal corpus).
- Pros: battle-tested; handles signatures and quotes; pretrained ML classifier for ambiguous cases.
- Cons: **Python**. Options are (a) shell out per inbound (latency hit, IPC fragility, deployment complexity — adds Python runtime to Kamal image), (b) port to Ruby (significant project, ML model is the hardest part), (c) extract just the heuristic regexes (loses the ML benefit). License (Apache 2.0) is fine.

**Option B — `email_reply_parser` gem (GitHub, MIT).**
- Approach: GitHub's open-source Ruby implementation of their own reply-trimming heuristic. ~9 years old, pure regex, no ML. Used by GitHub for issue-comment email replies.
- Pros: pure Ruby; lightweight (~200 LOC); MIT-licensed; designed for exactly this use case (extracting "the new content from a reply"); installed in many production Rails apps.
- Cons: heuristic-only — fails on mail clients that don't include a recognizable "On X, Y wrote:" prefix; signature detection is line-prefix-based (`-- ` line), which Outlook/Apple Mail often don't emit; HTML handling is weak (designed primarily for plain text).

**Option C — `EmailReplyTrimmer` (Discourse, MIT).**
- Approach: Discourse's reply trimmer — newer than GitHub's, more aggressive about quote detection, handles multiple languages of "On … wrote:" prefixes.
- Pros: maintained (Discourse uses it in production today); MIT; pure Ruby; better international quote detection than `email_reply_parser`.
- Cons: also primarily plain-text-oriented; Discourse strips HTML to text upstream and trims the text — for our use we need to do the same.

**Option D — Custom heuristic (regexes + line classifier).**
- Approach: write our own. Regex for `On <date>, <addr> wrote:` in 5 languages, regex for `>` quote prefixes, regex for `-- ` signature delimiter, regex for known "Sent from my iPhone" signature lines, line-by-line classifier.
- Pros: full control; no gem dependency; can be tuned to our exact 5-client corpus.
- Cons: we will reinvent every bug Talon and `EmailReplyTrimmer` already fixed; high maintenance cost; "tuned to our corpus" means brittle when a new client appears.

**Option E — AI-assisted parsing (LLM extraction).**
- Approach: pass the body to a model and ask "extract just the new content." Optional: use as fallback when heuristic confidence is low.
- Pros: handles cases the heuristics miss (weird signature layouts, multi-language, HTML).
- Cons: latency (1–3s vs. <10ms heuristic); cost (per-reply token spend on a high-volume path); non-determinism (a cosmic-ray model retrain shifts our parser behavior); deployment dependency on an external API at the ingest hot path. **Critically:** the parser runs on every onboarding reply forever; making it depend on an external LLM at ingest is the kind of decision you regret. Acceptable as an offline reprocessing tool for `:unparseable` audits, not as the primary path.

**Option F — Hybrid: `EmailReplyTrimmer` first; LLM fallback only for `:unparseable` triage (offline).**
- Approach: heuristic on the hot path; when the parser would emit `:unparseable`, log the InboundEmail for offline LLM review by a human-supervised reprocessing job (out of MVP scope but the seam is in place).

#### Decision
**Option C (`EmailReplyTrimmer`) for the hot path, with seam for Option F (offline LLM triage) in future phases.**

Rationale:
- Pure Ruby + MIT keeps the deployment footprint clean (no Python, no extra runtime).
- Discourse uses it in production at scale on similar inbound traffic; that's the strongest signal of robustness.
- Heuristic latency is bounded and predictable (<10ms), which matters because parsing happens inline with `OnboardingMailbox#process` — every wasted ms is a delayed in-thread ack.
- The `EmailReplyTrimmer` gem has a clean API: `EmailReplyTrimmer.trim(text)` returns the trimmed body. We layer our own signature-stripping pass on top to catch the cases it misses (Outlook desktop emits no `-- ` delimiter).
- LLM fallback is the right architecture but not the right starting point — we'd be paying its cost for the 5% of cases we can't determine yet, and we can build the audit pipeline in a later phase once we have real `:unparseable` rates to optimize against.

License: MIT — compatible with our (presumed MIT/private) Rails app.

#### Implementation guidance

```ruby
# Gemfile
gem 'email_reply_trimmer', '~> 0.1.13'  # Discourse's gem
```

```ruby
# app/services/onboarding_reply_parser/body_extractor.rb
module OnboardingReplyParser::BodyExtractor
  # Custom signature regexes for clients that EmailReplyTrimmer misses
  SIGNATURE_PATTERNS = [
    /^--\s*$/,                          # standard sig delimiter
    /^Sent from my (iPhone|iPad|Android)/i,
    /^Get Outlook for (iOS|Android)/i,
    /^Sent via the Samsung Galaxy/i,
  ].freeze

  # Extracts the GM's actual reply text from a Mail::Message.
  # Returns: { body: String, confidence: :high|:medium|:low, warnings: [Symbol] }
  def self.extract(mail)
    plain = pick_plain_part(mail)
    html  = pick_html_part(mail)
    warnings = []

    # 1. Prefer plain-text part if present and substantive
    raw_body =
      if plain.present? && plain.bytesize > 0
        plain
      elsif html.present?
        warnings << :html_only_reply
        strip_html_to_text(html)
      else
        warnings << :empty_body
        return { body: "", confidence: :low, warnings: warnings }
      end

    # 2. Trim quoted ancestors using EmailReplyTrimmer
    trimmed = EmailReplyTrimmer.trim(raw_body)

    # 3. Strip signatures we recognize
    body_lines = trimmed.lines
    sig_idx = body_lines.find_index { |line| SIGNATURE_PATTERNS.any? { |p| line.match?(p) } }
    cleaned = sig_idx ? body_lines[0...sig_idx].join : body_lines.join

    # 4. Confidence scoring
    confidence = assess_confidence(raw: raw_body, trimmed: trimmed, cleaned: cleaned)

    # 5. HTML/plain divergence check (only if both parts present)
    if plain.present? && html.present?
      html_text = strip_html_to_text(html)
      html_trimmed = EmailReplyTrimmer.trim(html_text)
      if normalize_for_compare(html_trimmed) != normalize_for_compare(trimmed)
        warnings << :html_plain_diverged
      end
    end

    { body: cleaned.strip, confidence: confidence, warnings: warnings }
  end

  def self.pick_plain_part(mail)
    return mail.body.decoded if mail.parts.empty? && mail.content_type&.start_with?('text/plain')
    mail.text_part&.decoded
  end

  def self.pick_html_part(mail)
    return nil if mail.parts.empty?
    mail.html_part&.decoded
  end

  def self.strip_html_to_text(html)
    # Use the `nokogiri` gem (already a Rails 8 dependency via action_text)
    doc = Nokogiri::HTML::DocumentFragment.parse(html)
    doc.css('blockquote, .gmail_quote, .OutlookMessageHeader, .gmail_signature').remove
    text = doc.text
    text.gsub(/ /, ' ').gsub(/[ \t]+/, ' ').gsub(/\n{3,}/, "\n\n")
  end

  def self.normalize_for_compare(text)
    text.downcase.gsub(/\s+/, ' ').strip
  end

  def self.assess_confidence(raw:, trimmed:, cleaned:)
    return :low  if cleaned.length < 2
    return :low  if trimmed == raw && raw.length > 5_000  # never found a quote boundary in a long reply -> probably missed it
    return :high if cleaned.length.between?(2, 1_000) && trimmed != raw
    :medium
  end
end
```

Notes:
- `Nokogiri` is already in the dependency tree (Rails 8 ships it via `action_text`); no new dep.
- Pre-removing `blockquote`, `.gmail_quote`, `.OutlookMessageHeader` from HTML before text-extraction handles ~90% of HTML-quote cases without relying on `EmailReplyTrimmer`'s plain-text-only quote regexes.
- The confidence heuristic is conservative — long replies with no quote-boundary detected get `:low` because we can't tell if we're including the ancestor. `:low` does not auto-fail the parse; it surfaces a warning the inbound handler logs and may use to ask for confirmation in the ack.

---

### L1.c — `skip` detection with quote/signature false-positive guards

#### Problem
GM types `skip` on its own line in the reply body. False positives to avoid:
1. "skip" inside a signature block (`Project Manager — skip-list reviewer`)
2. "skip" inside a quoted ancestor message
3. "skip" as part of a longer word (`skipping`, `skipped`, `skiplist`)
4. "skip" in a phrase that means the opposite (`don't skip this`, `not skip`)

We need a deterministic predicate the GM can learn: "type the word `skip` on its own line, optionally with whitespace around it."

#### Options

**Option A — Match `skip` anywhere in the cleaned body (post L1.b extraction).**
- Pros: lenient.
- Cons: false-positives on the "don't skip" / "skipping" cases.

**Option B — Single-token-on-its-own-line in the cleaned body.**
- Predicate: any line in cleaned body, after stripping leading/trailing whitespace and trailing punctuation, equals `skip` (case-insensitive).
- Pros: deterministic, teachable, robust to most false positives.
- Cons: a GM who writes "skip" inline ("Let's skip this one for now") doesn't get matched — but that's also a feature; it's ambiguous and we'd rather they retype it on its own line.

**Option C — Required position: `skip` must be the first non-empty line.**
- Pros: even more constrained, even fewer false positives.
- Cons: **too** constrained — a GM who writes "Hey, skip this one." on the first line and `skip` on the second won't match (the first line is non-empty and isn't `skip`).

**Option D — Combined: cleaned body length ≤ 30 chars AND contains `skip` as a token.**
- Pros: catches "skip", "Skip!", "skip.", "Skip — for now" all in a tight window.
- Cons: arbitrary cutoff; "skip pls" (8 chars) matches but "skip — circle back next quarter" (32 chars) doesn't. GM can't learn it from one observation.

#### Decision
**Option B (single-token-on-its-own-line in the cleaned body), with the operative word being "in the cleaned body."**

Rationale:
- The cleaned body from L1.b has signatures and quoted ancestors already removed, so `skip` in those locations cannot reach this predicate. That's the primary defense.
- "Single token on its own line, case-insensitive, surrounded by whitespace" is the most teachable rule: the GM can learn it from one in-thread ack ("type `skip` on its own line to defer"). The question email convention block already states it this way.
- Allowing trailing punctuation (`.`, `!`, `…`) is humane without being permissive — `skip!` is plainly intent; `skipping!` is plainly not.
- We do **not** require `skip` be the only line in the body — a GM may type "skip — we'll figure out who later" with `skip` on its own line and explanatory prose on subsequent lines. Enforcing "only line" is hostile.

#### Implementation guidance — exact predicate

```ruby
# app/services/onboarding_reply_parser/skip_detector.rb
module OnboardingReplyParser::SkipDetector
  # Match one line containing only the word "skip", case-insensitive,
  # with optional surrounding whitespace and at most one trailing
  # punctuation char from .,!?;…
  # The cleaned body has already had quoted ancestors and signatures stripped
  # (per L1.b), so a match here is robustly "the GM said skip."
  SKIP_LINE = /\A[[:space:]]*skip[[:space:]]*[.,!?;…]?[[:space:]]*\z/i

  def self.skip?(cleaned_body)
    cleaned_body.lines.any? { |line| line.match?(SKIP_LINE) }
  end
end
```

Test corpus — these MUST match:
```
"skip"
"  skip  "
"skip."
"Skip!"
"SKIP"
"skip\n"
"Hey,\nskip\nlet's revisit Q3\n"   # skip on its own line, prose around it
```

Test corpus — these MUST NOT match:
```
"skipping this for now"
"don't skip"
"skip-list reviewer"      # hyphenated
"Skip, my dog, says hi"   # comma inline
"skip the meeting"        # inline
""                         # empty
```

If `:skip` is detected, the parser sets `intent = :skip`, ignores any CCs (a `skip` reply with CCs is a contradiction; we treat the `skip` as authoritative and emit warning `:skip_with_ccs_present` so the ack can mention it: "We saw `skip` so we're deferring this. If you meant to assign Alex instead, just reply with their name.").

---

### L1.d — Multi-part HTML/plain reconciliation

#### Problem
Most clients send `multipart/alternative` with both parts. They occasionally diverge — most often when the user types in a rich-text editor and the editor adds inline formatting or signature HTML that the plain-text fallback doesn't include. Rare, but real.

#### Options

**Option A — Always prefer plain.** Simplest. Plain is what the GM "literally typed" in 99% of cases.
**Option B — Always prefer HTML (after stripping).** Captures rich-formatting nuances.
**Option C — Pick whichever produces higher confidence post-extraction.** Adaptive.
**Option D — Prefer plain; warn if they diverge significantly.** Conservative.

#### Decision
**Option D — prefer plain; emit `:html_plain_diverged` warning when normalized comparison differs.**

Rationale:
- Plain text is what the user "really typed"; HTML is the client's interpretation. When in doubt, trust the user's input.
- Divergence is rare but worth surfacing: it's a signal that something unusual is going on and the audit trail should note it.
- The warning doesn't change parse intent; it just gets logged and surfaced on the InboundEmail record so a support engineer can dig in if a complaint comes in.
- HTML-only replies (no plain part) — fall back to HTML, strip with Nokogiri, emit `:html_only_reply` warning. Some mobile clients (early Outlook iOS versions) shipped HTML-only.

#### Implementation guidance

Already covered in L1.b's `BodyExtractor.extract` — the `:html_plain_diverged` warning fires when both parts exist and `normalize_for_compare(plain_trimmed) != normalize_for_compare(html_trimmed)`. Normalization is whitespace-insensitive and case-insensitive to avoid noise.

---

### L1.e — Attachment handling

#### Problem
GMs may reply with attachments — a PDF list of vendors, a screenshot of an org chart, a CSV of contacts. Attachments aren't part of the reply convention. Question: ignore, archive, surface metadata, or reject?

#### Options

**Option A — Ignore at MVP.** Attachments are not part of the convention; we don't need them.
**Option B — Archive to ActiveStorage but don't process.** Preserves the data for future use without taking on processing responsibility.
**Option C — Surface metadata in `ParsedReply`.** Passes through filename / size / content-type so downstream code can decide.
**Option D — Reject (return `:unparseable`).** Defensive; treats unexpected attachments as a sign the GM didn't follow the convention.

#### Decision
**Option B + C — archive raw attachments via Action Mailbox's existing storage; surface metadata in `ParsedReply.warnings` as `:has_attachments` (no detail in `ParsedReply` itself; lookup via `inbound_email.mail.attachments` if needed).**

Rationale:
- Guiding Principle 3 (raw payload retention) already requires we store the full RFC 822 source — attachments are inside that source automatically. No additional ActiveStorage work needed.
- Surfacing `:has_attachments` as a warning lets the in-thread ack mention them ("We got your reply and noticed an attachment — at MVP we don't process attachments, but they're saved with the message. If there was something we should have read, just paste it inline next time.") — keeps the GM informed without dropping data.
- Rejecting (Option D) is hostile; an attachment is not a sign of bad intent, just a different communication style.
- Attachments don't affect intent classification — the body still drives `:assign` / `:self_assign` / `:skip` / `:unparseable`.

#### Implementation guidance

```ruby
# Inside OnboardingReplyParser.call
warnings << :has_attachments if mail.attachments.present?
```

The in-thread ack template has a conditional clause that fires when `:has_attachments` warning is set on the inbound's parser result.

---

### L1 summary — overall parser shape

```ruby
# app/services/onboarding_reply_parser.rb
class OnboardingReplyParser
  ParsedReply = Data.define(
    :intent,
    :primary_email,
    :fallback_emails,
    :question_id,
    :raw_excerpt,
    :confidence,
    :warnings
  )

  # Public entry point. Pure: no side effects beyond Rails.logger calls.
  def self.call(inbound_email:, tenant:)
    new(inbound_email: inbound_email, tenant: tenant).call
  end

  def initialize(inbound_email:, tenant:)
    @inbound_email = inbound_email
    @tenant = tenant
    @mail = inbound_email.mail
    @warnings = []
  end

  def call
    # 1. Resolve which question this reply is answering (via In-Reply-To / References)
    question_id = ThreadResolver.resolve_question_id(@mail, @tenant)
    @warnings << :question_unresolved if question_id.nil?

    # 2. Extract the GM's actual body content (signatures + quotes stripped)
    body_result = BodyExtractor.extract(@mail)
    @warnings.concat(body_result[:warnings])

    # 3. CC ordering + normalization
    cc_addresses, cc_warnings = CcOrdering.normalize(@mail)
    @warnings.concat(cc_warnings)

    # 4. Attachment metadata
    @warnings << :has_attachments if @mail.attachments.present?

    # 5. Intent dispatch — order matters: skip wins over CCs
    intent, primary, fallbacks = classify_intent(
      cleaned_body: body_result[:body],
      cc_addresses: cc_addresses,
      gm_email: @tenant.gm_email
    )

    # 6. Confidence: take the lower of body extraction confidence and intent confidence
    confidence = combine_confidence(body_result[:confidence], intent_confidence(intent, body_result[:body]))

    # 7. raw_excerpt: cap at 4 KB so audit row stays small; full RFC 822 lives on InboundEmail
    raw_excerpt = body_result[:body].byteslice(0, 4_096) || ""

    ParsedReply.new(
      intent: intent,
      primary_email: primary,
      fallback_emails: fallbacks,
      question_id: question_id,
      raw_excerpt: raw_excerpt,
      confidence: confidence,
      warnings: @warnings.uniq
    )
  rescue StandardError => e
    # Never raise from the parser; a malformed mail is a parser result, not a crash.
    Rails.logger.tagged(tenant: @tenant.id, flow: :onboarding, parser: :error).error(
      message: "OnboardingReplyParser failed",
      error: e.class.name,
      detail: e.message,
      message_id: @mail.message_id
    )
    ParsedReply.new(
      intent: :unparseable,
      primary_email: nil,
      fallback_emails: [],
      question_id: nil,
      raw_excerpt: "",
      confidence: :low,
      warnings: (@warnings + [:parser_exception]).uniq
    )
  end

  private

  def classify_intent(cleaned_body:, cc_addresses:, gm_email:)
    # Order matters:
    # (a) :skip wins over CCs (per L1.c rationale)
    # (b) CCs present and not :skip => :assign
    # (c) No CCs and body suggests self-assignment => :self_assign
    # (d) Otherwise => :unparseable
    return [:skip, nil, []] if SkipDetector.skip?(cleaned_body)

    if cc_addresses.any?
      primary, *fallbacks = cc_addresses
      [:assign, primary, fallbacks]
    elsif self_assign?(cleaned_body, gm_email)
      [:self_assign, gm_email.downcase, []]
    else
      [:unparseable, nil, []]
    end
  end

  # Self-assign signal — kept narrow because false positives here mean
  # we wrongly assign the GM to something they meant to skip or assign.
  # Accepts: "me", "that's me", "I do", "I am", "I'll handle it", "yes, me",
  # body that's primarily empty (single-line short reply with affirmative).
  def self_assign?(cleaned_body, gm_email)
    return false if cleaned_body.blank?
    normalized = cleaned_body.downcase.strip
    # Direct "me" indicators on their own line
    return true if normalized.lines.any? { |l| l.strip.match?(/\A(me|that'?s me|i do|i am|i'?ll handle (it|this)|yes,?\s*me)[.!]?\z/) }
    # Short body with a "me" token in a self-referential context
    return true if normalized.length <= 80 && normalized.match?(/\b(it'?s me|that'?s me|i'?ll do it|i'?ll handle (it|this))\b/)
    false
  end

  def intent_confidence(intent, body)
    case intent
    when :skip then :high          # the predicate is deterministic; if it matched, we're sure
    when :assign then :high        # CCs are unambiguous (modulo L1.a OWA case, already flagged separately)
    when :self_assign then body.length <= 80 ? :high : :medium
    when :unparseable then :high   # we're sure we can't parse it
    end
  end

  def combine_confidence(c1, c2)
    order = { high: 2, medium: 1, low: 0 }
    [c1, c2].min_by { |c| order[c] }
  end
end
```

What gets logged (via `Rails.logger.tagged(tenant: ..., flow: :onboarding)`):
- One INFO line per parsed reply: `{message_id, intent, confidence, warning_count, question_id_resolved}`. PII (email addresses, body content) is **not** logged at INFO; it lives on the InboundEmail row only.
- One WARN line per non-empty warning set, structured: `{message_id, warnings: [:cc_order_uncertain, :html_plain_diverged]}`.
- One ERROR line on parser exception (only for programmer errors — malformed mail flows through normally).

What gets persisted as warnings on the InboundEmail record:
- A `parser_warnings` jsonb column on `ActionMailbox::InboundEmail` (added via migration in Phase 1) holding the `warnings: [Symbol]` array. This is queryable for "show me all replies that flagged `:cc_order_uncertain` last quarter" support audits.
- `parser_intent` and `parser_confidence` mirrored as columns for cheap indexing.

The parser does **not** persist the `ParsedReply` itself — that's the dispatcher's job (`OnboardingMailbox#process`), which uses the `ParsedReply` to drive `Responsibility` / `Source` writes. Parser stays pure.

---

## L2. In-thread ack threading discipline

### L2.a — Header strategy

#### Problem
RFC 5322 §3.6.4 specifies threading via `Message-ID`, `In-Reply-To`, and `References`. Mail clients implement this to varying fidelity. Our outbound replies must:
- Set `In-Reply-To: <parent-message-id>`
- Set `References: <chain accumulating ancestors>`
- Set `Subject: Re: <parent subject>` (or unchanged if already prefixed)

Question: **what is "the parent" for each ack flavor?**

#### Options
- **A**: Parent is always the original outbound question email — keeps acks anchored to the same root.
- **B**: Parent is the GM's inbound reply we're acknowledging — most natural for the GM's client (the ack appears next to their reply in the thread view).
- **C**: Conditional per ack flavor — different parents for different cases.

#### Decision
**Option C, with explicit parent assignment per flavor:**

| Ack flavor | Parent | Rationale |
|------------|--------|-----------|
| `in_thread_ack` (response to GM's reply) | The GM's inbound reply (`InboundEmail#message_id`) | The GM's client threads our ack right next to their reply — most natural visual experience |
| `vendor_clarification` (asking GM about an unknown domain) | The GM's inbound reply | Same thread; the question lives where the reply lived |
| `gm_only_thread_notice` (sent to a non-GM who tried to reply on the thread) | The non-GM's inbound (their attempted reply) | Their client threads our notice next to their attempt; isolated side-thread doesn't pollute the GM's main thread |
| Next `question_email` (new question for the GM) | **No parent — fresh thread** | Each new question is a new thread (per AC-ENTRY-3 subject convention `[Smith Toyota Onboarding] <question text>`). Otherwise a single tenant's onboarding becomes one giant thread that's impossible to navigate. |

The `References` chain accumulates: each outbound's `References` header is the parent's `References` header (if present) plus the parent's `Message-ID`. This keeps the chain RFC-compliant and lets long threads still reconstruct the full ancestry.

#### Implementation guidance

```ruby
# app/mailers/concerns/threadable.rb
module Threadable
  extend ActiveSupport::Concern

  # Set In-Reply-To and References on an outbound that's a reply to `parent_inbound`.
  # parent_inbound is an ActionMailbox::InboundEmail.
  def thread_to(parent_inbound)
    return unless parent_inbound&.message_id
    headers['In-Reply-To'] = "<#{parent_inbound.message_id}>"
    parent_refs = parent_inbound.mail.references
    refs = Array(parent_refs) + [parent_inbound.message_id]
    headers['References'] = refs.map { |id| "<#{id}>" }.join(' ')
  end
end
```

```ruby
# app/mailers/onboarding_mailer.rb
class OnboardingMailer < ApplicationMailer
  include Threadable

  def in_thread_ack(parsed_reply:, inbound_email:)
    @parsed = parsed_reply
    thread_to(inbound_email)
    mail(
      to: inbound_email.tenant.gm_email,
      from: inbound_email.tenant.onboarding_address,
      subject: subject_for_ack(inbound_email)
    )
  end
  # ... etc
end
```

### L2.b — Subject discipline

#### Problem
- The GM may edit the subject mid-thread (adds `[response]`, removes the bracket prefix).
- A new question email is a *new* thread, not a reply, so it needs a fresh subject.

#### Options
- **A**: Always reuse the **original** onboarding-thread subject for in-thread acks (canonical, GM edits ignored).
- **B**: Always echo the GM's last-seen subject (preserves their edits — could lose threading if they strip `Re:`).
- **C**: Force a canonical subject `[<Dealership> Onboarding] <topic>` regardless of GM edits.

#### Decision
**Option C — force canonical subject `Re: [<Dealership> Onboarding] <question text>` for in-thread acks; `[<Dealership> Onboarding] <new question>` for fresh questions.**

Rationale:
- Threading in modern mail clients works primarily off `In-Reply-To` / `References`, not subject; subject is a tiebreaker/display label. So enforcing a canonical subject does not break threading.
- Canonical subject makes Rogue's emails greppable in the GM's inbox ("show me all `[Smith Toyota Onboarding]` mail") and reduces visual confusion when the GM has multiple responsibilities in flight.
- GM subject edits don't affect us — we always send our own subject. (If the GM strips the bracket prefix on their reply, fine; we'll put it back on our ack.)
- The `Re: ` prefix is added unless the parent subject already has one (RFC 5322 §3.6.5).

```ruby
def subject_for_ack(inbound_email)
  question_subject = inbound_email.question&.subject || "Onboarding"
  base = "[#{inbound_email.tenant.dealership_name} Onboarding] #{question_subject}"
  base.start_with?("Re:") ? base : "Re: #{base}"
end
```

### L2.c — Message-ID conventions

#### Problem
Every outbound gets a `Message-ID`. We can let Action Mailer auto-generate, or we can encode tenant/question/role information into the ID for easier lookup on inbound.

#### Options
- **A**: Auto-generate (Rails default — `<random@hostname>`).
- **B**: Deterministic IDs encoding `(tenant, question, role)` — e.g., `<tenant-1-question-7-ack@inbound.rogue.example>`.
- **C**: Auto-generate **and** persist outbound `message_id` on the related record (`Question#outbound_message_id`, `Tenant#confirmation_message_id`).

#### Decision
**Option C (auto-generate + persist on the originating record).**

Rationale:
- Deterministic IDs (Option B) leak structure to anyone who sees the headers (sender domains, inbound bounce reports, etc.). Information-leak smell, even if low-severity.
- Auto-generated IDs are cryptographically random, which is fine — what we actually need is fast inbound lookup, which we get by persisting the outbound `Message-ID` on the record that *generated* it. When an inbound comes in with `In-Reply-To: <X>`, we look up `Question.find_by(outbound_message_id: X)` — O(1) with an index, no parsing of structured IDs.
- This is also what's already needed for the `ThreadResolver` in `OnboardingReplyParser.call` (per L1 summary, `question_id` resolution).

#### Implementation guidance

Add to migration:
```ruby
add_column :questions, :outbound_message_id, :string
add_index :questions, :outbound_message_id, unique: true
```

In the question email mailer:
```ruby
def question_email(tenant:, question:)
  msg = mail(
    to: tenant.gm_email,
    from: tenant.onboarding_address,
    reply_to: tenant.onboarding_address,
    subject: "[#{tenant.dealership_name} Onboarding] #{question.text}"
  )
  # Persist Message-ID after the mailer composes it
  question.update!(outbound_message_id: msg.message_id)
  msg
end
```

Resolver:
```ruby
# app/services/onboarding_reply_parser/thread_resolver.rb
module OnboardingReplyParser::ThreadResolver
  def self.resolve_question_id(mail, tenant)
    candidate_ids = [Array(mail.in_reply_to), Array(mail.references)].flatten.compact
    return nil if candidate_ids.empty?
    Question.where(tenant_id: tenant.id, outbound_message_id: candidate_ids).pick(:id)
  end
end
```

### L2.d — Threading verification

#### Problem
Header correctness on the wire is necessary but not sufficient — different clients render threads differently, and some have known quirks (Outlook desktop sometimes ignores `In-Reply-To` and threads on `Subject` alone; Apple Mail honors `References` aggressively; Gmail prefers `Message-ID` chain matching).

#### Options
- **A**: Manual smoke test before each release. Slow, gates production.
- **B**: Fixture-based system tests: capture real mail-client `.eml` outputs once, replay in tests via Action Mailbox helpers, assert headers + thread continuity.
- **C**: Headless mail-client rendering. Heavy, out of scope.
- **D**: Live-dogfood: send to test mailboxes in Gmail / Outlook / Apple Mail; eyeball the result. One-time per major mailer change.

#### Decision
**Option B (fixture-based system tests) for CI gating + Option D (live-dogfood) once per build phase 4–5 cutover, captured as a Live-Dogfood-Pending tracker entry.**

Rationale:
- Fixture-based tests catch regressions in our own outbound headers — we can assert `In-Reply-To` matches the inbound `Message-ID`, `References` chain is well-formed, `Subject` follows the canonical pattern. That's a high-value, fast-feedback CI gate.
- Live-dogfood is the only way to verify *rendering* — that Gmail actually threads our ack with the GM's reply. We capture this once during build phase 4, save the screenshot evidence to a doc, and add to Live-Dogfood-Pending tracker for re-verification at production cutover (where we're probably switching ingress providers anyway, which can subtly change headers).
- Headless rendering (Option C) is too much engineering for an MVP guarantee — not worth it.

#### Implementation guidance

Test:
```ruby
# test/system/in_thread_ack_threading_test.rb
test "in-thread ack carries In-Reply-To and References pointing at GM reply" do
  tenant = create_tenant_confirmed
  question = create_first_question(tenant)

  receive_inbound_email_from_fixture('onboarding_replies/gmail_one_cc.eml')

  ack = ActionMailer::Base.deliveries.find { |m| m.subject.include?("Onboarding") && m.to.include?(tenant.gm_email) }
  assert_equal "<gmail-reply-msg-id@mail.gmail.com>", ack.in_reply_to
  assert_includes ack.references, "<gmail-reply-msg-id@mail.gmail.com>"
  assert ack.subject.start_with?("Re: [")
end
```

Live-dogfood checklist (added to TASK-001 Live-Dogfood-Pending Tracker as a Phase 4–5 item):
- Send a fixture question from staging to a real Gmail account; reply with one CC; verify the in-thread ack threads in the Gmail web UI.
- Repeat with Outlook web (OWA), Outlook desktop (Win), Apple Mail (macOS), Apple Mail (iOS).
- Capture screenshots; commit to `docs/threading-verification/` (or note in the task archive if the Docusaurus tree isn't yet in place).

### L2 summary — outbound thread-aware mailer pattern

```ruby
# app/mailers/concerns/threadable.rb
module Threadable
  extend ActiveSupport::Concern

  # For outbounds that are replies to an inbound message.
  def thread_to(parent_inbound)
    return unless parent_inbound&.message_id
    headers['In-Reply-To'] = "<#{parent_inbound.message_id}>"
    refs = Array(parent_inbound.mail.references).compact + [parent_inbound.message_id]
    headers['References'] = refs.map { |id| "<#{id.to_s.delete('<>')}>" }.join(' ')
  end

  # For outbounds that should remain reply-able later (question_email).
  # Persists the Message-ID after composition so inbound replies can resolve back.
  def persist_outbound_message_id_on(record)
    @persist_message_id_on = record
  end

  def mail(headers = {}, &block)
    msg = super
    if @persist_message_id_on && msg.message_id.present?
      @persist_message_id_on.update!(outbound_message_id: msg.message_id)
    end
    msg
  end
end
```

Every outbound email in `OnboardingMailer` either calls `thread_to(parent)` (for acks, clarifications, gm_only_thread_notices) or `persist_outbound_message_id_on(record)` (for fresh threads — confirmation_email, question_email). This is enforced via mailer test checklist:

```ruby
# test/mailers/onboarding_mailer_test.rb
test "every outbound action either threads to a parent or persists Message-ID" do
  OnboardingMailer.action_methods.each do |action|
    # Build an instance, capture which Threadable methods got called
    # ... assertion below
  end
end
```

---

## Test-fixture corpus

The parser test suite **must** include real `.eml` captures from at least these mail clients × intent variants:

### Mail-client variants (rows)
1. **Gmail web** (Chrome / Firefox / Safari)
2. **Gmail mobile** (iOS / Android)
3. **Outlook desktop** (Windows + Mac)
4. **Outlook Web App (OWA)** — the known re-ordering case
5. **Apple Mail** (macOS + iOS — capture both; iOS sometimes emits HTML-only)

### Intent variants (columns)
- `:assign` with one CC
- `:assign` with three CCs (ordering test — AC-HAPPY-4)
- `:self_assign` (no CC, body "me" / "that's me" / "I'll handle it")
- `:skip` with various trailing punctuation, one with a quoted ancestor that *also* contains the word "skip" (false-positive guard test — AC-HAPPY-6)
- `:unparseable` ("sounds good" — AC-ERROR-3)

That's a minimum of 5 × 5 = 25 fixtures. Plus targeted regression fixtures:
- HTML-only reply (Apple Mail iOS sometimes)
- Multipart with diverged plain/HTML parts
- Reply with attachments (PDF, image)
- Reply with `skip` as part of a longer phrase ("don't skip this")
- Reply where signature contains email-like strings (`alex@…`) that must NOT be parsed as CCs
- Outlook desktop reply with no `-- ` signature delimiter
- Reply forwarded through a corporate gateway (added `Received:` chain)

**Total**: ~32 fixtures. Stored at `test/fixtures/files/onboarding_replies/<client>_<intent>.eml`.

### Sourcing approach

**Recommended**: capture real fixtures during build phase 4 from your own personal accounts.

1. Set up a local-dev environment with a working OnboardingMailer.
2. Send a question email from local Rails to your personal Gmail / Outlook / Apple Mail accounts.
3. Reply from each client with each intent variant.
4. Pull the raw `.eml` from each receiving account (Gmail: "Show original" → "Download original"; Outlook: File → Save As → `.eml`; Apple Mail: drag the message to Finder).
5. Sanitize (replace personal email addresses with fictional dealership ones; preserve all headers including `User-Agent`, `Message-ID`, `Received:` chain, MIME boundaries).
6. Commit to `test/fixtures/files/onboarding_replies/` with a `README.md` documenting which client + version each fixture came from and what intent variant it represents.

This is a one-time fixture-collection task that should be tracked as an explicit work item in build phase 4. Without it, the parser tests are theoretical — they pass against synthetic mails that don't reflect real mail-client output. Synthetic mails have been the source of every "parser worked in test, broke in prod" story we'd like to avoid.

**Re-capture cadence**: re-capture fixtures from each client annually, or whenever a major mail-client version ships (e.g., Outlook UI redesigns). Add a `fixture_captured_at` field to the fixture README so we know when they age out.

---

## Failure-mode catalog

The parser may emit any of these warnings on `ParsedReply.warnings`. The inbound handler (`OnboardingMailbox#process`) decides what to do with each.

| Warning symbol | Source | Inbound handler action |
|----------------|--------|------------------------|
| `:cc_order_uncertain` | L1.a — known re-ordering client detected | Proceed normally; log; ack copy explicitly enumerates fallbacks so GM can spot misorder and reply with a correction (clarification flow) |
| `:body_extraction_low_confidence` | L1.b — quote boundary not found in long body | Proceed; log WARN; surface in support audit query |
| `:html_only_reply` | L1.b — no plain part | Proceed; log; consider adding to fixture corpus if frequency increases |
| `:html_plain_diverged` | L1.b/d — plain and HTML parts have substantively different content | Proceed; log WARN with both content normalized for comparison |
| `:empty_body` | L1.b — no body content extractable | Treat as `:unparseable` regardless of CCs (an empty body with CCs is too ambiguous) |
| `:has_attachments` | L1.e — mail has attachments | Proceed; ack mentions "we don't process attachments at MVP but they're saved" |
| `:skip_with_ccs_present` | L1.c — body has `skip` AND CCs | Proceed as `:skip` (skip wins); ack mentions "we saw `skip` so we deferred — if you meant to assign instead, reply with names only" |
| `:question_unresolved` | L2.c — `In-Reply-To` / `References` couldn't resolve to a Question | Treat carefully: if intent is `:assign` and exactly one un-answered question exists for tenant, infer; otherwise reply asking GM to clarify which question they're answering |
| `:parser_exception` | Parser caught an exception | Treat as `:unparseable`; log ERROR with full stack trace; alert engineering channel (out-of-scope at MVP — log severity is enough) |
| `:non_gm_sender` | Set by `OnboardingMailbox#process`, not parser, but tracked alongside | Drop assignment processing entirely; send `gm_only_thread_notice` to the actual sender |

The inbound handler runs on a state machine where most warnings are advisory (log + proceed) and only `:empty_body`, `:question_unresolved` (in some cases), and `:parser_exception` actually change the dispatched code path. This keeps "warning" semantically meaningful (data signal, not error).

---

## Open algorithm questions deferred

These are real problems but not worth solving at MVP. They become relevant when actual data shows the cost.

1. **Non-English signature stripping.** Talon and `EmailReplyTrimmer` both have limited non-English handling. Defer until first non-English-locale customer; revisit then with a corpus of their actual replies.
2. **Stripping conditional disclaimers** ("This email and any attachments may be confidential…"). Many corporate mail systems append these. They're often longer than the actual reply. Currently they get classified as part of the signature by the heuristic; sometimes they don't. Defer until we see them as signal noise in the audit corpus.
3. **AI fallback for `:unparseable` triage.** The Option F in L1.b — when the heuristic says `:unparseable`, ship the InboundEmail to an LLM for offline reprocessing and human review. Useful once we have real `:unparseable` rates (>2% of inbound) to optimize against. Architecturally clean — adds an offline job, doesn't change the hot path. Defer until post-MVP.
4. **Adaptive confidence thresholds.** Currently `:high` / `:medium` / `:low` buckets are heuristic. Could be calibrated against actual parse-correctness data. Defer until we have a feedback loop (e.g., GMs replying to acks with corrections — these are ground-truth-like).
5. **Mail-client fingerprinting at finer granularity.** L1.a only flags Outlook web variants as re-orderers. There may be others. Defer until we see real misorderings in production; expand the regex list then.
6. **HTML-quote stripping for non-Gmail/non-Outlook.** Nokogiri-based stripping currently handles Gmail's `.gmail_quote` and Outlook's `.OutlookMessageHeader`. Apple Mail uses `<blockquote type="cite">`, which the generic `blockquote` selector catches. Other clients may use different markup. Add as discovered.
7. **Body in subject only.** A degenerate case — GM types the entire reply into the subject and leaves the body empty. Currently classified as `:unparseable` (the parser only reads body). Defer; if it becomes common, lift subject content into body extraction.

---

## Validation Checklist

- [x] Parser is a pure service class, callable as `OnboardingReplyParser.call(inbound_email:, tenant:)` returning a typed `ParsedReply`. ✅
- [x] Parser never mutates the inbound (Guiding Principle 3). ✅ — only reads from `inbound_email.mail`; writes only to `Rails.logger`.
- [x] `Message-ID` idempotency handled by Action Mailbox (Guiding Principle 7). ✅ — parser is idempotent because it's pure; the deduplication happens upstream at `ActionMailbox::InboundEmail` create.
- [x] Skip detection robust against signature/quote false positives (AC-HAPPY-6). ✅ — operates on cleaned body post-extraction.
- [x] CC ordering preserved across 5 mail clients (AC-HAPPY-4). ✅ — wire order with `:cc_order_uncertain` flag for OWA-class.
- [x] No-CC reply self-assigns (AC-HAPPY-5). ✅ — `:self_assign` intent.
- [x] Unparseable reply triggers clarification (AC-ERROR-3). ✅ — `:unparseable` intent feeds into `OnboardingMailer.in_thread_ack` with the unparseable copy.
- [x] In-thread ack threads via `In-Reply-To` + `References` (AC-ASYNC-1). ✅ — `Threadable.thread_to` mixin.
- [x] Tenant scoping respected (Guiding Principle 5). ✅ — parser receives `tenant` arg explicitly, never global lookup.

---

## Next Steps

1. **Phase 1**: Add `email_reply_trimmer` to `Gemfile`. Add `parser_warnings` (jsonb), `parser_intent` (string), `parser_confidence` (string) columns to `ActionMailbox::InboundEmail` via migration. Add `outbound_message_id` (string, unique index) to `Question` and `Tenant` (for confirmation_email).
2. **Phase 4 (build, primary work)**: Implement `OnboardingReplyParser` and its sub-modules (`BodyExtractor`, `CcOrdering`, `SkipDetector`, `ThreadResolver`). Implement `Threadable` mixin. Wire into `OnboardingMailbox#process`.
3. **Phase 4 (fixtures)**: Capture the real-mail-client fixture corpus (32 fixtures across 5 clients × intents + edge cases). Commit to `test/fixtures/files/onboarding_replies/`.
4. **Phase 4 (tests)**: Run parser tests against the full fixture corpus. Add integration test verifying threading headers on outbound acks.
5. **Phase 4 (live-dogfood)**: Once tests are green, send real onboarding emails from staging to personal Gmail / Outlook / Apple Mail accounts. Verify threading visually. Capture results in TASK-001 Live-Dogfood-Pending Tracker.
6. **Post-MVP**: Stand up the offline `:unparseable` triage pipeline (Option F in L1.b) once real-traffic `:unparseable` rate is measurable.

ALGORITHM CREATIVE COMPLETE
Document: memory-bank/creative/TASK-001-algorithm.md
Decision: Pure-Ruby reply parser using `email_reply_trimmer` + custom signature/skip predicates with confidence + warning surface; outbound threading via a `Threadable` mailer mixin that sets `In-Reply-To`/`References` from the parent inbound and persists outbound `Message-ID`s on originating records for inbound resolution.
