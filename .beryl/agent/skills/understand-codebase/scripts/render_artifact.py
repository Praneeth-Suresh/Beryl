#!/usr/bin/env python3
"""Render a safe, self-contained codebase-understanding artifact."""

from __future__ import annotations

import argparse
import html
import json
from pathlib import Path
from typing import Any


def esc(value: Any, *, quote: bool = True) -> str:
    return html.escape(str(value), quote=quote)


def section_html(section: dict[str, Any], index: int) -> str:
    heading = esc(section.get("heading", f"Section {index}"))
    body = "".join(f"<p>{esc(item)}</p>" for item in section.get("body", []))
    code = "".join(
        f"<figure><figcaption>{esc(block.get('label', 'Source excerpt'))}</figcaption>"
        f"<pre><code>{esc(block.get('code', ''), quote=False)}</code></pre></figure>"
        for block in section.get("code_blocks", [])
    )
    before_after = ""
    if section.get("before") or section.get("after"):
        before_after = (
            '<div class="compare">'
            f'<div><p class="eyebrow">Before</p><p>{esc(section.get("before", ""))}</p></div>'
            f'<div><p class="eyebrow">After</p><p>{esc(section.get("after", ""))}</p></div>'
            "</div>"
        )
    playground = playground_html(section.get("playground"))
    return (
        f'<section id="section-{index}" aria-labelledby="heading-{index}">'
        f'<div class="section-mark">{index:02d}</div><div>'
        f'<p class="provenance">{esc(section.get("source", "Illustrative explanation"))}</p>'
        f'<h2 id="heading-{index}">{heading}</h2>{body}{before_after}{playground}{code}'
        "</div></section>"
    )


def playground_html(playground: dict[str, Any] | None) -> str:
    if not playground:
        return ""
    controls = "".join(
        f'<label>{esc(control.get("label", control["id"]))} '
        f'<input type="range" data-playground-control="{esc(control["id"])}" '
        f'min="{esc(control.get("min", 0))}" max="{esc(control.get("max", 10))}" '
        f'value="{esc(control.get("value", 0))}" step="{esc(control.get("step", 1))}"> '
        f'<output data-playground-value="{esc(control["id"])}"></output></label>'
        for control in playground.get("controls", [])
    )
    outputs = "".join(
        f'<p><strong>{esc(output.get("label", "Output"))}:</strong> '
        f'<span data-playground-output="{esc(output["id"])}" '
        f'data-playground-template="{esc(output.get("template", ""))}"></span></p>'
        for output in playground.get("outputs", [])
    )
    return (
        '<aside class="playground" aria-label="Interactive illustrative model">'
        f'<p class="eyebrow">Micro-world · illustrative model</p>'
        f'<h3>{esc(playground.get("title", "Explore the model"))}</h3>'
        f'<p>{esc(playground.get("description", "Adjust the controls to explore the relationship."))}</p>'
        f'<div class="controls">{controls}</div><div class="outputs">{outputs}</div></aside>'
    )


def quiz_html(question: dict[str, Any], index: int) -> str:
    options = "".join(
        f'<button type="button" class="answer" data-correct="{str(option.get("correct", False)).lower()}" '
        f'data-explanation="{esc(option.get("explanation", ""))}" '
        f'data-reference="{esc(question.get("reference", ""))}">{esc(option.get("text", ""))}</button>'
        for option in question.get("options", [])
    )
    return (
        f'<article class="question"><h3>{index}. {esc(question.get("prompt", ""))}</h3>'
        f'<div class="answers" role="group" aria-label="Question {index}">{options}</div>'
        '<p class="feedback" aria-live="polite" hidden></p></article>'
    )


