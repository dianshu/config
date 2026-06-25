---
name: continuous-learning
description: |
  Harvest reusable lessons from a work session and codify each as a Claude Code
  skill in the current project. Use when: the user runs /continuous-learning or
  asks "what did we learn?" (sweep the whole session); the user says "save this as
  a skill" / "extract a skill from this"; or a hard-won lesson just surfaced — a
  misleading error, a trial-and-error workaround, undocumented tool/API behavior,
  or a non-obvious fix after long debugging.
allowed-tools:
  - Read
  - Write
  - Edit
  - Grep
  - Glob
  - Skill
  - AskUserQuestion
---

# Continuous Learning

Harvest **lessons** from a work session and codify each as a skill. A lesson is hard-won, reusable knowledge — not the task's output. Be selective: most sessions yield none.

## What counts as a lesson

Codify only when **all four** hold:

- **Reusable** — bears on future tasks, not just this one.
- **Non-trivial** — took discovery, not a doc lookup.
- **Specific** — you can state the exact trigger and the fix.
- **Verified** — the fix actually worked.

Richest sources: non-obvious debugging, misleading error messages, trial-and-error workarounds, project-specific patterns, tool/API behavior the docs don't mention.

## Process

### Step 1: Search for an existing home

First find where this lesson might already live:

- `Glob` `.claude/skills/*/SKILL.md` (this project) — the dispatch table below operates here.
- `Grep` the lesson's keywords across that dir; `Grep -F` exact error strings.
- Also `Glob` `~/.claude/skills/*/SKILL.md` read-only: if the lesson already lives in a user-global skill, cross-link it — never edit it here (promotion is a separate call, Step 5).

Then dispatch every project-local skill you found:

| Found                                              | Action                                       |
|----------------------------------------------------|----------------------------------------------|
| Nothing related                                    | Create new                                   |
| Same trigger, same fix                             | Update in place, bump version                |
| Related but distinct (other root cause or problem) | Create new; cross-link `See also:` both ways |
| Partial overlap (same domain, new trigger)         | Add a "Variant" subsection to the existing   |
| Stale or wrong                                     | Mark deprecated, link to the replacement     |

Version bumps: patch = wording, minor = new scenario, major = breaking change.

**Done when** every related skill found maps to one row, and every modify action targets a project-local file.

### Step 2: State the lesson in one sentence

Write it as *trigger → the non-obvious insight → the fix that worked*. If you can't say it in one sentence with a concrete trigger, it isn't specific enough — drop it.

### Step 3: Check current practice (only if the lesson touches external tech)

When the lesson involves a framework / API / tool that evolves, reconcile it against current official sources before codifying, using whatever web-research tooling this session provides. Cite each source in a `References` section, and capture only what the docs *don't* already say. Skip entirely for project-internal patterns and stable generic concepts.

**Done when** the lesson is reconciled against the current official source and `References` cites each source consulted.

### Step 4: Draft the skill, the writing-skills way

Read `~/.claude/skills/writing-skills/SKILL.md` — the authority on skill craft — and apply it. Beyond what it covers, three emphases matter most for an extracted lesson:

- **One leading word.** Anchor the new skill on a pretrained token it can think with (writing-skills explains how to pick one).
- **Description = triggers.** Spend the description on exact errors, symptoms, and tool names — one per distinct branch.
  - Bad: `Helps with React problems`
  - Good: `Fix for "ENOENT: no such file" in npm workspaces. Use when npm run fails with ENOENT in a workspace but paths work from root.`
- **No boilerplate.** Include only what this lesson needs; a two-line fix is two lines. Don't revive the old Problem / Context / Solution / Verification / Example scaffold.

Minimal frontmatter:

```yaml
---
name: kebab-case-name
description: <what it does> + <exact trigger phrases>
version: 1.0.0
date: YYYY-MM-DD
allowed-tools: [only what it uses]
---
```

**Done when** the draft satisfies writing-skills and all three emphases — one leading word carrying the behavior, a triggers-only description, and no boilerplate sections.

### Step 5: Place it in the current project

Save into the **current project**, never the user-global dir. Execute the Step 1 dispatch outcome:

- **Create new** → `.claude/skills/<name>/SKILL.md` (+ `scripts/` for helpers), or fold a lesson that fits existing docs into `CLAUDE.md` instead of a new skill.
- **Update in place / Variant** → edit the matched project-local skill and bump its version.
- **Deprecated** → mark the old skill in place and link the replacement.

Don't judge whether the lesson is globally useful. Promotion to `~/.claude/skills/` is a separate call the user makes later.

## Retrospective sweep (`/continuous-learning`)

When invoked to review a whole session:

1. Sweep the conversation for lesson candidates.
2. List them, each with a one-line justification against the four-part bar.
3. Keep the highest-value, most reusable 1–3; drop the rest.
4. Run the Process above on each survivor.
5. Report what you created or updated, and why.
