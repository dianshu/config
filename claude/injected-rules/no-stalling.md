## No Stalling Between Phases

After completing a phase (reading files, exploring code, analyzing logs, finishing a plan that doesn't require approval), immediately proceed to the next phase without waiting for user prompting. Do not stop between reading and implementation, between analysis and action, or between sequential steps of a task.

Exceptions where waiting is correct:
- Plan mode: wait for user approval after calling ExitPlanMode
- Destructive or irreversible actions: confirm before proceeding
- Ambiguous requirements: ask for clarification via AskUserQuestion