def render(data: dict[str, Any]) -> str:
    title = esc(data.get("title", "Codebase field notes"))
    subtitle = esc(data.get("subtitle", "An offline understanding artifact"))
    sections = data.get("sections", [])
    toc = "".join(f'<li><a href="#section-{i}">{esc(item.get("heading", f"Section {i}"))}</a></li>' for i, item in enumerate(sections, 1))
    content = "".join(section_html(item, i) for i, item in enumerate(sections, 1))
    quiz = "".join(quiz_html(item, i) for i, item in enumerate(data.get("quiz", []), 1))
    provenance = "".join(f"<li>{esc(item)}</li>" for item in data.get("provenance", []))
    return f'''<!doctype html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>{title}</title><style>
:root{{--ink:#15211e;--paper:#eff5ef;--moss:#1c5b48;--sun:#e9a63a;--line:#b8c9bd;--muted:#496057}}
*{{box-sizing:border-box}}body{{margin:0;color:var(--ink);background:var(--paper);font:17px/1.55 Georgia,serif}}
main{{max-width:980px;margin:auto;padding:clamp(1.2rem,4vw,4rem)}}header{{border-bottom:5px solid var(--moss);padding-bottom:2rem;margin-bottom:2rem}}
.eyebrow,.provenance{{font:700 .78rem/1.2 ui-monospace,monospace;letter-spacing:.08em;text-transform:uppercase;color:var(--moss)}}
h1{{max-width:14ch;font:700 clamp(2.5rem,9vw,6.5rem)/.9 Georgia,serif;margin:.4rem 0}}h2{{font-size:clamp(1.5rem,4vw,2.7rem);line-height:1.05;margin:.2rem 0 1rem}}
.toc,.compare,.playground,.quiz{{padding:1.2rem;background:#fffdf5;border:1px solid var(--line);margin:1.3rem 0}}.toc ul{{columns:2}}.toc a{{color:var(--moss)}}
section{{display:grid;grid-template-columns:4rem 1fr;gap:1rem;border-bottom:1px solid var(--line);padding:2rem 0}}.section-mark{{color:var(--sun);font:700 1.35rem ui-monospace,monospace}}
.compare{{display:grid;grid-template-columns:1fr 1fr;gap:1rem;border:2px solid var(--moss)}}.compare>div+div{{border-left:1px solid var(--line);padding-left:1rem}}
pre{{overflow:auto;padding:1rem;background:#12211d;color:#e8f6eb;border-left:5px solid var(--sun)}}figure{{margin:1.5rem 0}}figcaption{{font:700 .85rem ui-monospace,monospace;color:var(--muted)}}
.controls{{display:grid;gap:.8rem}}label{{display:grid;grid-template-columns:minmax(8rem,1fr) 2fr 3rem;gap:.7rem;align-items:center}}input{{accent-color:var(--moss)}}
.answers{{display:grid;gap:.6rem}}button{{text-align:left;padding:.75rem;color:inherit;background:white;border:1px solid var(--moss);font:inherit;cursor:pointer}}button:hover,button:focus-visible{{outline:3px solid var(--sun);outline-offset:2px}}button[disabled]{{cursor:default}}.feedback{{padding:.8rem;background:#e4f0e7}}
footer{{margin-top:3rem;color:var(--muted);font-size:.9rem}}@media(max-width:560px){{section,.compare{{grid-template-columns:1fr}}.section-mark{{order:2}}.toc ul{{columns:1}}label{{grid-template-columns:1fr}}}}
</style></head><body><main><header><p class="eyebrow">Offline field notes · illustrative, not live execution</p><h1>{title}</h1><p>{subtitle}</p></header>
<nav class="toc" aria-label="Table of contents"><p class="eyebrow">Navigate</p><ul>{toc}</ul><a href="#quiz">Jump to understanding check</a></nav>
{content}<section id="quiz" class="quiz" aria-labelledby="quiz-heading"><div><p class="provenance">Understanding check</p><h2 id="quiz-heading">Test the mental model</h2><p>Choose an answer to see why it is right or wrong.</p>{quiz}</div></section>
<footer><p>Source provenance</p><ul>{provenance}</ul><p>Review assumptions, open questions, and generated explanations before relying on them.</p></footer></main>
<script>(()=>{{const setPlayground=()=>{{document.querySelectorAll('[data-playground-control]').forEach(c=>{{const id=c.dataset.playgroundControl;const value=document.querySelector(`[data-playground-value="${{id}}"]`);if(value)value.textContent=c.value;}});document.querySelectorAll('[data-playground-output]').forEach(o=>{{let v=o.dataset.playgroundTemplate;document.querySelectorAll('[data-playground-control]').forEach(c=>{{v=v.replaceAll(`{{${{c.dataset.playgroundControl}}}}`,c.value);}});o.textContent=v;}});}};document.querySelectorAll('[data-playground-control]').forEach(c=>c.addEventListener('input',setPlayground));setPlayground();document.querySelectorAll('.answer').forEach(b=>b.addEventListener('click',()=>{{const group=b.closest('.answers');group.querySelectorAll('button').forEach(x=>x.disabled=true);const f=group.parentElement.querySelector('.feedback');f.textContent=(b.dataset.correct==='true'?'Correct. ':'Not quite. ')+b.dataset.explanation+(b.dataset.reference?' See '+b.dataset.reference+'.':'');f.hidden=false;}}));}})();</script>
</body></html>'''


def main() -> None:
    parser = argparse.ArgumentParser(description="Render a safe offline understanding artifact")
    parser.add_argument("content", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    data = json.loads(args.content.read_text(encoding="utf-8"))
    if len(data.get("quiz", [])) != 5:
        raise SystemExit("content must contain exactly five quiz questions")
    if any(len(q.get("options", [])) < 2 for q in data["quiz"]):
        raise SystemExit("each quiz question needs at least two options")
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(render(data), encoding="utf-8")


if __name__ == "__main__":
    main()
