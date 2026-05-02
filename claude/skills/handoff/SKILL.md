---
name: handoff
description: Use when the user wants to save session state for later, says "handoff", "save session", "保存进度", "写 handoff", or wants to resume a previous session via "/handoff resume", "继续上次", "读 HANDOFF". Replaces auto-compact with a human-curated HANDOFF.md at the project root.
---

# Handoff

Curated session handoff via `./HANDOFF.md` at the project root. Two modes:

- **create** (default, `/handoff`): summarize current session into `HANDOFF.md`
- **resume** (`/handoff resume`): read `HANDOFF.md`, validate environment, brief the user, wait for confirmation

The file is always at the **project root**, named **`HANDOFF.md`** (uppercase), single file, overwritten each time. Do not manage `.gitignore` — the user handles that manually.

## Mode selection

1. If the user invoked `/handoff resume` → **resume mode**.
2. Otherwise → **create mode**, with one detection step:
   - If `HANDOFF.md` exists at the project root and its mtime is **less than 12 hours ago**, ask: *"Detected HANDOFF.md (modified Xh ago). Resume from it, or overwrite with a new handoff?"* — branch on the answer.
   - If `HANDOFF.md` exists but mtime ≥ 12h → overwrite without asking.
   - If `HANDOFF.md` does not exist → create directly.

For resume mode when `HANDOFF.md` is missing → tell the user *"No HANDOFF.md found. Run `/handoff` to create one?"* and stop.

## Create mode

### 1. Gather evidence

Run these in parallel and use their output as grounding for section content. Do not skip — handoffs written from conversation memory alone tend to miss what actually happened.

```bash
git status --porcelain=v2 --branch
git diff --stat
git log -5 --oneline
git rev-parse HEAD
git rev-parse --abbrev-ref HEAD
```

If not in a git repo, skip git commands and use `Branch: -` and `Last commit: -` in the metadata line.

### 2. Determine "关键文件路径" candidates

Take the set of files that were Read / Edit / Write'd during this session, intersect with files tracked by git (`git ls-files`), and let the model filter to those that the next step will actually touch again. If the session has no such files, leave the section empty and warn the user before writing (see edge case below).

### 3. Generate the file

Write to `./HANDOFF.md` (project root) with this exact structure:

```markdown
# HANDOFF
_Generated: YYYY-MM-DD HH:MM | Branch: <branch> | Last commit: <short-sha>_

## 当前在做什么

<1-3 sentences. The current task and where it stands right now.>

## 已经试过的方案和结果(含失败的)

<Bullet list. Include failed attempts and why they failed — this is the highest-value section for resume.>

## 下一步计划

1. <actionable step>
2. <actionable step>
3. <actionable step>
<3-5 items. Each must be concretely actionable, not "investigate X".>

## 关键文件路径

- <relative/path/to/file>
- <relative/path/to/file>

## 还没搞清楚的问题

<Open questions, unknowns, things to verify. May be empty.>
```

Use **half-width** punctuation in section headings exactly as shown above (`(` not `(`, `)` not `)`) — full-width characters break grep-based section detection.

### 4. Preview and confirm

Show the generated content (or a diff against the existing HANDOFF.md) and ask: *"OK to write? Anything to change?"*

- User says OK → write the file, done.
- User says change X → edit in place, re-show, ask again.
- User says cancel → do not write, exit.

### Edge case: thin session

If the session has produced no Read/Edit/Write activity (or none on tracked files), warn before writing: *"This session hasn't touched tracked files yet. Handoff will be sparse. Continue anyway?"*

## Resume mode

### 1. Read

Read `./HANDOFF.md` in full.

### 2. Validate environment drift

Run all three checks. Surface every mismatch found.

```bash
git rev-parse --abbrev-ref HEAD       # compare to "Branch:" in metadata
git rev-parse HEAD                     # compare to "Last commit:" in metadata
```

For each path under `## 关键文件路径`, verify it exists.

Drift output template:
- Branch differs: *"Branch was `<old>` when handoff was written, now `<new>`. Continue?"*
- HEAD differs: *"HEAD has moved from `<old>` to `<new>` (N commits). Files may have changed."*
- Missing files: list each missing path.

If any drift is detected, ask the user to confirm before continuing. If user says continue, drop it and move on.

### 3. Brief

Produce a 3-5 line summary covering:
- What was being done (from `## 当前在做什么`)
- Step 1 of `## 下一步计划` verbatim
- Any unresolved blockers from `## 还没搞清楚的问题` that affect step 1

End with: *"Start from step 1, or jump to a different step?"*

### 4. Wait

**Do not** auto-execute the next step. Wait for the user to confirm or redirect. Do not pre-read files in `## 关键文件路径` — read on demand once the user picks a step. The whole point of handoff is to avoid burning context on speculative reads.

### Edge case: malformed HANDOFF.md

If a section is missing or empty, mark it `(missing)` in the brief and continue. Do not refuse to resume.

## What this skill does not do

- Does not modify `.gitignore` (global or local) — user handles manually.
- Does not register hooks or change `settings.json`.
- Does not auto-create handoffs at session end or context-usage thresholds.
- Does not run build/test to verify environment on resume.
- Does not diff the codebase against handoff state.
