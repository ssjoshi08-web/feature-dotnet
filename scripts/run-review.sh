#!/usr/bin/env bash
# ============================================================================
# run-review.sh — Provider-Agnostic AI Review Orchestrator
# ----------------------------------------------------------------------------
# This is the ONLY entry point invoked by the CI workflow.
# It selects the configured provider, dispatches to the matching adapter,
# normalises the response to the common schema, applies decision logic,
# and emits review-report.json + review-summary.md.
#
# Provider selection is driven by config/ai-config.yml. No provider name
# appears in any workflow file.
# ============================================================================
set -euo pipefail

# ---------- paths & config -------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
CONFIG_FILE="${AI_CONFIG:-${REPO_ROOT}/config/ai-config.yml}"
PROVIDERS_DIR="${SCRIPT_DIR}/providers"
ARTIFACTS_DIR="${REPO_ROOT}/review-artifacts"
REPORT_JSON="${ARTIFACTS_DIR}/review-report.json"
SUMMARY_MD="${ARTIFACTS_DIR}/review-summary.md"

mkdir -p "${ARTIFACTS_DIR}"

log()  { printf '[run-review] %s\n' "$*"; }
fail() { printf '[run-review][ERROR] %s\n' "$*" >&2; exit "${2:-1}"; }

# ---------- pre-flight ------------------------------------------------------
[[ -f "${CONFIG_FILE}" ]] || fail "Config file not found: ${CONFIG_FILE}" 2
command -v python3 >/dev/null 2>&1 || command -v python >/dev/null 2>&1 \
  || fail "Python is required to parse YAML config" 2
command -v curl >/dev/null 2>&1 || fail "curl is required" 2
command -v jq >/dev/null 2>&1 || fail "jq is required" 2

# ---------- read provider from YAML ---------------------------------------
# Lightweight YAML reader — works on plain `provider: <value>` line.
read_provider() {
  local py
  py="$(command -v python3 || command -v python)"
  CONFIG_FILE="${CONFIG_FILE}" "${py}" - <<'PYEOF'
import os, re, pathlib
text = pathlib.Path(os.environ["CONFIG_FILE"]).read_text()
m = re.search(r'^\s*provider\s*:\s*([A-Za-z0-9_\-]+)', text, re.MULTILINE)
print(m.group(1) if m else "")
PYEOF
}

PROVIDER="$(read_provider)"
[[ -n "${PROVIDER}" ]] || fail "Could not determine provider from ${CONFIG_FILE}" 2
log "Active provider: ${PROVIDER}"

ADAPTER="${PROVIDERS_DIR}/${PROVIDER}-provider.sh"
[[ -f "${ADAPTER}" ]] || fail "Adapter not found for provider '${PROVIDER}': ${ADAPTER}" 2

# ---------- read model + endpoint from YAML (key/value) ------------------
read_value() {
  local key="$1"
  local py
  py="$(command -v python3 || command -v python)"
  CONFIG_FILE="${CONFIG_FILE}" "${py}" - "$key" <<'PYEOF'
import os, re, sys, pathlib
key = sys.argv[1]
path = os.environ.get("CONFIG_FILE", "")
text = pathlib.Path(path).read_text()
m = re.search(rf'^\s*{key}\s*:\s*"?([^"\n]+)"?', text, re.MULTILINE)
print(m.group(1).strip() if m else "")
PYEOF
}

MODEL="$(read_value 'model')"
ENDPOINT="$(read_value 'endpoint')"

# ---------- build the agent prompt from skills ---------------------------
build_prompt() {
  local skills_dir="${REPO_ROOT}/.github/agents"
  local prompt=""
  for skill in review-agent security-skill code-review-skill architecture-review-skill; do
    local f="${skills_dir}/${skill}.md"
    [[ -f "${f}" ]] && prompt+="\n\n===== FILE: ${f} =====\n$(cat "${f}")\n"
  done
  printf '%s' "${prompt}"
}

PROMPT="$(build_prompt)"

