#!/usr/bin/env bash
# Regression test for the safe interactive understanding artifact renderer.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
renderer="${repo_root}/.beryl/agent/skills/understand-codebase/scripts/render_artifact.py"
tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/beryl-understand.XXXXXX")"
trap 'rm -rf "${tmp_dir}"' EXIT

cat >"${tmp_dir}/content.json" <<'JSON'
{
  "title": "Renderer fixture",
  "sections": [{"heading": "Background", "body": ["<script>alert('injected')</script>"],
    "playground": {"title": "Toy state", "controls": [{"id": "n", "label": "Count", "min": 0, "max": 10, "value": 2}],
      "outputs": [{"id": "result", "label": "Result", "template": "count={n}"}]}}],
  "quiz": [
    {"prompt": "Question 1", "reference": "fixture:1", "options": [{"text": "A", "correct": true, "explanation": "yes"}, {"text": "B", "correct": false, "explanation": "no"}]},
    {"prompt": "Question 2", "options": [{"text": "A", "correct": true, "explanation": "yes"}, {"text": "B", "correct": false, "explanation": "no"}]},
    {"prompt": "Question 3", "options": [{"text": "A", "correct": true, "explanation": "yes"}, {"text": "B", "correct": false, "explanation": "no"}]},
    {"prompt": "Question 4", "options": [{"text": "A", "correct": true, "explanation": "yes"}, {"text": "B", "correct": false, "explanation": "no"}]},
    {"prompt": "Question 5", "options": [{"text": "A", "correct": true, "explanation": "yes"}, {"text": "B", "correct": false, "explanation": "no"}]}
  ],
  "provenance": ["fixture"]
}
JSON

python3 "${renderer}" "${tmp_dir}/content.json" "${tmp_dir}/index.html"
grep -Fq '&lt;script&gt;alert' "${tmp_dir}/index.html"
! grep -Fq '<script>alert' "${tmp_dir}/index.html"
grep -Fq 'data-playground-control="n"' "${tmp_dir}/index.html"
[[ "$(grep -o 'class="question"' "${tmp_dir}/index.html" | wc -l)" -eq 5 ]]
grep -Fq 'Table of contents' "${tmp_dir}/index.html"
printf 'understand-codebase tests passed\n'
