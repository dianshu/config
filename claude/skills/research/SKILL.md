---
name: research
description: |
  Generate structured research reports. Use when the user wants to research a topic,
  compare technologies, evaluate a GitHub repo or tool, says "research", "调研", "对比",
  "评估", "compare", "evaluate", or "/research".
---

# Deep Research

Generate structured research reports through a 6-phase adaptive pipeline.

## Phase 1: SCOPE

### Step 0: Get Current Date
Run this command via Bash to get the current date. Use it in all time-sensitive searches.
```bash
date +%Y-%m-%d
```

### Step 1: Parse Query
Extract the user's research topic from the arguments. Check for `--auto` flag — if present, remove it from the topic and enable autonomous mode.

### Step 2: Check for Resume
Look for an existing `research-*/state.json` in the current directory matching this topic. If found:
- Read the state file
- Skip to the phase recorded in `state.json`
- Use the research type and settings from the state file

### Step 3: Classify Research Type
Analyze the query to determine the research type:

| Signal | Type |
|---|---|
| Multiple named entities + comparison verbs (vs, 对比, compare, 比较, versus) | **comparison** |
| Single named project/tool + decision verbs (评估, 是否, 值不值得, should I use, worth, evaluate) | **evaluation** |
| Topic/question without specific entities or decision intent | **deep** |

### Step 4: Confirm Classification
Unless `--auto` mode is enabled, present the classification to the user via `AskUserQuestion`:
- Show the detected type and extracted topic
- Let the user confirm or override

### Step 5: Initialize Output Directory
Create the output directory: `research-{topic_slug}/`

Slugify the topic: lowercase, replace spaces/special chars with hyphens, truncate to 50 chars.

Write `state.json`:
```json
{
  "phase": 1,
  "type": "comparison|evaluation|deep",
  "topic": "the research topic",
  "auto": false,
  "date": "YYYY-MM-DD",
  "topic_slug": "slugified-topic"
}
```

## Phase 2-6: Orchestration

After Phase 1 completes, sequentially invoke each sub-skill. After each phase, update `state.json` with the current phase number.

### Phase 2: STRUCTURE
Read the `research-structure` skill from `~/.claude/skills/research/skills/research-structure/SKILL.md` and follow its instructions. Pass the output directory path and state.json contents.

### Phase 3: RETRIEVE
Read the `research-retrieve` skill from `~/.claude/skills/research/skills/research-retrieve/SKILL.md` and follow its instructions.

### Phase 4: VALIDATE
Read the `research-validate` skill from `~/.claude/skills/research/skills/research-validate/SKILL.md` and follow its instructions.

### Phase 5: CRITIQUE
Read the `research-critique` skill from `~/.claude/skills/research/skills/research-critique/SKILL.md` and follow its instructions.

If `--auto` mode and the topic appears lightweight (short query, no technical depth), skip Phase 5.

### Phase 6: REPORT
Read the `research-report` skill from `~/.claude/skills/research/skills/research-report/SKILL.md` and follow its instructions.

## Completion
After Phase 6, report to the user:
- Output directory path
- Report file path (`report.md`)
- Word count
- Number of sources
- Research type used
