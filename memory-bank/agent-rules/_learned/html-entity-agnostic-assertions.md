---
name: "Learned: Rendered-output spec assertion patterns"
globs: ["spec/requests/**/*_spec.rb", "spec/system/**/*_spec.rb", "spec/features/**/*_spec.rb", "spec/mailers/**/*_spec.rb"]
topics: ["testing", "rspec", "request-specs", "system-specs", "mailer-specs", "html-escaping", "assertion-patterns", "field-swap", "regression-guards"]
priority: low
evidence_count: 2
last_updated: 2026-05-12
auto_generated: true
---

# Rendered-output spec assertion patterns

Two tightening patterns for assertions that read rendered template output (views, mailer bodies, dashboard HTML).

## 1. HTML-entity-agnostic error-text assertions

- Spec assertions on error text rendered into HTML should not be sensitive to entity encoding of common punctuation. Rails escapes `'` → `&#39;`, `"` → `&quot;`, `&` → `&amp;` in default-escaped output. Assertions written as `expect(response.body).to include("can't be blank")` will fail against `"can&#39;t be blank"` and a literal-string fix (`include("can&#39;t be blank")`) is brittle to future changes in Rails' default escaping behavior or HTML serializer choice.
- Recommended pattern: assert on the error element's `id` (which renders **only** when the corresponding error is present, providing presence-checking) plus a regex agnostic to the encoded character:
  ```ruby
  expect(response.body).to(include('id="first-name-error"'))
  expect(response.body).to(match(/First name.{0,20}blank/))
  ```
- The `id`-presence check is the strong signal (the element only renders inside `<% if @errors&.key?(:first_name) %>`); the regex over the error text gives a readable trace if the message text changes. Together they are robust to entity encoding, message-text minor edits, and DOM rearrangement.
- Anti-pattern: parsing the response body with Nokogiri just to read `.text` for the un-escaped version. Adds parsing complexity for a one-line problem.

## 2. Positive + negative assertion pairs for field-swap regressions

- When swapping a field that templates were reading (e.g., replacing `model.foo.downcase.sub(/\?$/, "")` with `model.bar`), each new spec assertion should be a *pair*: positive (`include(new field value)`) AND negative (`not_to include(unique fragment of the old transformation's output)`). For example, after swapping `tenant_question.prompt.downcase.sub(/\?$/, "")` for `tenant_question.deliverable`:
  ```ruby
  expect(body).to(include("Marketing strategy report"))    # new field value renders
  expect(body).not_to(include("Who controls"))             # old prompt fragment doesn't
  ```
- The **positive** assertion catches "you forgot to swap this site" — a site you intended to migrate but missed in the diff. The **negative** assertion catches "you swapped a site that should have stayed on the old field" — a regression guard against accidental future reverts or over-migration. Together they pin the change tightly.
- Anti-pattern: only asserting that the new value appears, especially when the new value happens to be a substring of the old one. Example: asserting `include("marketing strategy")` against both old ("who controls your marketing strategy at smith toyota") and new ("Marketing strategy report") outputs passes either way, masking a regression.
- Equally valid in mailer specs (`mail.html_part.body.decoded` / `mail.text_part.body.decoded`) where the same template-fragment vs explicit-field pattern shows up.

## Evidence

| Learning | Source | Date |
|----------|--------|------|
| TASK-009 Phase 1: three blank-field error assertions (`"First name can't be blank"`, `"Last name can't be blank"`, `"Mobile phone can't be blank"`) failed because the apostrophe rendered as `&#39;`. Tightened to `id="<field>-error"` element check + regex `/Field name.{0,20}blank/`. Pattern is now applied uniformly across the four identity-form error assertions in `spec/requests/setup/walkthroughs_spec.rb`. | [reflection-TASK-009.md](../../reflection/reflection-TASK-009.md) | 2026-05-11 |
| TASK-010 Phase 2: five existing spec assertions in `accountability_mailer_spec`, `walkthroughs_spec`, `dashboards_spec` were tightened from `include("marketing strategy")` (passes against both old and new behavior — the old mangled "who controls your marketing strategy" also includes that substring) to `include("Marketing strategy report") + not_to include("Who controls")` (fails on old, passes on new). The negative assertion is the regression guard. Plus 3 net-new assertions on in_thread_ack HTML+text and done view using the same positive+negative pair pattern. | [reflection-TASK-010.md](../../reflection/reflection-TASK-010.md) | 2026-05-12 |
