---
name: architecture-review-skill
description: Architecture review skill — detects layering violations, dependency-direction errors, and misapplied design patterns.
version: 1.0.0
domain: architecture
---

# Architecture Review Skill

## Purpose

Detect structural defects that don't show up as line-level smells but undermine maintainability, testability, and evolvability. Findings flow into `architecture_issues` in the common response schema.

## Review Surfaces

### 1. Layer Violations

Conventional layering (configurable per stack):

```
Presentation → Application → Domain → Infrastructure
```

#### Forbidden Edges

- **Domain → Infrastructure** — domain entities must not import persistence, framework, transport, or IO concerns.
- **Domain → Presentation** — domain must not depend on UI/HTTP types.
- **Application → Presentation** — application services must not render views.
- **Infrastructure → Application** (inbound) — adapters may depend on ports, not the other way around.

#### Detection

- Static import-graph analysis: parse `import`/`using`/`require` statements.
- Acyclic dependencies principle (ADP) — flag any cycle in the dependency graph.
- Stable Dependencies Principle (SDP) — depend in the direction of stability.

### 2. Dependency Violations

- **Wrong abstraction level** — high-level policy depending on a low-level detail.
- **Leaky abstraction** — implementation detail exposed through a public interface (e.g. `JpaRepository` returned from a domain service).
- **Cross-cutting concern bleed** — logging, tracing, or auth implemented inside business logic instead of via decorator/middleware/interceptor.
- **Inappropriate Intimacy** — two modules accessing each other's private internals.
- **Stable Abstractions Principle (SAP)** — abstractness should rise with stability.

### 3. Design Pattern Misuse

| Pattern            | Misuse Signal                                                                |
|--------------------|------------------------------------------------------------------------------|
| Singleton          | Used for stateful collaborators, breaks testability, hides dependencies      |
| Repository         | Leaks IQueryable / ORM types to callers                                      |
| Factory            | Used for object construction when DI container would suffice                |
| Strategy           | Only one strategy ever supplied; over-engineered polymorphism                |
| Decorator          | Decorator mutates underlying behaviour instead of adding orthogonal concerns |
| Observer / Pub-Sub | Event handlers perform blocking IO synchronously                            |
| MVC                | Fat controllers — business logic in controller, not service                  |
| CQRS               | Read and write models silently share persistence                             |
| Microservice       | Distributed monolith — synchronous chains, shared DB                         |
| Hexagonal (Ports)  | Adapters calling other adapters directly                                     |

### 4. Boundaries & Contracts

- Public API contracts change without versioning
- Module exports more than it should (broad `export *`)
- Missing/null interfaces where contracts are unclear
- Public types with mutable state leaking across layers

### 5. Concurrency & State

- Shared mutable state across threads without synchronisation
- Static mutable collections
- Time/dates obtained via `new Date()` deep in domain logic (non-deterministic, untestable)
- Random sources not injected

### 6. Configuration & Secrets Architecture

- Secrets hardcoded (cross-reference `security-skill`)
- Config scattered across the codebase instead of centralised
- Environment-specific values checked into source

## Output Schema

```json
{
  "category": "architecture",
  "findings": [
    {
      "id": "ARCH-001",
      "issue_type": "layer_violation|dependency_violation|pattern_misuse|boundary|concurrency|config",
      "from": "module.A",
      "to": "module.B",
      "description": "...",
      "impact": "Testability | Maintainability | Evolvability | Performance",
      "remediation": "...",
      "severity": "CRITICAL|HIGH|MEDIUM|LOW"
    }
  ]
}
```

## Severity Policy

| Severity | Definition                                                                  | Pipeline Impact |
|----------|-----------------------------------------------------------------------------|-----------------|
| CRITICAL | Circular dependency between modules; domain bleeding into infrastructure   | FAIL            |
| HIGH     | Cross-layer import; pattern misuse that prevents unit testing               | FAIL            |
| MEDIUM   | Leaky abstraction; inappropriate intimacy                                  | Warning         |
| LOW      | Cosmetic pattern concern; documentation-only                               | Informational   |

## Cross-Tool Inputs

- **`build.gradle` / `pom.xml` / `package.json` / `*.csproj`** — module/dependency metadata.
- **`deps.json` / `dependency-graph.json`** — pre-computed graph from the build step, when available.
- **Trivy IaC scan** — for cloud-architecture drift.

The architecture reviewer prefers **graph-based detection** over heuristic text matching wherever the build pipeline can produce a structured graph.