# ---------- gather review corpus -----------------------------------------
gather_corpus() {
  local include_exts=".cs .java .py .ts .js .go .rb .tf .yml .yaml .json"
  local out=""
  local count=0
  local max=500
  while IFS= read -r f; do
    [[ ${count} -ge ${max} ]] && break
    out+="\n----- FILE: ${f} -----\n$(cat "${REPO_ROOT}/${f}")\n"
    count=$((count + 1))
  done < <(cd "${REPO_ROOT}" && \
    find . -type f \
           \( -name '*.cs' -o -name '*.java' -o -name '*.py' -o -name '*.ts' \
           -o -name '*.js'  -o -name '*.go' -o -name '*.rb' -o -name '*.tf' \
           -o -name '*.yml' -o -name '*.yaml' -o -name '*.json' \) \
           ! -path './bin/*' ! -path '*/bin/*' \
           ! -path './obj/*' ! -path '*/obj/*' \
           ! -path './node_modules/*' ! -path '*/node_modules/*' \
           ! -path './dist/*' ! -path '*/dist/*' \
           ! -path './.git/*' ! -path '*/.git/*' \
           ! -path './vendor/*' ! -path '*/vendor/*' \
           2>/dev/null | sed 's|^\./||')
  printf '%s' "${out}"
}

CORPUS="$(gather_corpus)"
log "Corpus size: $(printf '%s' "${CORPUS}" | wc -c) bytes"

# ---------- invoke provider adapter --------------------------------------
log "Invoking adapter: ${ADAPTER}"
RAW_RESPONSE="$( \
  CONFIG_FILE="${CONFIG_FILE}" \
  MODEL="${MODEL}" \
  ENDPOINT="${ENDPOINT}" \
  PROMPT="${PROMPT}" \
  CORPUS="${CORPUS}" \
  bash "${ADAPTER}" \
)"

# ---------- normalise to common schema -----------------------------------
# Each adapter *should* already emit the common schema, but we normalise
# defensively in case vendor output is partial.
PYTHON_BIN="$(command -v python3 || command -v python)"
NORMALISED="$(PROVIDER="${PROVIDER}" CONFIG_FILE="${CONFIG_FILE}" \
             RAW_RESPONSE="${RAW_RESPONSE}" \
             "${PYTHON_BIN}" - <<'PYEOF'
import os, json, sys, re, datetime

provider = os.environ.get("PROVIDER", "unknown")
raw = os.environ.get("RAW_RESPONSE", "")

# Try direct JSON parse first
data = None
try:
    data = json.loads(raw)
except Exception:
    # Many providers wrap the JSON inside a markdown code fence.
    m = re.search(r"\{[\s\S]*\}", raw)
    if m:
        try:
            data = json.loads(m.group(0))
        except Exception:
            data = None

if data is None:
    print(json.dumps({
        "agent_name": "AI Review Agent",
        "provider": provider,
        "status": "ERROR",
        "security_findings": 0,
        "code_smells": 0,
        "architecture_issues": 0,
        "test_coverage_issues": 0,
        "summary": "Provider returned non-JSON or schema-incompatible response.",
        "recommendations": ["Inspect provider raw output and adapter transform logic."],
        "metadata": {"raw_excerpt": raw[:500]}
    }, indent=2))
    sys.exit(0)

# Map onto the common schema with safe defaults.
def n(d, *keys, default=0):
    for k in keys:
        if isinstance(d, dict) and k in d:
            return d[k]
    return default

