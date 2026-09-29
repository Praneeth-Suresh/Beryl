#!/usr/bin/env python3
"""Render a safe, self-contained codebase-understanding artifact.

The input is intentionally data, never HTML.  This keeps inspected repository
content passive when an agent turns an explanation into a local web page.
"""

from __future__ import annotations

import argparse
import html
import json
from pathlib import Path
from typing import Any


def text(value: Any) -> str:
    """Return untrusted content safe for HTML text and attributes."""
    return html.escape(str(value), quote=True)


def code(value: Any) -> str:
    return html.escape(str(value), quote=False)


def render_section(section: dict[str, Any], index: int) -> str:
    heading = text(section.get("heading", f"Section {index}"))
    source = text(section.get("source", "Illustrative explanation"))
    body = "\n".join(f"<p>{text(item)}</p>" for item in section.get("body", []))
    blocks = "\n".join(
        f"<figure><figcaption>{text(block.get('label', 'Source excerpt'))}</figcaption>"
        f"<pre><code>{code(block.get('code', ''))}</code></pre></figure>"
        for block in section.get("code_blocks", [])
    )
    return (
        f'<section id="section-{index}" aria-labelledby="heading-{index}">'
        f'<div class="section-mark">{index:02d}</div><div><p class="provenance">{source}</p>'
        f'<h2 id="heading-{index}">{heading}</h2>{body}{blocks}</div></section>'
    )


def render_quiz(question: dict[str, Any], index: int) -> str:
    options = question.get("options", [])
    option_html = "".join(
        f'<button type="button" class="answer" data-correct="{str(option.get("correct", False)).lower()}" '
        f'data-explanation="{text(option.get("explanation", ""))}" '
        f'data-reference="{text(question.get("reference", ""))}">{text(option.get("text", ""))}</button>'
        for option in options
    )
    return (
        f'<article class="question"><h3>{index}. {text(question.get("prompt", ""))}</h3>'
        f'<div class="answers" role="group" aria-label="Question {index}">{option_html}</div>'
        '<p class="feedback" aria-live="polite" hidden></p></article>'
    )


def render(data: dict[str, Any]) -> str:
    title = text(data.get("title", "Codebase field notes"))
    subtitle = text(data.get("subtitle", "An offline understanding artifact"))
    sections = "\n".join(render_section(item, i) for i, item in enumerate(data.get("sections", []), 1))
    quiz = "\n".join(render_quiz(item, i) for i, item in enumerate(data.get("quiz", []), 1))
    provenance = "\n".join(f"<li>{text(item)}</li>" for item in data.get("provenance", []))
    return f'''<!doctype html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<title>{title}</title><style>
:root {{ color-scheme: light; --ink:#15211e; --paper:#eff5ef; --moss:#1c5b48; --sun:#e9a63a; --line:#b8c9bd; --muted:#496057; }}
* {{ box-sizing:border-box }} body {{ margin:0; color:var(--ink); background:var(--paper); font:17px/1.55 Georgia,serif }}
main {{ max-width:980px; margin:auto; padding:clamp(1.2rem,4vw,4rem) }} header {{ border-bottom:5px solid var(--moss); padding-bottom:2rem; margin-bottom:2.5rem }}
.eyebrow,.provenance {{ font:700 .78rem/1.2 ui-monospace,monospace; letter-spacing:.08em; text-transform:uppercase; color:var(--moss) }} h1 {{ max-width:14ch; font:700 clamp(2.5rem,9vw,6.5rem)/.9 Georgia,serif; margin:.4rem 0 }} h2 {{ font-size:clamp(1.5rem,4vw,2.7rem); line-height:1.05; margin:.2rem 0 1rem }}
section {{ display:grid; grid-template-columns:4rem 1fr; gap:1rem; border-bottom:1px solid var(--line); padding:2rem 0 }} .section-mark {{ color:var(--sun); font:700 1.35rem ui-monospace,monospace }}
pre {{ overflow:auto; padding:1rem; background:#12211d; color:#e8f6eb; border-left:5px solid var(--sun) }} figure {{ margin:1.5rem 0 }} figcaption {{ font:700 .85rem ui-monospace,monospace; color:var(--muted) }}
.quiz {{ margin-top:3rem; padding:clamp(1rem,4vw,2.5rem); background:#fffdf5; border:2px solid var(--moss) }} .question {{ border-top:1px solid var(--line); padding:1.2rem 0 }} .question:first-of-type {{ border:0 }} .answers {{ display:grid; gap:.6rem }} button {{ text-align:left; padding:.75rem; color:inherit; background:white; border:1px solid var(--moss); font:inherit; cursor:pointer }} button:hover,button:focus-visible {{ outline:3px solid var(--sun); outline-offset:2px }} button[disabled] {{ cursor:default }} .feedback {{ padding:.8rem; background:#e4f0e7 }} footer {{ margin-top:3rem; color:var(--muted); font-size:.9rem }}
@media (max-width:560px) {{ section {{ grid-template-columns:1fr }} .section-mark {{ order:2 }} }} @media (prefers-reduced-motion:reduce) {{ * {{ scroll-behavior:auto!important }} }}
</style></head><body><main><header><p class="eyebrow">Offline field notes · illustrative, not live execution</p><h1>{title}</h1><p>{subtitle}</p></header>
{sections}<section class="quiz" aria-labelledby="quiz-heading"><div><p class="provenance">Understanding check</p><h2 id="quiz-heading">Test the mental model</h2><p>Choose an answer to see why it is right or wrong.</p>{quiz}</div></section>
<footer><p>Source provenance</p><ul>{provenance}</ul><p>Assumptions and open questions should be reviewed with the artifact author.</p></footer></main>
<script>document.querySelectorAll('.answer').forEach(function(button){{button.addEventListener('click',function(){{var group=button.closest('.answers');group.querySelectorAll('button').forEach(function(item){{item.disabled=true}});var feedback=group.parentElement.querySelector('.feedback');var answer=button.dataset.correct==='true'?'Correct. ':'Not quite. ';feedback.textContent=answer+button.dataset.explanation+(button.dataset.reference?' See '+button.dataset.reference+'.':'');feedback.hidden=false;}});}});</script>
</body></html>'''


def main() -> None:
    parser = argparse.ArgumentParser(description="Render a safe offline understanding artifact")
    parser.add_argument("content", type=Path, help="structured JSON content")
    parser.add_argument("output", type=Path, help="output index.html")
    args = parser.parse_args()
    data = json.loads(args.content.read_text(encoding="utf-8"))
    if len(data.get("quiz", [])) != 5:
        raise SystemExit("content must contain exactly five quiz questions")
    if any(len(question.get("options", [])) < 2 for question in data["quiz"]):
        raise SystemExit("each quiz question needs at least two options")
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(render(data), encoding="utf-8")


if __name__ == "__main__":
    main()
