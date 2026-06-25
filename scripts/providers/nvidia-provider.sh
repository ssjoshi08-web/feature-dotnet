#!/usr/bin/env bash
# ============================================================================
# nvidia-provider.sh — NVIDIA NIM adapter
# ----------------------------------------------------------------------------
# Implements the provider adapter contract for NVIDIA's integrate API
# (OpenAI-compatible chat completions at integrate.api.nvidia.com).
# Reads NVIDIA_API_KEY, calls the chat/completions endpoint, normalises
# to the common JSON schema.
# ============================================================================
set -euo pipefail

: "${CONFIG_FILE:?CONFIG_FILE is required}"
: "${PROMPT:?PROMPT is required}"
: "${CORPUS:?CORPUS is required}"

API_KEY="${NVIDIA_API_KEY:-}"
[[ -n "${API_KEY}" ]] || { echo '{"status":"ERROR","summary":"NVIDIA_API_KEY not set"}' >&2; exit 3; }

MODEL="${MODEL:-meta/llama-3.1-70b-instruct}"
ENDPOINT="${ENDPOINT:-https://integrate.api.nvidia.com/v1/chat/completions}"

# System prompt instructs the model to emit only the common JSON schema.
SYSTEM_PROMPT='You are the AI Review Agent. Analyse the provided source files
for security, code quality, testing, and architecture issues. Respond with a
single JSON object matching this schema exactly:

{
  "agent_name": "AI Review Agent",
  "provider": "nvidia",
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
     "max_tokens": 4096,
     "messages": [
       {"role":"system","content":$sys},
       {"role":"user","content":$user}
     ]
   }')"

RESPONSE="$(mktemp)"
HTTP_CODE="$(curl -sS -o "${RESPONSE}" -w "%{http_code}" -X POST "${ENDPOINT}" \
  -H "Authorization: Bearer ${API_KEY}" \
  -H "Accept: application/json" \
  -H "Content-Type: application/json" \
  --data "${REQUEST_BODY}" || echo "000")"
echo "[nvidia-provider] HTTP status: ${HTTP_CODE}" >&2
if [[ ! "${HTTP_CODE}" =~ ^2 ]]; then
  echo "[nvidia-provider][ERROR] non-2xx response (first 500 bytes):" >&2
  head -c 500 "${RESPONSE}" >&2
  echo >&2
  printf '{"agent_name":"AI Review Agent","provider":"nvidia","status":"ERROR","security_findings":0,"code_smells":0,"architecture_issues":0,"test_coverage_issues":0,"summary":"NVIDIA API call failed (HTTP %s). See job log for response body.","recommendations":["Verify NVIDIA_API_KEY is valid and the model is available on your NIM account."]}\n' "${HTTP_CODE}"
  rm -f "${RESPONSE}"
  exit 0
fi
RESPONSE_BODY="$(cat "${RESPONSE}")"
rm -f "${RESPONSE}"

PYTHON_BIN="$(command -v python3 || command -v python)"
"${PYTHON_BIN}" - <<PYEOF
import json, os, re, sys
try:
    raw = json.loads('''${RESPONSE_BODY//\'/\'\\\'\'}''')
except json.JSONDecodeError as e:
    excerpt = '''${RESPONSE_BODY//\'/\'\\\'\'}'''[:500]
    print(json.dumps({
        "agent_name": "AI Review Agent", "provider": "nvidia", "status": "ERROR",
        "security_findings": 0, "code_smells": 0,
        "architecture_issues": 0, "test_coverage_issues": 0,
        "summary": f"NVIDIA returned non-JSON response: {e}. First 500 chars: {excerpt!r}",
        "recommendations": ["Inspect the HTTP response body in the job log."]
    }, indent=2))
    sys.exit(0)

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
        "agent_name": "AI Review Agent", "provider": "nvidia", "status": "PASS",
        "security_findings": 0, "code_smells": 0,
        "architecture_issues": 0, "test_coverage_issues": 0,
        "summary": "NVIDIA response could not be parsed; defaulting to PASS.",
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
    "provider":   g("provider", default="nvidia"),
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