---
name: "Learned: Time Zones in Tenant-Scoped Code"
globs: ["app/services/**/*.rb", "app/models/**/*.rb", "app/jobs/**/*.rb"]
topics: ["time-zones", "scheduling"]
priority: low
evidence_count: 2
last_updated: 2026-05-03
auto_generated: true
---

# Time Zones in Tenant-Scoped Code

- When constructing dates/times in tenant-scoped code, derive the zone from the tenant (or from a `TimeWithZone` you received) — never from `Time.zone` (the application default leaks UTC). Scheduled timestamps cross calendar boundaries and land on the wrong day. Apply anywhere you call `Time.zone.local`, `Date.current`, or `.beginning_of_*` inside a method that takes a `Tenant` or a `time_zone:` argument.

## Evidence

| Learning | Source | Date |
|----------|--------|------|
| Quarterly-scheduler bug: `Time.zone.local(year, month, 1)` constructed in UTC landed on previous day in `America/New_York`. Fixed by using `now.time_zone.local(...)` | [reflection-TASK-001.md](../../reflection/reflection-TASK-001.md) | 2026-05-03 |
| `Submissions::Capture#period_starting_for` and `DigestAssembler.any_current_period_submission?` both use `prompt.scheduled_for.in_time_zone(tenant.time_zone).to_date.beginning_of_month` — period boundaries align across mailer / capture / digest because they're constructed identically | [reflection-TASK-002.md](../../reflection/reflection-TASK-002.md) | 2026-05-03 |
