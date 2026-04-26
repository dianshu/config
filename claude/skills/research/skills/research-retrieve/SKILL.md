---
name: research-retrieve
description: Phase 3 of deep research - executes searches using web-search-agent with strategy modules. Supports parallel batch execution and resume.
---

# Phase 3: RETRIEVE

Execute searches to gather data for each entity, dimension, or angle.

## Inputs
- Read `state.json` from the output directory
- Read the structure file from Phase 2 (outline.yaml / eval_dimensions.yaml / search_angles.yaml)

## Resume Check
Check `data/` directory for existing JSON files. Skip any entity/angle that already has a completed JSON file.

## Search Stack
All searches use these tools (zero cost, no API keys):
- `mcp__searxng__searxng_web_search` — primary web search
- `mcp__searxng__web_url_read` — read URL content
- `mcp__chrome__new_page` + `mcp__chrome__take_snapshot` — fallback URL reading
- `gh` CLI via Bash — GitHub repository data
- HN Algolia API via `web_url_read` — Hacker News discussions

## Search Failure Handling
| Source | Failure | Action |
|---|---|---|
| SearXNG | Down/no results | Retry once, then warn and continue |
| `gh` CLI | Auth error/not found | Log error, mark dimension incomplete |
| HN Algolia | Rate limit/timeout | Skip, use SearXNG Reddit/X instead |
| Chrome MCP | Cannot render | Warn, use SearXNG snippet only |

No single failure blocks the pipeline.

## Comparison Mode

### Step 1: Read outline.yaml and fields.yaml
Parse the entity list and field definitions.

### Step 2: Batch Execution
Group entities by `batch_size` from outline.yaml.

For each batch:
1. Unless `--auto`, present the batch to the user via `AskUserQuestion` for approval
2. For each entity in the batch, spawn an Agent (subagent_type: "general-purpose") with this prompt:

```
Read the web search agent instructions at ~/.claude/skills/research/agents/web-search-agent.md and follow them.

Your research topic is: {entity_name}
Your output path is: {output_dir}/data/{entity_slug}.json

Load these strategy modules before searching:
- ~/.claude/skills/research/agents/modules/general-web.md
{if entity is a GitHub project:}
- ~/.claude/skills/research/agents/modules/github-repo.md

Here are the fields you need to populate (from fields.yaml):
{paste fields.yaml content}

The current date is: {date from state.json}
```

3. Run all agents in the batch in parallel (multiple Agent tool calls in one message)
4. After the batch completes, check each output JSON exists

### Step 3: Report
List completed entities, failed entities, and total coverage.

## Evaluation Mode

### Step 1: Read eval_dimensions.yaml
Parse the dimension list and repo info.

### Step 2: Research Each Dimension
For each dimension, research sequentially:

**project_health** (source: gh_cli):
```bash
gh repo view {repo} --json name,description,stargazerCount,forkCount,pushedAt,createdAt,licenseInfo,primaryLanguage
gh api repos/{repo}/commits --jq '.[].commit.committer.date' | head -10
gh api repos/{repo}/contributors --jq 'length'
gh api repos/{repo}/releases --jq '.[0:3] | .[] | {tag: .tag_name, date: .published_at}'
```

**code_quality** (source: clone_analysis):
- Clone the repo to a temp directory
- Check for: tests directory, README, docs, CI config, dependency count
- Report findings

**community_sentiment** (source: web_search):
- Spawn an Agent to search with modules: general-web, reddit-x, hn-discussions
- Focus on user opinions, complaints, praise

**alternatives** (source: web_search):
- Search for "{topic} alternatives", "{topic} vs"
- List competing projects with brief descriptions

**integration_risk** (source: gh_cli):
- Check breaking changes in recent releases
- Analyze license compatibility
- Count dependencies

Write each dimension's results to `data/{dimension_name}.json`.

## Deep Mode

### Step 1: Read search_angles.yaml
Parse the angle list.

### Step 2: Parallel Research
For each angle, spawn an Agent with this prompt:

```
Read the web search agent instructions at ~/.claude/skills/research/agents/web-search-agent.md and follow them.

Your research angle is: {angle.query}
Focus area: {angle.focus}
Your output path is: {output_dir}/data/{angle_slug}.json

Load these strategy modules:
- ~/.claude/skills/research/agents/modules/general-web.md
{if focus is "academic":}
- ~/.claude/skills/research/agents/modules/academic.md
{if query contains Chinese:}
- ~/.claude/skills/research/agents/modules/chinese-tech.md

No fields.yaml — write free-form research findings.
The current date is: {date}
```

Run all agents in parallel.

### Step 3: Report
List completed angles and any failures.
