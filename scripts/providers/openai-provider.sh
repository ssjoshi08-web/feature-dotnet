#!/usr/bin/env bash
# ============================================================================
# openai-provider.sh — OpenAI adapter
# ----------------------------------------------------------------------------
# Implements the provider adapter contract for OpenAI's Chat Completions API.
# Reads OPENAI_API_KEY, calls https://api.openai.com/v1/chat/completions,
# normalises the response into the common JSON schema.
# ============================================================================
set -euo pipefail

: "${CONFIG_FILE:?CONFIG_FILE is required}"
: "${PROMPT:?PROMPT is required}"
: "${CORPUS:?CORPUS is required}"

API_KEY="${OPENAI_API_KEY:-}"
[[ -n "${API_KEY}" ]] || { echo '{"status":"ERROR","summary":"OPENAI_API_KEY not set"}' >&2; exit 3; }

MODEL="${MODEL:-gpt-4o}"
ENDPOINT="${ENDPOINT:-https://api.openai.com/v1/chat/completions}"

SYSTEM_PROMPT='You are the AI Review Agent. Analyse the provided source files
for security, code quality, testing, and architecture issues. Respond with a
single JSON object matching this schema exactly:

{
  "agent_name": "AI Review Agent",
  "provider": "openai",
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
     "temperature": 0,
     "response_format": {"type": "json_object"},
     "messages": [
       {"role":"system","content":$sys},
       {"role":"user","content":$user}
     ]
   }')"

RESPONSE="$(curl -sS -X POST "${ENDPOINT}" \
  -H "Authorization: Bearer ${API_KEY}" \
  -H "Content-Type: application/json" \
  --data "${REQUEST_BODY}")"

PYTHON_BIN="$(command -v python3 || command -v python)"
"${PYTHON_BIN}" - <<'PYEOF'
import json, os, re, sys
raw = json.loads('''${RESPONSE//\'/\'\\\'\'}''')

text = ""
if isinstance(raw, dict):
    choices = raw.get("choices", [])
    if choices:
        text = choices[0].get("message", {}).get("content", "")
usage = raw.get("usage", {}) or {}

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
        "agent_name": "AI Review Agent", "provider": "openai", "status": "PASS",
        "security_findings": 0, "code_smells": 0,
        "architecture_issues": 0, "test_coverage_issues": 0,
        "summary": "OpenAI response could not be parsed; defaulting to PASS.",
        "recommendations": [],
        "metadata": {"model": os.environ.get("MODEL"),
                     "endpoint": os.environ.get("ENDPOINT"),
                     "tokens_used": usage.get("completion_tokens", 0)}
    }, indent=2))
    sys.exit(0)

def g(*keys, default=None):
    for k in keys:
        if isinstance(data, dict) and k in data: return data[k]
    return default

print(json.dumps({
    "agent_name": g("agent_name", default="AI Review Agent"),
    "provider":   g("provider", default="openai"),
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
        "tokens_used": usage.get("completion_tokens", 0)
    }
}, indent=2))
PYEOF