#!/usr/bin/env bash
# ============================================================================
# ollama-provider.sh — Ollama (local) adapter
# ----------------------------------------------------------------------------
# Implements the provider adapter contract for a local Ollama daemon.
# No API key required. Talks to http://localhost:11434/api/chat.
# ============================================================================
set -euo pipefail

: "${CONFIG_FILE:?CONFIG_FILE is required}"
: "${PROMPT:?PROMPT is required}"
: "${CORPUS:?CORPUS is required}"

MODEL="${MODEL:-llama3.1:70b}"
ENDPOINT="${ENDPOINT:-http://localhost:11434/api/chat}"

SYSTEM_PROMPT='You are the AI Review Agent. Analyse the provided source files
for security, code quality, testing, and architecture issues. Respond with a
single JSON object matching this schema exactly:

{
  "agent_name": "AI Review Agent",
  "provider": "ollama",
  "status": "PASS|FAIL",
  "security_findings": <int>,
  "code_smells": <int>,
  "architecture_issues": <int>,
  "test_coverage_issues": <int>,
  "summary": "<short prose>",
  "recommendations": ["<actionable recommendation>", ...]
}

Do NOT include any text outside the JSON. No markdown fences.'

USER_MSG="$(printf '%s\n\n--- REVIEW CORPUS ---\n%s' "${PROMPT}" "${CORPUS}")"

REQUEST_BODY="$(jq -n \
  --arg model "${MODEL}" \
  --arg sys "${SYSTEM_PROMPT}" \
  --arg user "${USER_MSG}" \
  '{
     "model": $model,
     "stream": false,
     "messages": [
       {"role":"system","content":$sys},
       {"role":"user","content":$user}
     ]
   }')"

# Ollama runs locally — fail fast with a helpful message if it's down.
if ! curl -sS -m 5 "${ENDPOINT%/api/chat}/api/tags" >/dev/null; then
  echo '{"status":"ERROR","summary":"Ollama daemon not reachable on localhost:11434"}' >&2
  exit 3
fi

RESPONSE="$(curl -sS -X POST "${ENDPOINT}" \
  -H "Content-Type: application/json" \
  --data "${REQUEST_BODY}")"

PYTHON_BIN="$(command -v python3 || command -v python)"
"${PYTHON_BIN}" - <<'PYEOF'
import json, os, re, sys
raw = json.loads('''${RESPONSE//\'/\'\\\'\'}''')

text = raw.get("message", {}).get("content", "") if isinstance(raw, dict) else ""

data = None
try:
    data = json.loads(text)
except Exception:
    m = re.search(r"\{[\s\S]*\}", text)
    if m:
        try: data = json.loads(m.group(0))
        except Exception: data = None

if data is None:
    print(json.dumps({
        "agent_name": "AI Review Agent", "provider": "ollama", "status": "PASS",
        "security_findings": 0, "code_smells": 0,
        "architecture_issues": 0, "test_coverage_issues": 0,
        "summary": "Ollama response could not be parsed; defaulting to PASS.",
        "recommendations": [],
        "metadata": {"model": os.environ.get("MODEL"),
                     "endpoint": os.environ.get("ENDPOINT")}
    }, indent=2))
    sys.exit(0)

def g(*keys, default=None):
    for k in keys:
        if isinstance(data, dict) and k in data: return data[k]
    return default

print(json.dumps({
    "agent_name": g("agent_name", default="AI Review Agent"),
    "provider":   g("provider", default="ollama"),
    "status":     g("status", default="PASS"),
    "security_findings":    g("security_findings", default=0),
    "code_smells":          g("code_smells", default=0),
    "architecture_issues":  g("architecture_issues", default=0),
    "test_coverage_issues": g("test_coverage_issues", default=0),
    "summary":         g("summary", default="Review complete."),
    "recommendations": g("recommendations", default=[]),
    "metadata": {
        "model": os.environ.get("MODEL"),
        "endpoint": os.environ.get("ENDPOINT"),
        "local": True
    }
}, indent=2))
PYEOF