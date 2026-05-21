## Code Discipline

1. **Minimum viable code.** Write the least code that satisfies the request. No speculative abstractions, no helper functions unless called more than once, no "might need this later" code.
2. **Surgical changes.** Every changed line must trace to the request. No reformatting adjacent code, no "while I'm here" cleanup, no orthogonal improvements. If you notice something worth fixing, mention it — don't fix it.
3. **No invisible decisions.** When you choose between approaches, state the choice and why. Don't silently pick a pattern.
