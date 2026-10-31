# Vendored Skills

These skills are copied unchanged from established open-source skill
collections. Each directory keeps its upstream licence file. Do not edit the
vendored files in place. To update one, copy the upstream directory again at a
new commit and update the commit in this table.

| Skill | Upstream repository | Upstream path | Commit | Licence |
| --- | --- | --- | --- | --- |
| `systematic-debugging` | <https://github.com/obra/superpowers> | `skills/systematic-debugging` | `2ce8aa15d05bd57213e6f746f953aafb7ded7a8b` | MIT, Copyright (c) 2025 Jesse Vincent |
| `test-driven-development` | <https://github.com/obra/superpowers> | `skills/test-driven-development` | `2ce8aa15d05bd57213e6f746f953aafb7ded7a8b` | MIT, Copyright (c) 2025 Jesse Vincent |
| `verification-before-completion` | <https://github.com/obra/superpowers> | `skills/verification-before-completion` | `2ce8aa15d05bd57213e6f746f953aafb7ded7a8b` | MIT, Copyright (c) 2025 Jesse Vincent |
| `grill-me` | <https://github.com/mattpocock/skills> | `skills/productivity/grill-me` | `a496f5513d4a4cf889bc48e189e579f4b0bdf6aa` | MIT, Copyright (c) 2026 Matt Pocock |
| `grilling` | <https://github.com/mattpocock/skills> | `skills/productivity/grilling` | `a496f5513d4a4cf889bc48e189e579f4b0bdf6aa` | MIT, Copyright (c) 2026 Matt Pocock |
| `frontend-design` | <https://github.com/anthropics/skills> | `skills/frontend-design` | `ca45fc496a3436251f191354091d557da31c15b5` | Apache-2.0 (`LICENSE.txt`) |

Upstream `grill-me` is a one-line entry point that runs `grilling`, so both are
vendored.

Some vendored text names skills with an upstream prefix, such as
`superpowers:test-driven-development`. In this repository, load the skill with
the same name from `.beryl/agent/skills/`.
