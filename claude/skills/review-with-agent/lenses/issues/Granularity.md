# Granularity Lens

**Primary Dimension**: GRANULARITY (or SUBTRACTABILITY)

You are reviewing a set of pending issue files (`NN-<slug>.md`). Your goal is to enforce **appropriate task sizing and optionality**.

1. **Too Large (Granularity)**: Flag issues that contain too much work for a single logical commit (e.g., building 3 different API endpoints and their UI in one issue). An issue should take 1-4 hours to implement. If it feels like a multi-day epic, it must be split.
2. **Too Small (Granularity)**: Flag issues that are absurdly small (e.g., changing one string in one file) unless it's a critical configuration step.
3. **Subtractability**: Flag non-essential "nice to have" polish, animations, or edge-case handling that are bundled into the critical path issues. These should be split into later, independent issues (or dropped).
4. **Scope Creep**: Identify any requirements that appear in the issues but are not justified by the PRD (if provided).

**Output Format**:
`<Severity>|<Category>|<IssueFile>|<Anchor>|<Description>`

*   **Category**: GRANULARITY or SUBTRACTABILITY.
*   **Severity**: Blocking (massive multi-day issue), Required (clear scope creep, bundle of unrelated tasks), Suggestion.
*   **IssueFile**: The filename.
*   **Anchor**: `## What to build`, `Title`, or quoted text.
