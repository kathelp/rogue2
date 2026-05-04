---
name: "Learned: Service Namespace Conventions"
globs: ["app/services/**/*.rb", "app/controllers/**/*.rb"]
topics: ["namespacing", "service-classes", "zeitwerk"]
priority: low
evidence_count: 1
last_updated: 2026-05-03
auto_generated: true
---

# Service Namespace Conventions

- When a service's natural noun matches an ActiveRecord model class (singular form), default to the **plural** form for the service module namespace. Aligns with Rails controller conventions (`Submissions::FormsController`) and avoids Zeitwerk's `TypeError: <Singular> is not a module` when both `app/models/<singular>.rb` (class) and `app/services/<singular>/...rb` (module) load. Apply when creating any service class whose noun could collide with an existing model.

## Evidence

| Learning | Source | Date |
|----------|--------|------|
| `Submission::Capture` failed to load (Zeitwerk: "Submission is not a module") because `app/models/submission.rb` defines `Submission` as a class. Renamed to `Submissions::Capture` to match the controller namespace `Submissions::FormsController`. | [reflection-TASK-002.md](../../reflection/reflection-TASK-002.md) | 2026-05-03 |
