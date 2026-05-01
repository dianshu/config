#!/usr/bin/env python3
"""Extract structured timeline + recent assistant text from transcript JSONL.

Output JSON: {"events": [...], "recent_text": [...]}
Each event: {"line": int, "type": str, "target": str}
type ∈ edit|write|multiedit|notebook|bash_modify|skill|slash_command
"""
import json
import re
import sys

REVIEW_STEPS = {"simplify", "codex-review", "gemini-review", "e2e-verify"}

SKILL_TO_STEP = {
    "simplify": "simplify",
    "codex-review": "codex-review",
    "gemini-review": "gemini-review",
    "e2e-verify": "e2e-verify",
}

BASH_MODIFY_RE = re.compile(
    r"\b(sed\s+-i|awk\s+-i|perl\s+-i|tee\b|>\s*[^&\s|]|>>|"
    r"\bmv\b|\bcp\b|\brm\b|\bapply_patch\b|"
    r"git\s+(apply|checkout|restore)\b|"
    r"(npm|pnpm|bun|yarn)\s+(install|add|remove|update)\b|"
    r"pip\s+install\b|cargo\s+(add|install)\b|"
    r"(prettier|black|ruff)\s+(--write|format)|gofmt\s+-w|rustfmt\b)"
)

# Commands targeting only ephemeral paths (tmp, caches) are not implementation
# modifications. Match if EVERY non-flag word is under such a path.
EPHEMERAL_PATH_RE = re.compile(
    r"^(/tmp/|/var/folders/|/private/var/folders/|/private/tmp/|"
    r"~/\.cache/|~/Library/Caches/|/dev/null$|\.\./|\./)"
)


def is_ephemeral_only(cmd):
    """True if all path-like args target ephemeral locations."""
    paths = [tok for tok in cmd.split() if "/" in tok or tok == "/dev/null"]
    if not paths:
        return False
    return all(EPHEMERAL_PATH_RE.match(p.lstrip("'\"")) for p in paths)

_STEP_ALT = "|".join(re.escape(s) for s in REVIEW_STEPS)
SLASH_RE = re.compile(r"^\s*/(" + _STEP_ALT + r")\b")
COMMAND_NAME_RE = re.compile(
    r"<command-name>/?(" + _STEP_ALT + r")</command-name>"
)

MAX_EVENTS = 100
MAX_RECENT_TEXT = 5
TEXT_TRUNC = 500


def normalize_skill(name):
    return SKILL_TO_STEP.get(name)


def normalize_slash(name):
    return name if name in REVIEW_STEPS else None


def extract_text(content):
    if isinstance(content, str):
        return content
    if isinstance(content, list):
        parts = []
        for blk in content:
            if isinstance(blk, dict) and blk.get("type") == "text":
                parts.append(blk.get("text", ""))
        return "\n".join(parts)
    return ""


def main():
    if len(sys.argv) < 2:
        print(json.dumps({"events": [], "recent_text": []}))
        return
    path = sys.argv[1]
    events = []
    recent_text = []
    try:
        with open(path) as f:
            for lineno, raw in enumerate(f, 1):
                try:
                    entry = json.loads(raw)
                except Exception:
                    continue
                etype = entry.get("type")
                msg = entry.get("message", {}) or {}
                content = msg.get("content", [])

                if etype == "user":
                    text = extract_text(content)
                    for line in text.splitlines():
                        m = SLASH_RE.match(line)
                        if m:
                            step = normalize_slash(m.group(1))
                            if step:
                                events.append({"line": lineno, "type": "slash_command",
                                               "target": step})
                        m = COMMAND_NAME_RE.search(line)
                        if m:
                            step = normalize_slash(m.group(1))
                            if step:
                                events.append({"line": lineno, "type": "slash_command",
                                               "target": step})

                elif etype == "assistant" and isinstance(content, list):
                    text_buf = []
                    for blk in content:
                        if not isinstance(blk, dict):
                            continue
                        if blk.get("type") == "tool_use":
                            tname = blk.get("name", "")
                            tin = blk.get("input", {}) or {}
                            if tname == "Edit":
                                events.append({"line": lineno, "type": "edit",
                                               "target": tin.get("file_path", "")})
                            elif tname == "Write":
                                events.append({"line": lineno, "type": "write",
                                               "target": tin.get("file_path", "")})
                            elif tname == "MultiEdit":
                                events.append({"line": lineno, "type": "multiedit",
                                               "target": tin.get("file_path", "")})
                            elif tname == "NotebookEdit":
                                events.append({"line": lineno, "type": "notebook",
                                               "target": tin.get("notebook_path", "")})
                            elif tname == "Bash":
                                cmd = tin.get("command", "")
                                if BASH_MODIFY_RE.search(cmd) and \
                                        not is_ephemeral_only(cmd):
                                    events.append({
                                        "line": lineno,
                                        "type": "bash_modify",
                                        "target": cmd[:200],
                                    })
                            elif tname == "Skill":
                                step = normalize_skill(tin.get("skill", ""))
                                if step:
                                    events.append({"line": lineno, "type": "skill",
                                                   "target": step})
                        elif blk.get("type") == "text":
                            text_buf.append(blk.get("text", ""))
                    if text_buf:
                        joined = "\n".join(text_buf)[:TEXT_TRUNC]
                        recent_text.append({"line": lineno, "text": joined})
    except FileNotFoundError:
        pass

    if len(events) > MAX_EVENTS:
        last_skill_pos = {}
        for i, e in enumerate(events):
            if e["type"] in ("skill", "slash_command"):
                last_skill_pos[e["target"]] = i
        keep = set(last_skill_pos.values())
        n_keep = MAX_EVENTS - len(keep)
        recent = list(range(max(0, len(events) - n_keep), len(events)))
        keep.update(recent)
        events = [e for i, e in enumerate(events) if i in keep]

    recent_text = recent_text[-MAX_RECENT_TEXT:]

    print(json.dumps({"events": events, "recent_text": recent_text}))


if __name__ == "__main__":
    main()
