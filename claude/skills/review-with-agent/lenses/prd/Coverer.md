# PRD Coverer Lens

Build and validate the two-way coverage matrix between User Stories and Testing Decisions; verify each User Story has Acceptance Criteria.

## Primary dimensions covered
- TRACEABILITY (primary — story ↔ testing decision matrix)
- ACCEPTANCE_CRITERIA (every story must have explicit criteria)

## Method
1. Enumerate every User Story (extract id and the actor/feature/benefit triple)
2. Enumerate every Testing Decision (extract a short id or first-sentence summary)
3. Build the matrix: which testing decision(s) cover which story; which story / decision has no counterpart
4. For each User Story, check whether Acceptance Criteria are nested below it

## Checklist
- **Story without any Testing Decision**: a User Story is not covered by any Testing Decision → Blocking (UNCOVERED)
- **Testing Decision without any Story**: a Testing Decision serves no User Story → Required (ORPHAN)
- **Many-to-one ambiguity**: one Testing Decision claims to cover many stories without specifying which behaviors of each → Required
- **Implementation Decision without Story**: a decision serves no story → Required (ORPHAN)
- **Missing Acceptance Criteria**: a User Story has no Acceptance Criteria sub-section → Blocking
- **Acceptance Criteria references implementation**: criteria mention class / method / schema field / file path / DB column → Blocking (rewrite in observable terms)
- **Acceptance Criteria not testable**: criteria so vague no test could be written ("the feature works") → Blocking
- **Acceptance Criteria covers only happy path**: criteria miss failure / boundary / empty cases → Required
- **Seam quality**: when Testing Decisions describe the seam (test point), flag if the seam is too low (testing implementation rather than behavior) → Required

## Output: coverage matrix as findings
For each unmatched row/column, emit one finding. Optionally emit one GLOBAL summary finding stating overall coverage % (e.g. "8 of 11 user stories have testing decisions"). The summary is Suggestion-severity.

## Inputs
- The PRD content
- Wont-fix ledger

## Constraints
- ≤10 Suggestion findings; Blocking and Required uncapped. ≤3 lines each
- If nothing actionable: output `LGTM`

## Output Format
One finding per line:
`<Severity>|<Category>|<Section>|<Anchor>|<Description>`

Where:
- Section — "User Stories" / "Testing Decisions" / "Implementation Decisions" / "GLOBAL" (for matrix summary)
- Anchor — story id (e.g. "US-7"), testing-decision id (e.g. "TD-3"), or "MATRIX-SUMMARY"
- Description — what's uncovered / orphan / non-testable → impact → what to add (≤3 lines)
