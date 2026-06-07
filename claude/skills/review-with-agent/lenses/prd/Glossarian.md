# PRD Glossarian Lens

Enforce terminology consistency with project domain language.

## Primary dimensions covered
- USER_VOCABULARY (user-facing terms must match how users talk)
- CONSISTENCY (domain terms must match the glossary / past PRDs / ADRs)

## Inputs
- The PRD content
- **Project context (REQUIRED for full value)**: CONTEXT.md glossary section, sibling/historical PRDs, ADR titles. The workflow injects these via args.contextFiles.

## Checklist
- **Terminology drift vs glossary**: every domain noun in the PRD must use the term defined in CONTEXT.md (or comparable glossary file). Flag any noun phrase that names a domain concept under a different label than the glossary entry.
- **Invented terms for existing concepts**: PRD names something new ("message bundle", "session wrapper") when the codebase already has a term ("envelope", "session"). Flag and propose the canonical term.
- **Engineering term in user-facing section**: Problem Statement / Solution / User Stories use API names, class names, schema field names, protocol names, library names, or engineering metrics (SLO, p99, QPS, throughput, ms) without translation to user experience. → Required
- **User-facing term in engineering section**: Implementation Decisions / Testing Decisions use vague user words ("seamless", "fast") where measurable contracts are needed. → Suggestion
- **Inconsistent term within the PRD itself**: PRD calls the same thing two different names in different sections (e.g. "session" in section 1 and "conversation" in section 3). → Required
- **Term conflicts with sibling PRD**: a recent PRD established a term and this PRD silently changes it. → Required
- **ADR relationship not declared**: PRD's Implementation Decisions touch an area where an Accepted ADR exists, but PRD does not state extends / refines / supersedes / no-relationship. → Blocking when the decision actually contradicts the ADR.

## Behavior when context is absent
If `args.contextFiles` is empty or contains no glossary/ADR entries, fall back to:
- Internal consistency (same concept named consistently within the PRD)
- USER_VOCABULARY checks (engineering terms in user sections, and vice versa)
- Flag a single Suggestion noting that no glossary was injected, so cross-doc consistency could not be checked

## Constraints
- ≤10 Suggestion findings; Blocking and Required uncapped. ≤3 lines each
- If nothing actionable: output `LGTM`

## Output Format
One finding per line:
`<Severity>|<Category>|<Section>|<Anchor>|<Description>`

Where:
- Section — H2 where the term appears
- Anchor — the offending term itself (verbatim quoted), so cross-round dedup works
- Description — used term → canonical term (from glossary/ADR/sibling PRD) → rewrite suggestion (≤3 lines)
