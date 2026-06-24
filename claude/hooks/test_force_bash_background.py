#!/usr/bin/env python3
"""Table-driven tests for force-bash-background.py.

Each case feeds a PreToolUse JSON payload to the hook on stdin and asserts
whether the hook rewrites the command to background (emits `run_in_background:
true`) or leaves it untouched (emits nothing -> stays foreground).

Run: python3 test_force_bash_background.py
Exits non-zero if any case fails.
"""

import json
import os
import subprocess
import sys

HOOK = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                    "force-bash-background.py")


def rewrites_to_background(payload):
    """Run the hook on payload; True iff it emits a background rewrite."""
    proc = subprocess.run(
        [sys.executable, HOOK],
        input=json.dumps(payload),
        capture_output=True,
        text=True,
    )
    out = proc.stdout.strip()
    return bool(out) and '"run_in_background": true' in out


def bash(command, **top_level):
    """A Bash PreToolUse payload; extra kwargs go at the top level."""
    return {"tool_name": "Bash", "tool_input": {"command": command}, **top_level}


# (name, payload, expect_background_rewrite)
CASES = [
    # main thread (no agent_id): policy applies normally
    ("main non-whitelisted -> background",
     bash("python3 x.py"), True),
    ("main whitelisted -> foreground",
     bash("ls -la"), False),
    ("main control-structure -> background",
     bash("for f in *; do node $f; done"), True),
    # any subagent (agent_id present): always foreground
    ("subagent non-whitelisted -> foreground",
     bash("python3 x.py", agent_id="a123"), False),
    ("subagent whitelisted -> foreground",
     bash("ls", agent_id="a123"), False),
    ("default workflow subagent -> foreground",
     bash("npm test", agent_id="a1", agent_type="workflow-subagent"), False),
    # the regression this fix closes: a typed worker spawned by a workflow
    # reports its own agent_type, but still carries an agent_id
    ("typed workflow worker (Explore) -> foreground",
     bash("npm test", agent_id="a1", agent_type="Explore"), False),
    # invariants preserved
    ("already background -> no-op",
     {"tool_name": "Bash",
      "tool_input": {"command": "python3 x.py", "run_in_background": True}},
     False),
    ("non-Bash tool -> no-op",
     {"tool_name": "Read", "tool_input": {"command": "python3 x.py"}}, False),
    ("empty agent_id (falsy) treated as main -> background",
     bash("python3 x.py", agent_id=""), True),
]


def main():
    failures = 0
    for name, payload, expected in CASES:
        got = rewrites_to_background(payload)
        ok = got == expected
        failures += not ok
        status = "PASS" if ok else "FAIL"
        print(f"{status} | {name} (expected_bg={expected}, got_bg={got})")
    if failures:
        print(f"\n{failures} FAILED")
        return 1
    print(f"\nALL {len(CASES)} PASSED")
    return 0


if __name__ == "__main__":
    sys.exit(main())