common = {
    "agent_name": n(data, "agent_name", default="AI Review Agent"),
    "provider":   n(data, "provider", default=provider),
    "status":     n(data, "status", default="PASS"),
    "security_findings":      n(data, "security_findings", default=n(data, "security", "findings_count", default=0)),
    "code_smells":            n(data, "code_smells", default=n(data, "code_quality", "findings_count", default=0)),
    "architecture_issues":    n(data, "architecture_issues", default=n(data, "architecture", "findings_count", default=0)),
    "test_coverage_issues":   n(data, "test_coverage_issues", default=n(data, "testing", "findings_count", default=0)),
    "summary":         n(data, "summary", default=""),
    "recommendations": n(data, "recommendations", default=[]),
    "metadata":        n(data, "metadata", default={
        "model": os.environ.get("MODEL"),
        "endpoint": os.environ.get("ENDPOINT"),
        "timestamp": datetime.datetime.utcnow().isoformat() + "Z"
    })
}
print(json.dumps(common, indent=2))
PYEOF
)"

# ---------- apply decision policy ----------------------------------------
DECISION="$(PROVIDER="${PROVIDER}" NORMALISED="${NORMALISED}" \
"${PYTHON_BIN}" - <<'PYEOF'
import os, json, sys, re, pathlib
cfg_path = os.environ["CONFIG_FILE"]
provider = os.environ["PROVIDER"]
data = json.loads(os.environ["NORMALISED"])

text = pathlib.Path(cfg_path).read_text()
thr = 80
m = re.search(r"coverage_threshold_pct\s*:\s*(\d+)", text)
if m: thr = int(m.group(1))

def fail(reason):
    return {"status": "FAIL", "reason": reason}

if (data.get("security_findings", 0) or 0) > 0:
    print(json.dumps(fail("security_findings>0")))
elif (data.get("architecture_issues", 0) or 0) > 0:
    print(json.dumps(fail("architecture_issues>0")))
elif data.get("status", "").upper() == "FAIL":
    print(json.dumps(fail("provider_reported_failure")))
else:
    print(json.dumps({"status": "PASS", "reason": "no_fail_conditions_met", "threshold_pct": thr}))
PYEOF
)"

log "Decision: ${DECISION}"

# ---------- merge decision into report -----------------------------------
FINAL_JSON="$("${PYTHON_BIN}" - <<PYEOF
import json, os
data = json.loads('''${NORMALISED}''')
dec  = json.loads('''${DECISION}''')
if dec.get("status") == "FAIL":
    data["status"] = "FAIL"
    data.setdefault("recommendations", []).insert(0, f"Pipeline blocked: {dec.get('reason')}")
print(json.dumps(data, indent=2))
PYEOF
)"

echo "${FINAL_JSON}" > "${REPORT_JSON}"
log "Wrote ${REPORT_JSON}"

# ---------- generate review-summary.md -----------------------------------
PYTHON_BIN="$(command -v python3 || command -v python)"
SUMMARY="$(SUMMARY_PATH="${SUMMARY_MD}" FINAL_JSON="${FINAL_JSON}" \
"${PYTHON_BIN}" - <<'PYEOF'
import json, os
data = json.loads(os.environ["FINAL_JSON"])
recs = data.get("recommendations") or []
md = []
md.append("# AI Review Summary\n")
md.append(f"- **Provider**: `{data.get('provider','?')}`")
md.append(f"- **Status**: **{data.get('status','?')}**")
md.append(f"- **Security findings**: {data.get('security_findings',0)}")
md.append(f"- **Code smells**: {data.get('code_smells',0)}")
md.append(f"- **Architecture issues**: {data.get('architecture_issues',0)}")
md.append(f"- **Test coverage issues**: {data.get('test_coverage_issues',0)}")
md.append("")
md.append(f"> {data.get('summary','')}\n")
if recs:
    md.append("## Recommendations\n")
    for r in recs:
        md.append(f"- {r}")
open(os.environ["SUMMARY_PATH"], "w").write("\n".join(md) + "\n")
PYEOF
)"
log "Wrote ${SUMMARY_MD}"

# ---------- exit code -----------------------------------------------------
STATUS="$(printf '%s' "${FINAL_JSON}" | jq -r '.status')"
case "${STATUS}" in
  PASS) log "Review PASSED"; exit 0 ;;
  FAIL) log "Review FAILED"; exit 1 ;;
  *)    log "Review ERROR";   exit 3 ;;
esac