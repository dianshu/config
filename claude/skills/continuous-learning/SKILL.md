---
name: continuous-learning
description: |
  Continuous learning system that extracts reusable knowledge from work sessions.
  Use when: (1) /continuous-learning command to review session learnings,
  (2) "save this as a skill" or "extract a skill from this",
  (3) "what did we learn?", (4) After non-obvious debugging (>10 min investigation),
  (5) Error resolution where error message was misleading,
  (6) Workaround discovered through trial-and-error,
  (7) Tool integration knowledge not covered by docs.
  Creates lightweight reusable skills in ~/.claude/skills/.
allowed-tools:
  - Read
  - Write
  - Edit
  - Grep
  - Glob
  - WebSearch
  - WebFetch
  - Skill
  - AskUserQuestion
---

# Continuous Learning

Extracts reusable knowledge from work sessions and codifies it as Claude Code skills. Be selective — not every task produces a skill.

## When to Extract

Extract when **all** apply:
- **Reusable** — helps with future tasks, not just this one
- **Non-trivial** — required discovery, not just doc lookup
- **Specific** — exact trigger conditions and solution can be stated
- **Verified** — solution actually worked

Typical sources: non-obvious debugging, project-specific patterns, tool/API integration knowledge not in docs, misleading error messages, multi-step workflow optimizations.

## Extraction Process

### Step 1: Check for existing skills

Search before creating:
- `Glob` `~/.claude/skills/*/SKILL.md` to list all
- `Grep` keywords across `~/.claude/skills/` and `.claude/skills/`
- `Grep -F` exact error messages

| Found                                            | Action                                          |
|--------------------------------------------------|-------------------------------------------------|
| Nothing related                                  | Create new                                      |
| Same trigger and same fix                        | Update existing (bump version)                  |
| Same trigger, different root cause               | Create new, add `See also:` links both ways     |
| Partial overlap (same domain, different trigger) | Update existing with new "Variant" subsection   |
| Same domain, different problem                   | Create new, add `See also:` in Notes            |
| Stale or wrong                                   | Mark deprecated in Notes, link to replacement   |

Versioning: patch = wording, minor = new scenario, major = breaking change.

### Step 2: Identify the knowledge

- What was the problem?
- What was non-obvious about the solution?
- What are the exact trigger conditions (errors, symptoms, contexts)?

### Step 3: Research best practices (when applicable)

Search the web when the topic involves specific technologies, frameworks, or APIs that may have evolved. Skip for project-specific internal patterns or stable generic concepts.

Search strategy: official docs first, then best practices, then common-issue threads. Always cite sources in a `References` section.

### Step 4: Structure the skill

```markdown
---
name: [kebab-case-name]
description: |
  [Specific use cases, trigger conditions (exact errors/symptoms),
  what problem this solves. Specific enough that semantic matching
  surfaces it when relevant.]
version: 1.0.0
date: [YYYY-MM-DD]
allowed-tools:
  - [tools needed]
---

# [Name]

## Problem
## Context / Trigger Conditions
## Solution
## Verification
## Example
## Notes
## References   (only if web sources cited)
```

### Step 5: Write effective descriptions

Include: specific symptoms (exact errors), context markers (framework/file/tool names), action phrases ("Use when…").

Bad: `Helps with React problems`
Good: `Fix for "ENOENT: no such file" in npm workspaces. Use when (1) npm run fails with ENOENT in a workspace, (2) paths work in root but not packages.`

### Step 6: Save and mirror

- Project-specific: `.claude/skills/[name]/SKILL.md`
- User-wide: `~/.claude/skills/[name]/SKILL.md`
- Helper scripts: `scripts/` subdir

After saving to `~/.claude/skills/`, mirror to `~/repos/config/claude/skills/` (`~/.claude/` is source of truth). Then `/push` the config repo.

## Retrospective mode (`/continuous-learning`)

1. Review conversation history for extractable knowledge
2. List candidates with brief justification
3. Prioritize highest-value, most reusable
4. Extract top 1–3 candidates
5. Report what was created and why

## Anti-patterns

- **Over-extraction** — mundane solutions don't need preservation
- **Vague descriptions** — won't surface when needed
- **Unverified solutions** — only extract what worked
- **Documentation duplication** — link to official docs, add what's missing
- **No version/date** — knowledge becomes stale
