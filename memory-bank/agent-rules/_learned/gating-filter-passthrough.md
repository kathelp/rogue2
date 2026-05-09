---
name: "Learned: Gating Filters Pass Through Unknown Records"
globs: ["app/services/**/*.rb", "app/models/**/*.rb"]
topics: ["filtering", "data-modeling", "gating"]
priority: low
evidence_count: 1
last_updated: 2026-05-09
auto_generated: true
---

# Gating Filters Pass Through Unknown Records

- When filtering a collection by a related model's state, treat absence of a corresponding record as KEEP. Only drop items whose related record exists AND fails the gate condition. Three rules: matched + passes gate → KEEP; matched + fails gate → DROP; no match → KEEP. The "no match → DROP" alternative silently breaks legacy raw-string inputs and pre-existing data that predates the gate. Self-healing on later record creation falls out of this design for free.

## Evidence

| Learning | Source | Date |
|----------|--------|------|
| `OnboardingFlow::EscalationCascade.fallback_emails_for` filters fallback email strings against the `contacts` table to drop unverified Contacts. Raw strings with no Contact record (legacy GM-typed fallbacks) pass through; verified Contacts pass through; only unverified Contacts are dropped. Tests verify all three cases, including the gm_nudge `fallback_chain` payload consistency. | [reflection-TASK-008.md](../../reflection/reflection-TASK-008.md) | 2026-05-09 |
