## Commit & Push Behavior

Do not commit or push unless explicitly requested. An implement/fix/refactor request is not an implicit commit/push request — stop at the working-tree change and report.

"Explicitly requested" means either the user's message asks for it (e.g. "commit this", "push it", "/push", "ship it", "open a PR"), or a skill the user invoked commits/pushes as part of its documented workflow (e.g. `/tdd`, `/finalize`, `/push`).

This covers every commit/push path — `git commit`, `git commit --amend`, `git push`, `gh pr create`, the `/push` skill, etc. — not just the `/push` skill.
