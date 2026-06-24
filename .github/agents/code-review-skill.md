---
name: code-review-skill
description: Code-quality and testing review skill — detects SOLID violations, code smells, dead code, complexity, and weak/missing tests.
version: 1.0.0
domain: code_quality
---

# Code Review Skill

Covers two review surfaces: **code quality** and **testing**. Both feed the common response schema under `code_smells` and `test_coverage_issues` respectively.

---

## Part 1 — Code Quality

### 1. SOLID Violations

| Principle       | Detection Heuristic                                                       |
|-----------------|---------------------------------------------------------------------------|
| S — SRP         | Class with > 1 high-level responsibility (mixed persistence + business + IO) |
| O — OCP         | Frequent `instanceof` / type-dispatch on a closed hierarchy              |
| L — LSP         | Subclass that throws `UnsupportedOperationException` or weakens preconditions |
| I — ISP         | Interfaces forcing clients to implement unused methods                    |
| D — DIP         | High-level modules importing concrete low-level modules directly          |

### 2. Code Smells

- **Long Method** — > 40 lines or > 3 levels of nesting
- **Large Class** — > 300 lines, > 10 public methods
- **Long Parameter List** — > 4 parameters (consider parameter object)
- **Feature Envy** — method uses another class's data more than its own
- **Primitive Obsession** — over-reliance on primitives where a domain type is warranted
- **Shotgun Surgery** — single conceptual change requires edits in many files
- **Divergent Change** — one class changed for many unrelated reasons
- **Data Clumps** — same group of primitives passed together repeatedly
- **Refused Bequest** — subclass ignores inherited behaviour
- **Comments as Deodorant** — comments justifying unclear code instead of fixing it

### 3. Duplicate Code

- Token-level clones (Type-1, identical except whitespace/comments)
- Structural clones (Type-2, identical structure with renamed identifiers)
- Semantic clones (Type-3, similar behaviour via different code) — flagged with lower confidence

### 4. Naming Conventions

- Single-letter variables outside short lambdas/loops
- Misleading names (e.g. `List<Customer>` declared as `customersList` is fine, but `getCustomers` that mutates is not)
- Inconsistent casing within a module

### 5. Dead Code

- Unreachable branches
- Unused private methods/fields (with no reflection usage)
- Commented-out code blocks > 5 lines

### 6. Complexity

- Cyclomatic complexity > 10 per function
- Cognitive complexity > 15 per function
- Deep nesting (> 3 levels)

---

## Part 2 — Testing

### 1. Coverage Concerns

- Branch coverage < 80% (configurable threshold in `ai-config.yml`)
- Public API surface untested
- Error/exception paths untested
- Boundary conditions (0, -1, max, empty, null) untested

### 2. Missing Unit Tests

- New public functions/methods without at least one positive + one negative test
- New modules without an associated test file
- Bug fixes without regression tests

### 3. Weak Assertions

- `assertTrue(x)` / `Assert.IsTrue(x)` instead of specific assertion
- Assertions on mock setup rather than behaviour
- `Thread.Sleep` in tests (flake risk)
- Tests asserting only on `Mock.Verify` counts with no observable outcome
- No AAA (Arrange-Act-Assert) structure

### 4. Test Smells

- **Eager Test** — single test verifying multiple behaviours
- **Assertion Roulette** — multiple unrelated assertions in one test
- **Mystery Guest** — test depends on external state not declared in the test
- **Slow Test** — unit test touching network, disk, or DB

---

## Output Schema

### Code Smells

```json
{
  "category": "code_smell",
  "findings": [
    {
      "id": "CS-001",
      "smell_type": "long_method|solid_duplicate_dead_complexity|naming",
      "file": "src/...",
      "line": 120,
      "description": "...",
      "suggestion": "Refactor into helper, e.g. ...",
      "severity": "HIGH|MEDIUM|LOW"
    }
  ]
}
```

### Testing

```json
{
  "category": "testing",
  "findings": [
    {
      "id": "TST-001",
      "issue_type": "missing_tests|weak_assertions|coverage|test_smell",
      "file": "tests/...",
      "description": "...",
      "recommendation": "...",
      "severity": "HIGH|MEDIUM|LOW"
    }
  ],
  "coverage": {
    "line_pct": 0.0,
    "branch_pct": 0.0,
    "below_threshold": true
  }
}
```

## Severity Policy

- HIGH — clear defect with measurable impact; recommends a follow-up issue.
- MEDIUM — should-fix before next release; logged but not blocking.
- LOW — informational; appears in summary only.

Coverage below the configured threshold (default **80%**) escalates to a pipeline `FAIL`.