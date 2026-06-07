# PRD Challenger Lens

Assume each User Story has weak INVEST quality, vague benefit, or smuggled implementation — prove it.

## Primary dimensions covered
- USER_STORY_INVEST (primary)
- ACCEPTANCE_CRITERIA (call out missing or implementation-leaking criteria)
- USER_VOCABULARY (call out engineering terms inside stories)

## Checklist — per User Story
For each "As an X, I want Y, so that Z":
- **Actor** is "user" / "we" / "the system" instead of a concrete persona → Required
- **Want** describes UI mechanics ("click the blue button") or implementation ("call the X API") instead of observable behavior → Blocking
- **So-that** is a tautology that restates the want ("...so that I can see X" when the want already says "see X") → Required
- **So-that** names no measurable user value → Required
- INVEST violations:
  - Not **Independent**: hidden ordering dep on another story (story B only makes sense after story A ships)
  - Not **Negotiable**: locks an implementation choice that should be deferred
  - Not **Valuable**: no measurable value, vanity feature
  - Not **Estimable**: missing information needed to scope
  - Not **Small**: too large to fit a single sprint / iteration
  - Not **Testable**: cannot write an acceptance scenario for it → **Blocking**
- **Acceptance criteria absent** for the story → Blocking
- **Acceptance criteria reference implementation** (class name, method, schema field, file path, DB column) → Blocking — must be rewritten in terms of observable behavior

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
- Section — typically "User Stories"
- Anchor — story id (e.g. "US-7"), or a quoted phrase if no ids are present
- Description — what's wrong → why it matters → suggested rewrite (≤3 lines)
