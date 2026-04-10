---
name: research-validate
description: Phase 4 of deep research - validates citations, scores source credibility, checks field coverage and cross-entity consistency.
---

# Phase 4: VALIDATE

Validate the research data collected in Phase 3.

## Inputs
- Read `state.json` from the output directory
- Read all JSON files from `data/`

## Resume Check
If `validation.json` exists in the output directory, skip this phase.

## Step 1: Collect All Sources
Scan all JSON files in `data/` and extract every source entry (url, title, accessed date).
Write them to a temporary `sources_temp.json` file.

## Step 2: Citation Verification
Run the citation verifier:
```bash
python3 ~/.claude/skills/research/scripts/verify_citations.py sources_temp.json
```

This checks for:
- Generic academic title patterns (hallucination indicator)
- Future publication years
- Entries with neither URL nor DOI
- Anachronistic citations

Note: URL reachability checking is optional (add `--check-urls` flag for thorough validation, but it's slow).

## Step 3: Credibility Scoring
For each source, run the credibility evaluator:
```bash
python3 ~/.claude/skills/research/scripts/source_evaluator.py "<url>" "<title>" "<date>"
```

Record scores. Flag any source with score < 40 as `verify` — these need extra scrutiny.

## Step 4: Field Coverage (Comparison Mode Only)
If the research type is `comparison`, validate each entity JSON against `fields.yaml`:
```bash
python3 ~/.claude/skills/research/scripts/validate_json.py data/<entity>.json fields.yaml
```

Report coverage percentage per entity. If any entity has < 70% coverage, flag it for re-research.

## Step 5: Cross-Entity Consistency (Comparison Mode Only)
Read all entity JSONs and check for contradictions:
- If entity A says "supports feature X" but entity B says "only B supports feature X"
- If numerical values seem inconsistent (e.g., wildly different date formats)
- Report any contradictions found

## Step 6: Write Results
Write `validation.json` to the output directory:
```json
{
  "citation_check": {"total": N, "suspicious": N, "pass": true/false},
  "credibility_scores": [{"url": "...", "score": N, "recommendation": "..."}],
  "field_coverage": {"entity_name": 0.85},
  "contradictions": ["description of contradiction"],
  "overall_pass": true/false
}
```

## Step 7: Report Summary
Tell the user:
- Number of suspicious citations
- Number of low-credibility sources
- Field coverage per entity (if comparison)
- Any contradictions found
