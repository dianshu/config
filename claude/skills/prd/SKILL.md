---
name: prd
description: Turn the current conversation context into a PRD and publish it to the project issue tracker. Use when user wants to create a PRD from the current context.
---

This skill takes the current conversation context and codebase understanding and produces a PRD. Do NOT interview the user — just synthesize what you already know.

Read `~/.claude/matt/issue-tracker.md` and `~/.claude/matt/triage-labels.md` for the issue tracker and triage label configuration.

## Process

1. Explore the repo to understand the current state of the codebase, if you haven't already. Use the project's domain glossary vocabulary throughout the PRD, and respect any ADRs in the area you're touching.

   If `$PWD/GRILLCOMMITMENTS.md` exists, read it. Treat each active commitment (under `## Commitments`, not superseded in `## Modifications`) as a constraint the PRD must honor — scope, priority, definitions, and quantities stated there override any conflicting assumption you would otherwise make. If a commitment conflicts with what you are about to write, surface the conflict to the user instead of silently overriding it.

2. Sketch out the seams at which you're going to test the feature. Existing seams should be preferred to new ones. Use the highest seam possible. If new seams are needed, propose them at the highest point you can. The fewer seams across the codebase, the better — the ideal number is one.

   Check with the user that these seams match their expectations. Check with the user which seams they want tests written for. **(This is the first user touchpoint — seam confirmation. The second is the final approval after `/prd-review-loop`.)**

3. **Write the PRD draft** using the template below to a file under the project issue tracker location (e.g. `~/.claude/matt/features/<slug>/PRD.md`). Do NOT publish or apply any triage label yet — the PRD is still a draft.

   At the end of this step, suggest the user run `/prd-review-loop <PRD-path>` to dual-review and refine the PRD before final approval. The review loop reads the same GRILLCOMMITMENTS.md, ADRs, and glossary that this skill consulted, and cross-checks the draft against them.

4. **Finalize and publish** (after `/prd-review-loop` returns EXIT and the user gives final approval): apply the `ready-for-agent` triage label and treat the PRD as published. A PRD that comes out of this skill **after review** is fully specified and ready for an AFK agent.

<prd-template>

## Problem Statement

The problem that the user is facing, from the user's perspective. Use user vocabulary, not implementation vocabulary. Engineering metrics (SLO, p99, ms) belong elsewhere unless translated into user-experienceable terms.

## Solution

The solution to the problem, from the user's perspective. Every Solution element must trace back to something in Problem Statement.

## User Stories

A LONG, numbered list of user stories. Each user story is structured as:

```
### US-<n>. As an <actor>, I want a <feature>, so that <benefit>

**Acceptance Criteria** (Given-When-Then or observable-behavior bullets):
- ...
- ...
```

<user-story-example>
### US-1. As a mobile bank customer, I want to see balance on my accounts, so that I can make better informed decisions about my spending

**Acceptance Criteria**:
- Given I am signed in, When I open the Accounts tab, Then each account row shows its current balance in the account's currency.
- Given my balance fetch fails, When I open the Accounts tab, Then each affected row shows "Balance unavailable" and a retry control, and no stale value is shown.
- Given a balance changes server-side, When I am on the Accounts tab and the app receives the change, Then the row updates within 5 seconds without me reloading.
</user-story-example>

Rules:
- The actor must be a concrete persona (e.g. "mobile bank customer", "hapi maintainer"), not the generic word "user".
- The benefit ("so that ...") must name measurable user value — not restate the want.
- Acceptance Criteria MUST describe **externally observable behavior only**. Do NOT mention class names, method names, schema field names, file paths, DB columns, or library names. If you need to reference internals, those references belong in **Implementation Decisions**, not here.
- Every User Story must have at least one Acceptance Criterion. Missing criteria = the story is not yet a PRD-grade requirement.

This list should be extremely extensive and cover all aspects of the feature.

## Implementation Decisions

A list of implementation decisions that were made. This can include:

- The modules that will be built/modified
- The interfaces of those modules that will be modified
- Technical clarifications from the developer
- Architectural decisions
- Schema changes
- API contracts
- Specific interactions

Do NOT include specific file paths or code snippets. They may end up being outdated very quickly.

Every Implementation Decision should serve at least one User Story (cite the US-<n>). If a decision serves no story, it is either premature or belongs in a different PRD.

If a decision touches an area covered by an Accepted ADR (under `docs/adr/`), explicitly declare the relationship: **extends / refines / supersedes / unrelated** ADR-NNNN.

## Testing Decisions

A list of testing decisions that were made. Include:

- A description of what makes a good test (only test external behavior, not implementation details)
- Which modules will be tested — cite the User Story id(s) each test seam covers (e.g. "covers US-1, US-3")
- Prior art for the tests (i.e. similar types of tests in the codebase)

Coverage rule: every User Story should be covered by at least one Testing Decision; every Testing Decision should cite the User Story id(s) it covers.

## Out of Scope

A description of the things that are out of scope for this PRD. Each item must declare an explicit **Re-evaluate when** trigger so it doesn't become a forgotten dead-name list.

Format:

```
- <Out-of-scope item>
  - **Re-evaluate when**: <observable signal — metric threshold, user count, upstream change, regulatory change, sibling PRD shipped>
```

The trigger must be **observable** — "if users complain" is not enough; "if support tickets mentioning X exceed 5/week for 2 consecutive weeks" or "when concurrent-session count > 1k" is. Vague triggers turn into never-revisited Out-of-Scope items.

## Assumptions

A list of **load-bearing assumptions** this PRD depends on. Each assumption is a statement that, if false, would invalidate part of the Solution or User Stories. Include both:

- Assumptions the team has agreed on (e.g. "single-user concurrency only; multi-user is out of scope").
- Assumptions inherited from the codebase / dependencies that are not explicitly documented elsewhere (e.g. "the upstream X service guarantees ordering within a session").

For each assumption, note the **validation plan**: how / when we'd discover the assumption is wrong (smoke test, dashboard alert, user feedback, etc.). Assumptions without a validation plan are silent landmines.

## Success Metrics

At least one externally observable signal that tells us whether the feature is delivering the value claimed in Solution. Outcome metrics (user behavior, business outcome) are preferred over output metrics (lines of code, tickets closed).

Each metric should specify:
- The signal name and how it is measured
- The target (with units and direction — increase / decrease / stay below)
- The horizon (when do we evaluate)

Example:
```
- **Account-balance discovery rate** (user-event funnel): % of sessions that view ≥1 account balance within 30s of opening Accounts tab. Target: ≥80% on a 14-day rolling window. Horizon: evaluate 4 weeks after rollout.
```

## Further Notes

Any further notes about the feature — open questions, future work hooks, references to past PRDs / RFCs / ADRs (with `extends / refines / supersedes` annotations if relevant), risk notes.

</prd-template>
