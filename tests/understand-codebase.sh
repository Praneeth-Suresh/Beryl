#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/beryl-understand-codebase.XXXXXX")"
trap 'rm -rf "${TMP_DIR}"' EXIT

python3 - "${TMP_DIR}/content.json" <<'PY'
import json
import sys
content = {
  "title": "Hostile <script>alert(1)</script>",
  "subtitle": "A safe artifact",
  "sections": [{"heading": "Observed facts", "body": ["<img src=x onerror=alert(1)>"], "code_blocks": [{"label": "fixture", "code": "  if (x < y):\n    pass"}]}],
  "provenance": ["tests/fixture:1"],
  "quiz": [{"prompt": f"Question {i}", "reference": "section-1", "options": [{"text": "Plausible wrong answer", "correct": False, "explanation": "Why this is wrong"}, {"text": "Correct answer", "correct": True, "explanation": "Why this is right"}]} for i in range(1, 6)]
}
with open(sys.argv[1], "w", encoding="utf-8") as out:
    json.dump(content, out)
PY

python3 "${REPO_ROOT}/.beryl/agent/skills/understand-codebase/scripts/render_artifact.py" "${TMP_DIR}/content.json" "${TMP_DIR}/index.html"
artifact="${TMP_DIR}/index.html"

grep -Fq '<!doctype html>' "${artifact}"
grep -Fq '&lt;script&gt;alert(1)&lt;/script&gt;' "${artifact}"
grep -Fq '&lt;img src=x onerror=alert(1)&gt;' "${artifact}"
grep -Fq '  if (x &lt; y):' "${artifact}"
grep -Fq 'aria-live="polite"' "${artifact}"
grep -Fq 'button.addEventListener' "${artifact}"
[[ "$(grep -o 'class="question"' "${artifact}" | wc -l | tr -d ' ')" == "5" ]]
! grep -Eq 'https?://|<script>alert|<img src=x' "${artifact}"

printf 'understand-codebase tests passed\n'
