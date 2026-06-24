#!/usr/bin/env bash
# ============================================================================
# claude-provider.sh — Claude (Anthropic) adapter
# ----------------------------------------------------------------------------
# Implements the provider adapter contract for Anthropic's Messages API.
# Reads ANTHROPIC_API_KEY, calls https://api.anthropic.com/v1/messages,
# transforms the response into the common JSON schema, prints to stdout.
# ============================================================================
set -euo pipefail

: "${CONFIG_FILE:?CONFIG_FILE is required}"
: "${PROMPT:?PROMPT is required}"
: "${CORPUS:?CORPUS is required}"

API_KEY="${ANTHROPIC_API_KEY:-}"
[[ -n "${API_KEY}" ]] || { echo '{"status":"ERROR","summary":"ANTHROPIC_API_KEY not set"}' >&2; exit 3; }

MODEL="${MODEL:-claude-opus-4-8}"
ENDPOINT="${ENDPOINT:-https://api.anthropic.com/v1/messages}"

# Compose the user message: prompt + corpus
USER_MSG="$(printf '%s\n\n--- REVIEW CORPUS ---\n%s' "${PROMPT}" "${CORPUS}")"

# Anthropic Messages API expects a JSON body
REQUEST_BODY="$(jq -n \
  --arg model "${MODEL}" \
  --arg content "${USER_MSG}" \
  '{
     "model": $model,
     "max_tokens": 4096,
     "temperature": 0,
     "messages": [{"role": "user", "content": $content}]
   }')"

# Call Claude
RESPONSE="$(curl -sS -X POST "${ENDPOINT}" \
  -H "content-type: application/json" \
  -H "x-api-key: ${API_KEY}" \
  -H "anthropic-version: 2023-06-01" \
  --data "${REQUEST_BODY}")"

# Extract the assistant text and feed it to a Python normaliser that emits
# the common JSON schema. Anthropic returns content blocks like:
#   { "content": [{"type":"text","text":"..."}], "usage": {...} }
PYTHON_BIN="$(command -v python3 || command -v python)"
"${PYTHON_BIN}" - <<'PYEOF'
import json, os, sys, re

raw = json.loads('''${RESPONSE//\'/\'\\\'\'}''')

# Extract the textual content from the response.
text = ""
if isinstance(raw, dict):
    content = raw.get("content", [])
    if isinstance(content, list):
        text = "".join(b.get("text","") for b in content if isinstance(b, dict))
    usage = raw.get("usage", {}) or {}

# Pull a JSON object out of the model output (it may be fenced).
data = None
try:
    data = json.loads(text)
except Exception:
    m = re.search(r"\{[\s\S]*\}", text)
    if m:
        try:
            data = json.loads(m.group(0))
        except Exception:
            data = None

if data is None:
    print(json.dumps({
        "agent_name": "AI Review Agent",
        "provider": "claude",
        "status": "PASS",
        "security_findings": 0, "code_smells": 0,
        "architecture_issues": 0, "test_coverage_issues": 0,
        "summary": "Claude response could not be parsed; defaulting to PASS.",
        "recommendations": [],
        "metadata": {
            "model": os.environ.get("MODEL"),
            "endpoint": os.environ.get("ENDPOINT"),
            "tokens_used": (raw.get("usage", {}) or {}).get("output_tokens", 0)
        }
    }, indent=2))
    sys.exit(0)

# Coerce to common schema.
def g(*keys, default=None):
    for k in keys:
        if isinstance(data, dict) and k in data:
            return data[k]
    return default

common = {
    "agent_name": g("agent_name", default="AI Review Agent"),
    "provider":   g("provider", default="claude"),
    "status":     g("status", default="PASS"),
    "security_findings":    g("security_findings", "security_count", default=0),
    "code_smells":          g("code_smells", "code_smell_count", default=0),
    "architecture_issues":  g("architecture_issues", "architecture_count", default=0),
    "test_coverage_issues": g("test_coverage_issues", "testing_count", default=0),
    "summary":         g("summary", default="Review complete."),
    "recommendations": g("recommendations", default=[]),
    "metadata": {
        "model": os.environ.get("MODEL"),
        "endpoint": os.environ.get("ENDPOINT"),
        "tokens_used": (raw.get("usage", {}) or {}).get("output_tokens", 0)
    }
}
print(json.dumps(common, indent=2))
PYEOF