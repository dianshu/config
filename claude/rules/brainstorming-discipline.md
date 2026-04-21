## Brainstorming Discipline

### Never Skip Brainstorming

Never skip the brainstorming process by judging a task as "too simple." Even a one-line config change can hide multiple design decisions (path resolution, cross-platform support, dedup strategies, terminal differences).

### Always Complete Full Checklist

When brainstorming is invoked (whether via `/brainstorming` or `/superpowers:brainstorming`), you MUST complete the full checklist — design → spec → user review → writing-plans — for EVERY task, regardless of perceived size or simplicity.

**Forbidden behavior:** Skipping the spec/plan and going directly to file-by-file edits. This is NEVER acceptable after brainstorming is invoked.

**Why:** Skipping the plan forces the user to approve each file edit individually without seeing the full picture. This is both unsafe (no holistic review) and tedious (repeated permission prompts).

**Rule:** If brainstorming was invoked, code changes may only happen AFTER the writing-plans skill has produced a plan and the user has approved it.
