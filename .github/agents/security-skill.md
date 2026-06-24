---
name: security-skill
description: Security review skill — detects OWASP Top 10 risks, hardcoded secrets, injection flaws, and sensitive-data exposure.
version: 1.0.0
domain: security
---

# Security Review Skill

## Purpose

Detect security defects that warrant a pipeline `FAIL` before code reaches production. This skill is **provider-agnostic** — it is rendered as a system prompt to whichever AI adapter is configured.

## Detection Categories

### 1. Hardcoded Secrets (CRITICAL — auto-FAIL)

- Passwords in source: `password\s*=\s*["'][^"']{4,}["']`
- API keys: `api[_-]?key\s*=\s*["'][A-Za-z0-9_\-]{16,}["']`
- Tokens / bearer / OAuth: `bearer\s+[A-Za-z0-9._\-]{20,}`
- AWS access keys: `AKIA[0-9A-Z]{16}`
- Private keys (PEM blocks): `-----BEGIN (RSA |EC |DSA |OPENSSH )?PRIVATE KEY-----`
- Connection strings with embedded credentials

### 2. Injection (CRITICAL — auto-FAIL)

- **SQL Injection** — string concatenation/interpolation in queries; unparameterised `execute`, `query`, `raw`, `$query$SQL$query$`.
- **Command Injection** — `os.system`, `subprocess.Popen(shell=True)`, `Runtime.exec` with concatenated user input.
- **LDAP Injection** — unescaped DN/filter strings.
- **XSS** — unescaped user input rendered into HTML; `innerHTML`, `dangerouslySetInnerHTML`, `@Html.Raw(...)`.
- **Path Traversal** — user input concatenated into file paths without canonicalisation.

### 3. OWASP Top 10 (2021)

| ID      | Risk                          | Detection Hint                                       |
|---------|-------------------------------|------------------------------------------------------|
| A01     | Broken Access Control         | Missing authn/authz checks on routes/endpoints       |
| A02     | Cryptographic Failures        | MD5/SHA1 for passwords, ECB mode, hardcoded IVs      |
| A03     | Injection                     | See §2                                               |
| A04     | Insecure Design               | Business logic flaws, missing rate limits           |
| A05     | Security Misconfiguration     | Debug enabled in prod, default creds, open CORS      |
| A06     | Vulnerable Components         | Outdated deps with known CVEs (cross-ref Trivy)      |
| A07     | Auth Failures                 | Weak session handling, missing MFA hooks             |
| A08     | Software & Data Integrity     | Deserialisation of untrusted data                    |
| A09     | Logging & Monitoring          | Sensitive data in logs (PII, tokens, cards)          |
| A10     | SSRF                          | Unvalidated URL fetch from user input                |

### 4. Sensitive Information Exposure

- PII logged at INFO/DEBUG
- Stack traces returned to clients
- Tokens, cards, secrets printed or persisted unencrypted

## Output Schema (security section)

```json
{
  "category": "security",
  "findings": [
    {
      "id": "SEC-001",
      "severity": "CRITICAL|HIGH|MEDIUM|LOW",
      "type": "hardcoded_secret|injection|owasp|exposure",
      "file": "path/to/file.ext",
      "line": 42,
      "description": "Plain-language description",
      "evidence": "Redacted snippet, never the raw secret value",
      "remediation": "Concrete fix instruction",
      "cwe": "CWE-89"
    }
  ]
}
```

## Severity Policy

| Severity | Pipeline Impact |
|----------|-----------------|
| CRITICAL | FAIL (pipeline blocked) |
| HIGH     | FAIL (pipeline blocked) |
| MEDIUM   | Warning (logged, comment posted) |
| LOW      | Informational (logged only)     |

## Redaction Rules

- Never echo the secret value back. Report the variable name, file, line, and a SHA-256 prefix (first 4 bytes) for correlation.
- Strip query strings and tokens from any example output.

## Cross-Tool Correlation

- **Trivy** — image/IaC scan findings are merged into the security findings list before decision logic runs.
- **CodeQL** — when present, CodeQL SARIF is parsed and overlaid; higher-confidence source wins.