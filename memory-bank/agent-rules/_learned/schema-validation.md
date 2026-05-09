---
name: "Learned: Schema Validation Before Planning"
globs: ["memory-bank/tasks/**/*.md", "db/schema.rb"]
topics: ["planning", "schema", "spec-writing"]
priority: low
evidence_count: 1
last_updated: 2026-05-09
auto_generated: true
---

# Schema Validation Before Planning

- Before writing a task spec or plan that names existing database columns, grep those column names against `app/` and `spec/` to verify the column is actually read or written somewhere. Dead schema (declared but never used) should be removed in the same migration that adds new fields, not treated as a base to extend. The cost of finding dead schema late is one creative agent's worth of design exploration that turns out to be premised on a false constraint.

## Evidence

| Learning | Source | Date |
|----------|--------|------|
| TASK-008's task description said "split `Contact#name` into first/last", but the column was actually `display_name` and `grep -rn 'display_name' app/ spec/` returned zero matches. The Spec Writer Agent caught this; the architecture phase resolved it as Q3-A (drop the dead column, add the three new ones). | [reflection-TASK-008.md](../../reflection/reflection-TASK-008.md) | 2026-05-09 |
