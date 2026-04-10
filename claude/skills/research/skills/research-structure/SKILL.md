---
name: research-structure
description: Phase 2 of deep research - generates outline/fields (comparison), evaluation dimensions, or search angles based on research type.
---

# Phase 2: STRUCTURE

Generate the structural framework for the research based on the type determined in Phase 1.

## Inputs
- Read `state.json` from the research output directory to get: type, topic, auto flag, date

## Resume Check
Check if structure files already exist in the output directory:
- `outline.yaml` + `fields.yaml` (comparison)
- `eval_dimensions.yaml` (evaluation)
- `search_angles.yaml` (deep)

If they exist, skip this phase.

## Comparison Mode

### Step 1: Draft Entities
Using your knowledge, generate an initial list of entities (items to compare) from the topic. For example, "对比 Cursor vs Windsurf vs Zed" → entities are Cursor, Windsurf, Zed.

### Step 2: Draft Comparison Dimensions
Generate a categorized list of comparison fields. Think about what dimensions matter for this type of comparison:
- Core features
- Pricing/licensing
- Community/ecosystem
- Performance
- Developer experience

### Step 3: Web Search Supplement
Spawn a single Agent (subagent_type: "general-purpose") to search for any missing entities or dimensions:
- Load `~/.claude/skills/research/agents/modules/general-web.md`
- Search for "{topic} comparison" to find commonly compared dimensions
- Report any additional entities or fields found

### Step 4: Generate outline.yaml
```yaml
topic: "<research topic>"
items:
  - name: "<Entity Name>"
    slug: "<entity-slug>"
execution:
  batch_size: 3
  items_per_agent: 1
  output_dir: "data"
```

### Step 5: Generate fields.yaml
```yaml
categories:
  - name: "<Category Name>"
    fields:
      - name: "<field_slug>"
        description: "<What to research for this field>"
        detail_level: "brief|moderate|detailed"
```

### Step 6: User Review
Unless `--auto`, present the outline and fields to the user via `AskUserQuestion`. Let them add/remove entities or dimensions.

### Step 7: Write Files
Write both `outline.yaml` and `fields.yaml` to the output directory. Create the `data/` subdirectory.

## Evaluation Mode

### Step 1: Extract Repo Info
Try to identify the GitHub repository from the topic. If a repo is referenced (e.g., "FastMCP", "jlowin/fastmcp"):
```bash
gh repo view <owner/repo> --json name,description,stargazerCount,forkCount,pushedAt,createdAt,licenseInfo,primaryLanguage,homepageUrl
```

### Step 2: Generate Evaluation Dimensions
Create `eval_dimensions.yaml` with these standard dimensions:
```yaml
topic: "<project name>"
repo: "<owner/repo>"
dimensions:
  - name: "project_health"
    description: "Stars, commit frequency, issue response time, contributor count"
    source: "gh_cli"
  - name: "code_quality"
    description: "Test coverage, documentation, dependency count, directory structure"
    source: "clone_analysis"
  - name: "community_sentiment"
    description: "Reddit/HN/X discussions, GitHub issues tone"
    source: "web_search"
  - name: "alternatives"
    description: "Competing projects and how they compare"
    source: "web_search"
  - name: "integration_risk"
    description: "Breaking changes history, license, dependency weight"
    source: "gh_cli"
```

### Step 3: User Review
Unless `--auto`, present dimensions to the user. Let them add/remove dimensions.

### Step 4: Write File
Write `eval_dimensions.yaml` to the output directory. Create `data/`.

## Deep Mode

### Step 1: Decompose Question
Break the research topic into 5-10 search angles. Each angle approaches the topic from a different perspective:
- Overview / current state
- Technical details / how it works
- Industry adoption / use cases
- Challenges / limitations
- Future direction / trends

### Step 2: Generate search_angles.yaml
```yaml
topic: "<research topic>"
angles:
  - query: "<specific search query>"
    focus: "<what this angle covers>"
```

### Step 3: Write File
Write `search_angles.yaml` to the output directory. Create `data/`.
