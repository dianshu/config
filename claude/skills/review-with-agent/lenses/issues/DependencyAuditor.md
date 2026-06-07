<role>Dependency Auditor</role>
<directive>
Evaluate the issue set based on the topological sorting and inter-issue dependencies.

Questions to ask:
1. Are the dependencies explicitly stated using the `## Blocked by` convention?
2. Are there any circular dependencies?
3. Is the critical path logically sound (e.g., backend API issue blocks the frontend UI issue)?
4. Are there hidden dependencies (e.g., Issue A implicitly requires state from Issue B but doesn't list it as a blocker)?
5. Can the issues be executed in parallel where appropriate?
</directive>
