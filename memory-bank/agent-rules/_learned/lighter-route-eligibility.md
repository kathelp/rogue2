---
name: "Learned: Lighter-route eligibility for continuation tasks"
globs: ["memory-bank/tasks/**/*.md", "memory-bank/archive/**/*.md"]
topics: ["build-orchestration", "task-continuation", "workflow-shape"]
priority: low
evidence_count: 1
last_updated: 2026-05-11
auto_generated: true
---

# Lighter-Route Eligibility for Continuation Tasks

- A continuation task whose design questions were all resolved in a predecessor task's `/rai-creative` and whose scope is bounded by existing detailed creative docs can run a **lighter route**:
  - Skip `/rai-plan` — write the task file directly, referencing the predecessor's creative docs as the design source.
  - Skip `/rai-creative` — the predecessor's docs are canonical for the new task; re-running creative would re-derive facts already on disk.
  - Execute `/rai-build` phases **inline** rather than spawning the full sub-agent fan-out (Test Writer → Coding Agent → Test Orchestrators → Code Reviewer → Documentation Agent). For phases of 2-5 files and ~10-20 specs, inline execution is ~3-4× cheaper and produces equivalent output.
- **Eligibility criteria** (all four must hold):
  1. Prior creative docs are canonical for the new task (not contradicting it).
  2. Scope is bounded by existing detailed creative output (e.g., a UI/UX doc with exact ERB snippets, an architecture doc with exact controller pseudocode).
  3. Design questions are all resolved (no LOW-confidence flags remaining).
  4. The task is a continuation — picking up deferred work from a prior task — not a fresh feature.
- **Anti-eligibility** (any one disqualifies):
  - Novel architecture or new component shapes.
  - Ambiguous or unbounded scope.
  - Predecessor creative work contradicts the new requirements.
  - Substantive new design questions arise during planning.
- **Trade-off accepted**: minor TDD-discipline relaxation in phases that touch many files at once (the strict red-then-green cadence becomes "write spec, write impl in close succession" for the heavy phase). For small phases (Phase 0, Phase 3 in TASK-009), strict TDD ordering remained easy.
- The lighter route is **not the default** for Level 3-4 tasks. The default is the full plan → creative → build sequence. The lighter route is an opt-in escape hatch for the specific shape of continuation tasks, declared explicitly at task-creation time and documented in the task file's header.

## Evidence

| Learning | Source | Date |
|----------|--------|------|
| TASK-009 (FEAT-006 FE pass) ran lighter route: task file written directly (no `/rai-plan`), zero new creative phases (referenced TASK-008's three creative docs), four phases executed inline. All five ACs met, 22 new specs, 0 failures, ~3-4× cheaper than full sub-agent fan-out. Eligibility check: prior creative docs were canonical (UI/UX doc had verbatim ERB for `identity.html.erb`; architecture doc had verbatim controller pseudocode); scope was bounded (Live-Dogfood-Pending Tracker enumerated the 4 deferred items); design questions resolved (all 5 in TASK-008's `/rai-creative`); continuation of a prior archived task. | [reflection-TASK-009.md](../../reflection/reflection-TASK-009.md) | 2026-05-11 |
