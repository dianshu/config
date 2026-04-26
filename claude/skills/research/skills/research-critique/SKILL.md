---
name: research-critique
description: Phase 5 of deep research - red team analysis with 3 critic personas. Can loop back to Phase 3 for gap-filling.
---

# Phase 5: CRITIQUE

Perform red team analysis on the research findings to identify gaps, weaknesses, and biases.

## Inputs
- Read `state.json` from the output directory
- Read all JSON files from `data/`
- Read `validation.json` if it exists

## Resume Check
If `critique.json` exists in the output directory, skip this phase.

## Step 1: Load Research Data
Read all data JSON files and the validation results. Build a mental model of the complete research findings.

## Step 2: Apply Three Critic Personas

Evaluate the research through three lenses, sequentially:

### Skeptical Practitioner
Ask yourself:
- What claims lack sufficient evidence?
- Which sources are single-sourced (only one reference)?
- What would break if someone used this in production?
- Are there important caveats missing?

Generate a list of concerns with severity: **critical** / **moderate** / **minor**

### Adversarial Reviewer
Ask yourself:
- What alternative explanations exist for the findings?
- What's missing from this analysis that a domain expert would notice?
- Are there biases in the source selection?
- Are any conclusions overstated relative to the evidence?

Generate concerns with severity ratings.

### Implementation Engineer
Ask yourself:
- Is this analysis actionable?
- What practical gaps exist for someone trying to use these findings?
- Are version numbers, compatibility info, and setup requirements included?
- Would a developer have enough info to make a decision?

Generate concerns with severity ratings.

## Step 3: Gap Analysis
Review all critical concerns. For each one, determine:
- Is this a **factual gap** (missing data that could be found with more searching)?
- Or a **writing issue** (the data exists but needs better presentation)?

## Step 4: Loop-Back (If Needed)
If there are factual gaps (critical concerns that require more data):

1. Generate 2-3 targeted delta-queries to fill the gaps
2. Read the `research-retrieve` skill and execute only those specific queries
3. Time-box: spend no more than 3-5 minutes on supplemental searches
4. Maximum 2 loop-backs total

## Step 5: Write Results
Write `critique.json` to the output directory:
```json
{
  "concerns": [
    {
      "persona": "Skeptical Practitioner",
      "concern": "description",
      "severity": "critical|moderate|minor",
      "type": "factual_gap|writing_issue"
    }
  ],
  "loop_backs": 0,
  "delta_queries": [],
  "summary": "Overall assessment of research quality"
}
```

## Step 6: Report Summary
Tell the user:
- Number of concerns by severity
- Whether any loop-backs were triggered
- Overall quality assessment
