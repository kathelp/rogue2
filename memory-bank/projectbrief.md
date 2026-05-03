# Project Brief: Rogue

## Project Overview

Rogue is a multi-tenant data collection and standardization platform for automotive dealerships. Dealers define what data they need, from whom, and on what cadence; Rogue collects it through frictionless no-login submission paths and normalizes it into per-domain canonical schemas via AI-assisted adapters.

The MVP focuses on the marketing domain, with lead ingestion (ADF-XML email + raw HTTP POST) as the first end-to-end flow.

> Detailed product specification — domain model, email-first onboarding, submission and escalation flow, MVP scope, adapter accountability, consumption layer, access model, security/data handling, and open questions — lives in `productBrief.md`.

## Goals

1. **Eliminate friction in data collection.** People providing data should never need to create an account, learn a new tool, or change their workflow.
2. **Standardize disparate inputs.** Every domain has one canonical schema so analytics, dashboards, and chat-based reporting can be built once and applied universally.
3. **Make onboarding cheap.** Adapters are AI-generated from sample payloads, so a new tenant/source pairing goes live in minutes rather than weeks of integration work.
4. **Treat vendors as first-class, canonical entities.** A vendor serving 40 rooftops has one identity across the platform.
5. **Establish marketing as the wedge domain** before expanding to sales and service.

## Repository Structure
- **Type**: Mono-repo (single Rails 8 application)
- **Workspace Tool**: None
- **Workspace Root**: N/A

## Git Configuration
- **Repository**: Yes (local)
- **Provider**: None (no remote configured)
- **CLI Available**: gh
- **Remote URL**: none
- **Default Branch**: main
- **Archive Strategy**: local-merge
