#!/usr/bin/env python3
"""Dev-workflow enforcement checker.

Scans a Claude Code transcript (JSONL) for evidence that the mandatory
post-implementation loop was executed after the last implementation edit.

Usage: python3 dev-workflow-check.py <transcript_path>
Exit 0 = pass (no implementation work, or loop completed/skipped)
Exit 2 = missing steps (stderr has details for Claude)
"""
import json
import os
import re
import sys

REQUIRED_STEPS = [
    "simplify",
    "codex-review",
    "gemini-review",
    "e2e-verify",
    "verification-before-completion",
]

SKILL_TO_STEP = {
    "simplify": "simplify",
    "codex-review": "codex-review",
    "gemini-review": "gemini-review",
    "e2e-verify": "e2e-verify",
    "superpowers:verification-before-completion": "verification-before-completion",
}

EXCLUDED_PATH_PATTERNS = [
    "/.claude/plans/",
    "/.claude/settings",
    "/.claude/hooks/",
    "/.claude/rules/",
]

BASH_WRITE_PATTERN = re.compile(
    r"(?:"
    r"\S+\s*[^>&\d]>[^>]"    # redirect > (not >&, not >>)
    r"|\S+\s*>>"              # append redirect >>
    r"|\btee\s"               # tee command (followed by space)
    r"|\bsed\s+-i\b"          # sed in-place
    r")"
)

SKIP_PATTERN = re.compile(
    r"SKIP:\s*(simplify|codex-review|gemini-review|e2e-verify|verification-before-completion)"
    r"\s*[\u2014\u2013\-]\s*reason:\s*(.+)",
    re.IGNORECASE,
)


def is_excluded_path(file_path):
    return any(pat in file_path for pat in EXCLUDED_PATH_PATTERNS)


def is_bash_file_write(command):
    return bool(BASH_WRITE_PATTERN.search(command))


def scan_transcript(transcript_path):
    """Scan transcript and return (last_impl_line, step_lines, skip_lines).

    last_impl_line: line number of the last implementation edit (-1 if none)
    step_lines: dict mapping step_name -> line number where it was invoked
    skip_lines: dict mapping step_name -> (line_number, reason)
    """
    last_impl_line = -1
    step_lines = {}
    skip_lines = {}

    if not os.path.isfile(transcript_path):
        return last_impl_line, step_lines, skip_lines

    with open(transcript_path) as f:
        for line_num, line in enumerate(f):
            try:
                entry = json.loads(line)
            except (json.JSONDecodeError, ValueError):
                continue

            if entry.get("type") != "assistant":
                continue

            content = entry.get("message", {}).get("content", [])
            if not isinstance(content, list):
                continue

            for block in content:
                if not isinstance(block, dict):
                    continue

                if block.get("type") == "tool_use":
                    name = block.get("name", "")
                    inp = block.get("input", {})
                    if not isinstance(inp, dict):
                        inp = {}

                    # Check Edit/Write for implementation work
                    if name in ("Edit", "Write"):
                        file_path = inp.get("file_path", "")
                        if not is_excluded_path(file_path):
                            last_impl_line = line_num

                    # Check Skill invocations
                    if name == "Skill":
                        skill_name = inp.get("skill", "")
                        if skill_name in SKILL_TO_STEP:
                            step = SKILL_TO_STEP[skill_name]
                            step_lines[step] = line_num

                elif block.get("type") == "text":
                    text = block.get("text", "")
                    for m in SKIP_PATTERN.finditer(text):
                        step_name = m.group(1).lower()
                        reason = m.group(2).strip()
                        skip_lines[step_name] = (line_num, reason)

    return last_impl_line, step_lines, skip_lines


def main():
    if len(sys.argv) < 2:
        sys.exit(0)

    transcript_path = sys.argv[1]
    last_impl_line, step_lines, skip_lines = scan_transcript(transcript_path)

    # No implementation work → no workflow required
    if last_impl_line < 0:
        sys.exit(0)

    # Check which steps are completed or skipped AFTER the last edit
    missing = []
    completed = []
    skipped = []

    for step in REQUIRED_STEPS:
        step_line = step_lines.get(step, -1)
        skip_info = skip_lines.get(step)

        after_edit_step = step_line > last_impl_line
        after_edit_skip = skip_info is not None and skip_info[0] > last_impl_line

        if after_edit_step:
            completed.append(step)
        elif after_edit_skip:
            skipped.append((step, skip_info[1]))
        else:
            missing.append(step)

    if not missing:
        sys.exit(0)

    # Build feedback message
    total = len(REQUIRED_STEPS)
    msg_lines = [
        "DEV-WORKFLOW GATE: Post-implementation loop incomplete.",
        f"Missing steps ({len(missing)}/{total}):",
    ]
    for step in missing:
        msg_lines.append(f"  - {step}")

    msg_lines.append("")
    msg_lines.append("Run these steps before completing, or declare:")
    msg_lines.append("  SKIP: <step-name> — reason: <explanation>")

    if completed:
        msg_lines.append("")
        msg_lines.append("Completed: " + ", ".join(completed))
    if skipped:
        msg_lines.append("Skipped: " + ", ".join(f"{s} ({r})" for s, r in skipped))

    print("\n".join(msg_lines), file=sys.stderr)
    sys.exit(2)


if __name__ == "__main__":
    main()
