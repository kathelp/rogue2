---
name: "Learned: Predicate-pair symmetry"
globs: ["app/models/**/*.rb"]
topics: ["ruby", "rails", "models", "predicates", "scopes"]
priority: low
evidence_count: 1
last_updated: 2026-05-11
auto_generated: true
---

# Predicate-Pair Symmetry

- When extending a model with a positive predicate (`verified?`, `confirmed?`, `published?`), also add the negation (`unverified?`, `unconfirmed?`, `draft?`) if a scope of that name exists or is likely to be added. The cost is one line; the benefit is symmetric usage at call sites — `if @contact.unverified?` reads more clearly than `unless @contact.verified?` and matches the existing scope vocabulary (`Contact.unverified`).
- Asymmetric naming surface — scope present, predicate absent — is a small but recurring source of confusion. Callers reach for `model.unverified?` because the scope is `:unverified`, hit `NoMethodError`, and then must either add the predicate (right answer) or write `!model.verified?` at every call site (wrong answer — drift accumulates).
- This is **not** a call to add both directions for every predicate by default — single-direction predicates are fine when only one form is ever used. The rule applies when (a) a scope of the negation already exists, or (b) the codebase already has the same predicate/scope pair on a peer model.

## Evidence

| Learning | Source | Date |
|----------|--------|------|
| TASK-008 added `Contact#verified?` predicate and `:verified`/`:unverified` scopes but skipped `Contact#unverified?`. TASK-009's `Setup::WalkthroughsController#template_for_step` reached for `@contact.unverified?` (mirroring the scope name), hit `NoMethodError`, and added the one-line predicate. The asymmetric naming surface (scope present, predicate absent) was the trigger; adding the negation predicate took one line and removed the temptation to litter the controller with `!@contact.verified?`. | [reflection-TASK-009.md](../../reflection/reflection-TASK-009.md) | 2026-05-11 |
