# PRD Devil's Advocate Lens

Question the premise: is this the right feature, prioritized correctly, scoped honestly, and aware of its own assumptions?

## Primary dimensions covered
- ASSUMPTIONS_SURFACED (primary — both stated and inferred)
- OUT_OF_SCOPE_DISCIPLINE (scope honesty)
- INTERNAL_CAUSAL_CHAIN (does the Solution actually solve the Problem?)

## Checklist — Premise
- **Solution-problem mismatch**: the Solution doesn't actually fix the stated Problem (or fixes a different one)
- **Simpler alternative**: a meaningfully cheaper path was passed over without acknowledgment
- **Priority dispute**: prioritization implied by story order or P0/P1 tags doesn't match user value
- **Scope creep camouflage**: "in-scope" includes things a reasonable reader would expect to be out-of-scope
- **Out-of-Scope without re-evaluation trigger**: each OoS item must declare when it should be re-evaluated; missing trigger → Required
- **Out-of-Scope with unobservable trigger**: "if users complain" / "if it becomes important" → Required
- **Out-of-Scope contradicts In-Scope**: an in-scope story implies an out-of-scope capability → Blocking
- **No fallback decision**: PRD claims X will succeed but says nothing about what happens if X fails / is delayed

## Checklist — Assumptions
- Output TWO lists:
  - **(a) Stated assumptions**: assumptions the PRD explicitly calls out
  - **(b) Inferred assumptions**: assumptions YOU read between the lines but the author did not write down — for each, **quote the line that triggered the inference**
- Common load-bearing assumptions to probe specifically:
  - User behavior pattern (single-user? concurrent? engaged daily?)
  - Upstream system availability
  - Data scale (now and projected)
  - Network topology / latency
  - Failure semantics (retries idempotent? partial failure visible?)
  - Permission / auth model
  - Timezone, locale, monotonic-clock dependencies
- Flag (b) entries as Required so the author either documents them or adds wont-fix justification

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
- Section — "Problem Statement" / "Solution" / "Out of Scope" / "Assumptions" / "GLOBAL"
- Anchor — for inferred assumptions, use a short tag like "ASSUME:single-user" or the quoted trigger phrase
- Description — premise being challenged → why it matters → what to change (≤3 lines)
