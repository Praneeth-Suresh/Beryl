# Beryl bootstrap request

Repository: {target_dir}
Source ref: {source_ref}
Installer version: {installer_version}
Profile: {profile}
Runner policy: {policy}
Runner: {runner}
Status file target: {status_file}

Fill the following required files under `.beryl/agent/` so this repository has
repo-specific context:

{required_files}

Use this strict scope:
- Read and edit **only** files under `.beryl/agent/` with extension `.md`.
- Do not create, modify, or remove files outside `.beryl/agent/*.md`.
- Do not modify files outside this scope.

For each required file, replace install template placeholders with concrete
repository-specific details:
- project-brief.md
- architecture.md
- design-tree.md
- testing-policy.md
- ubiquitous-language.md
- agent-rules.md
- task-routing.md

After writing, leave them with complete content and no placeholder bracket tokens.

If files are already complete, leave them unchanged.
