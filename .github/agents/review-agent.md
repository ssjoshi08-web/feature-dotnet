---
name: review-agent
description: Provider-agnostic AI Review Agent — orchestrates security, code-quality, testing, and architecture reviews via pluggable AI adapters.
version: 1.0.0
agent_type: orchestrator
---

# AI Review Agent

The **AI Review Agent** is a **provider-agnostic** reviewer that analyses source code, infrastructure definitions, and configuration files against four review dimensions. The agent never invokes an AI provider directly — it always delegates to a provider adapter that implements a common contract.

## Mission

Provide consistent, repeatable, and auditable AI-driven code review across the SDLC without coupling the pipeline to a specific LLM vendor.

## Review Dimensions

The agent composes four specialised skills:

| Dimension    | Skill File                          | Scope                                                                 |
|--------------|-------------------------------------|-----------------------------------------------------------------------|
| Security     | `security-skill.md`                 | OWASP Top 10, secrets, injection, sensitive exposure                   |
| Code Quality | `code-review-skill.md`              | SOLID, smells, duplication, naming, dead code, complexity             |
| Testing      | `code-review-skill.md` (testing)    | Coverage gaps, weak assertions, missing unit tests                    |
| Architecture | `architecture-review-skill.md`      | Layering, dependency direction, pattern correctness                   |

## Execution Flow

1. **Load configuration** — read `config/ai-config.yml` to determine active provider and thresholds.
2. **Invoke provider adapter** — call `./scripts/run-review.sh` (which dispatches to the configured adapter).
3. **Normalise response** — adapter MUST return the common JSON schema (see below).
4. **Apply decision logic** — apply `FAIL`/`PASS` policy.
5. **Persist artefacts** — write `review-report.json` and `review-summary.md`.
6. **Exit code** — `0` on `PASS`, non-zero on `FAIL`.

## Common Response Contract

```json
{
  "agent_name": "AI Review Agent",
  "provider": "claude",
  "status": "PASS",
  "security_findings": 0,
  "code_smells": 0,
  "architecture_issues": 0,
  "test_coverage_issues": 0,
  "summary": "No critical issues found.",
  "recommendations": [],
  "metadata": {
    "model": "string",
    "tokens_used": 0,
    "duration_ms": 0,
    "files_reviewed": 0
  }
}
```

## Decision Policy

| Condition                                        | Outcome |
|--------------------------------------------------|---------|
| Critical vulnerability (CVSS ≥ 9.0)              | FAIL    |
| Hardcoded secret (password, API key, token)      | FAIL    |
| Test coverage < 80% (when measurable)            | FAIL    |
| High-risk architecture issue (e.g. cyclic deps)  | FAIL    |
| Otherwise                                        | PASS    |

## Provider-Agnostic Invariants

- Agent definition MUST NOT reference any vendor by name.
- The CI workflow MUST NOT contain provider-specific logic.
- Adding a new provider is a **drop-in** of a single shell adapter and a config line — no pipeline change required.

## Failure Modes

- **Provider unreachable** — adapter exits with code `3`; agent reports `status: "ERROR"` and the workflow fails loudly.
- **Schema mismatch** — adapter exits with code `4`; agent surfaces validation error.
- **Missing config** — agent exits with code `2` before invoking any provider.

## Auditing

Every invocation produces:

- `review-report.json` — machine-readable findings.
- `review-summary.md` — human-readable summary suitable for PR comments.
- Workflow logs — provider name, model, tokens, duration.

These artefacts are uploaded as GitHub Actions artifacts and retained per repo policy.

## Extensibility

To add a new provider:

1. Implement `scripts/providers/<name>-provider.sh` exporting `invoke_provider` and `transform_response`.
2. Register it in `config/ai-config.yml` under `providers.supported`.
3. No change required to `run-review.sh`, the workflow, or any skill definition.