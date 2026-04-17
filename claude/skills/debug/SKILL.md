---
name: debug
description: |
  Use when encountering any bug, test failure, or unexpected behavior,
  before proposing fixes. Dispatches specialized agents for reproduction,
  investigation, and fixing. Proactively use when the user reports something
  broken, failing, or behaving unexpectedly.
---

# Systematic Debugging — Agent Orchestrated

## Overview

Random fixes waste time and create new bugs. Quick patches mask underlying issues.

**Core principle:** ALWAYS find root cause before attempting fixes. Symptom fixes are failure.

## The Iron Law

```
NO FIXES WITHOUT ROOT CAUSE INVESTIGATION FIRST
```

## When to Use

Use for ANY technical issue: test failures, bugs, unexpected behavior, performance problems, build failures, integration issues.

**Use this ESPECIALLY when:**
- Under time pressure (emergencies make guessing tempting)
- "Just one quick fix" seems obvious
- You've already tried multiple fixes
- You don't fully understand the issue

## Agent Dispatch Protocol

**You MUST use the three debug agents in strict order. Do NOT perform debug work directly.**

### Step 1: Debug Session Activation (Automatic)

The debug gate is activated automatically by hooks when `/debug` is invoked or the debug skill is used. No manual action needed.

### Step 2: Dispatch debug-reproducer

```
Agent(subagent_type: "debug-reproducer", prompt: "<bug description from user>")
```

**Before proceeding, check the output:**
- Has `understanding`? → Relay to user for confirmation. If user disagrees, re-dispatch with corrected understanding.
- Has `reproduction` with evidence? → Proceed to Step 3.
- Has `reproduction: null`? → Report to user: "Could not reproduce. Reason: {reason}. Should I proceed to code analysis, or can you suggest how to reproduce?"

### Step 3: Dispatch debug-investigator

```
Agent(subagent_type: "debug-investigator", prompt: "Reproduction evidence: <output from reproducer>")
```

**Before proceeding, check the output:**
- Has `root_cause`? → Proceed to Step 4.
- Has `root_cause: null`? → Report hypotheses to user. Ask which to pursue or if user has additional context.

### Step 4: Dispatch debug-fixer

```
Agent(subagent_type: "debug-fixer", prompt: "Root cause: <output from investigator>")
```

**After completion, check the output:**
- Has `changes` + passing `test_results`? → Report to user. Clean up debug session.
- Has `failure_reason`? → Report to user. Discuss before retrying.

### Step 5: Clean Up

Remove the debug gate directory for your session:
```bash
ls ~/.claude/debug-gate/
```
Then delete your session's directory (the one matching your session ID). If unsure, `ls` the directory first to confirm which one is yours.

**Important:** Always clean up the gate directory, even if the debug flow is abandoned early (user pivots, reproduction fails and user wants to move on, etc.). A stale gate directory blocks all Edit/Write for the rest of the session.

## Hard Rules

1. **Do NOT edit files directly** during a debug session. The hook will block you. All edits go through debug-fixer.
2. **Do NOT skip agents.** You cannot call debug-fixer without first going through reproducer → investigator.
3. **Do NOT call debug-investigator without reproduction evidence** (or explicit user permission to skip reproduction).
4. **Check each agent's output contract** before proceeding. If output is malformed or missing required fields, re-dispatch.

## Red Flags — STOP and Follow Process

If you catch yourself thinking:
- "Quick fix for now, investigate later"
- "Just try changing X and see if it works"
- "It's probably X, let me fix that"
- "I don't fully understand but this might work"
- "Let me read the code first" (before reproducing)
- "I can see the issue from the code" (skipping reproduction)
- "One more fix attempt" (when already tried 2+)
- Each fix reveals new problem in different place

**ALL of these mean: STOP. Go back to the correct agent.**

## Common Rationalizations

| Excuse | Reality |
|--------|---------|
| "Issue is simple, don't need agents" | Simple issues have root causes too. Agents are fast for simple bugs. |
| "Emergency, no time for process" | Systematic debugging is FASTER than guess-and-check thrashing. |
| "I'll just fix it directly" | The hook will block you. Use the agents. |
| "One more fix attempt" (after 2+ failures) | 3+ failures = architectural problem. Discuss with user. |
| "Reproduction isn't necessary here" | It always is. Ask the user if you truly can't find a way. |

## Supporting Techniques

Available in this directory:
- **`root-cause-tracing.md`** — Trace bugs backward through call stack
- **`defense-in-depth.md`** — Add validation at multiple layers after finding root cause
- **`condition-based-waiting.md`** — Replace arbitrary timeouts with condition polling

## Quick Reference

| Step | Agent | Key Activity | Success Criteria |
|------|-------|-------------|------------------|
| 1 | — | Activate debug session | Gate directory created |
| 2 | debug-reproducer | Understand + reproduce | Evidence of failure |
| 3 | debug-investigator | Root cause analysis | Identified root cause |
| 4 | debug-fixer | TDD fix + verify | Tests pass, bug resolved |
| 5 | — | Clean up | Gate directory removed |
