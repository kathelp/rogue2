---
name: "Learned: HTML-entity-agnostic error-text assertions"
globs: ["spec/requests/**/*_spec.rb", "spec/system/**/*_spec.rb", "spec/features/**/*_spec.rb"]
topics: ["testing", "rspec", "request-specs", "system-specs", "html-escaping"]
priority: low
evidence_count: 1
last_updated: 2026-05-11
auto_generated: true
---

# HTML-entity-agnostic error-text assertions

- Spec assertions on error text rendered into HTML should not be sensitive to entity encoding of common punctuation. Rails escapes `'` → `&#39;`, `"` → `&quot;`, `&` → `&amp;` in default-escaped output. Assertions written as `expect(response.body).to include("can't be blank")` will fail against `"can&#39;t be blank"` and a literal-string fix (`include("can&#39;t be blank")`) is brittle to future changes in Rails' default escaping behavior or HTML serializer choice.
- Recommended pattern: assert on the error element's `id` (which renders **only** when the corresponding error is present, providing presence-checking) plus a regex agnostic to the encoded character:
  ```ruby
  expect(response.body).to(include('id="first-name-error"'))
  expect(response.body).to(match(/First name.{0,20}blank/))
  ```
- The `id`-presence check is the strong signal (the element only renders inside `<% if @errors&.key?(:first_name) %>`); the regex over the error text gives a readable trace if the message text changes. Together they are robust to entity encoding, message-text minor edits, and DOM rearrangement.
- Anti-pattern: parsing the response body with Nokogiri just to read `.text` for the un-escaped version. Adds parsing complexity for a one-line problem.

## Evidence

| Learning | Source | Date |
|----------|--------|------|
| TASK-009 Phase 1: three blank-field error assertions (`"First name can't be blank"`, `"Last name can't be blank"`, `"Mobile phone can't be blank"`) failed because the apostrophe rendered as `&#39;`. Tightened to `id="<field>-error"` element check + regex `/Field name.{0,20}blank/`. Pattern is now applied uniformly across the four identity-form error assertions in `spec/requests/setup/walkthroughs_spec.rb`. | [reflection-TASK-009.md](../../reflection/reflection-TASK-009.md) | 2026-05-11 |
