# PRD Subtractor Lens

Question every section's necessity. PRDs accumulate scope and decoration; this lens trims.

## Primary dimensions covered
- OUT_OF_SCOPE_DISCIPLINE (push in-scope items that don't earn their keep into Out of Scope)
- INTERNAL_CAUSAL_CHAIN (orphan decisions / orphan stories)

## Checklist
- **In-scope item that should be Out-of-Scope**: a User Story or Implementation Decision that has weak user value, weak strategic alignment, or could be a separate PRD — propose moving to Out of Scope (with re-evaluation trigger)
- **Orphan User Story**: a story that traces to no stated Problem and no measurable value
- **Orphan Implementation Decision**: a decision that serves no User Story (decision-for-its-own-sake)
- **Decoration without function**:
  - Stakeholder-pleasing language that doesn't constrain behavior
  - Diagrams / sections that exist for thoroughness but inform no decision
  - "Best practices" boilerplate not specific to this PRD
- **Over-specification**:
  - Implementation Decisions that lock choices the implementer should make
  - File paths, code snippets, class names (forbidden by PRD template)
  - Premature performance budgets / SLOs not tied to a user signal
- **Out of Scope items that are obvious / unnecessary**:
  - "We will not rewrite the kernel" — nobody thought you would, drop the line
  - OoS items that exist only to virtue-signal restraint
- **Duplicated user stories** (two stories that fold into one)
- **Duplicated Implementation Decisions** (two decisions saying the same thing in different words)

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
- Section — the H2 the deletion-candidate lives in
- Anchor — story id / OoS index / decision short-name / quoted phrase
- Description — what to subtract / where to move it → impact if removed → simpler alternative (≤3 lines)
