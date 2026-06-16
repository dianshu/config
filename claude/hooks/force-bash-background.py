#!/usr/bin/env python3
"""PreToolUse hook: force non-whitelisted Bash commands into background mode.

Policy: every Bash command runs in background (`run_in_background: true`)
EXCEPT commands whose every segment head is on WHITELIST below. Whitelisted
commands (quick / read-only / need-immediate-result) stay in the foreground.

Mechanism: emit `hookSpecificOutput.updatedInput` to rewrite the tool input,
WITHOUT `permissionDecision` — so the user's `permissions.deny` rules are still
enforced (deny-first precedence). The hook never blocks a command; on any
unexpected error it exits 0 with no output (fail open).

To adjust which commands stay foreground, edit WHITELIST.

Limitations:
- Unparseable shell syntax (unbalanced quotes, heredocs) is treated as
  non-whitelisted -> background (safe direction).
- Non-whitelisted wrapper prefixes (sudo, timeout, xargs, nohup ...) keep their
  wrapped command in the background, since the parsed head is the wrapper.
- A whitelisted command chained with a non-whitelisted one (`a && npm build`)
  goes to background -- not every segment head is whitelisted.
- Foreground "leaks" (a slow command wrongly kept in foreground) are the one
  UNSAFE direction, possible because head-only matching cannot see arguments:
  some whitelisted commands dispatch or block on a flag (`git clone`/`push`,
  `gh run watch`, `command <slow>`, `tail -f`, `cat`/`grep` reading stdin), and
  a heavy command nested in a substitution is not descended into (`echo
  "$(npm run build)"`, `cat <(slow)`, backticks, `<<<`). These block only until
  the Bash timeout; add such commands' slow forms to your own judgement.
- Inline control structures (`for`/`if`/`while`/`case`) go to background
  regardless of body, since their keywords are not whitelisted (safe direction).
"""

import contextlib
import os
import re
import shlex
import sys

# Commands that STAY IN THE FOREGROUND. Everything else runs in background.
# Keep this to quick / read-only / cheap commands whose output Claude needs
# immediately. Edit freely.
WHITELIST = {
    # navigation / inspection
    "ls", "ll", "la", "pwd", "cd", "pushd", "popd", "tree", "stat", "file",
    "du", "df", "realpath", "readlink", "basename", "dirname", "find", "fd",
    "fdfind",
    # view
    "cat", "bat", "head", "tail", "nl", "tac", "xxd", "od", "hexdump",
    "strings",
    # search
    "grep", "egrep", "fgrep", "rg", "ag", "ack",
    # text processing
    "echo", "printf", "sed", "awk", "gawk", "cut", "paste", "tr", "sort",
    "uniq", "comm", "column", "rev", "wc", "diff", "cmp", "jq", "yq", "fmt",
    "expand", "fold", "seq",
    # meta / env
    "which", "type", "command", "whoami", "hostname", "uname", "id", "groups",
    "date", "cal", "printenv", "true", "false", "test", "sleep", "expr",
    "tput", "clear", "sw_vers",
    # fast filesystem mutations (need immediate confirmation)
    "touch", "mkdir", "rmdir", "rm", "cp", "mv", "ln", "chmod", "chgrp",
    # hashing / encoding
    "base64", "md5", "md5sum", "shasum", "sha1sum", "sha256sum", "cksum",
    # vcs / forge (mostly quick; remove if you want push/clone backgrounded)
    "git", "gh",
}

# Tokens that separate one command from the next (start a new segment).
# Redirections (>, >>, <, 2>, &> ...) are intentionally NOT here: they do not
# begin a new command.
SEPARATORS = {"&&", "||", "|", "|&", ";", ";;", "&", "(", ")"}

# Characters that only ever appear in shell operators / redirections.
_PUNCT_ONLY = set("&|;()<>")

# Leading `NAME=value` environment assignment (e.g. `FOO=bar cmd`).
_ASSIGN = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*=")


def _segment_heads(command):
    """Return the head (first real word) of every command segment.

    Raises ValueError if the command cannot be tokenized.
    """
    # Join backslash line-continuations, then treat remaining newlines as
    # command separators so multi-line scripts are analysed per statement.
    normalized = command.replace("\r", "").replace("\\\n", " ").replace("\n", " ; ")

    lex = shlex.shlex(normalized, posix=True, punctuation_chars=True)
    lex.whitespace_split = True
    lex.commenters = ""  # do not treat '#' as a comment
    tokens = list(lex)  # may raise ValueError on bad quoting

    heads = []
    expect_head = True
    for tok in tokens:
        if tok in SEPARATORS:
            expect_head = True
            continue
        if not expect_head:
            continue
        if _ASSIGN.match(tok):
            continue  # env assignment prefix; keep looking for the head
        if tok and all(c in _PUNCT_ONLY for c in tok):
            continue  # stray redirection operator; skip
        heads.append(tok)
        expect_head = False
    return heads


def _should_background(command):
    """True if the command must run in background (not fully whitelisted)."""
    try:
        heads = _segment_heads(command)
    except ValueError:
        return True  # unparseable -> background (safe direction)
    if not heads:
        return False  # no real command (pure assignment / no-op) -> foreground
    return any(os.path.basename(head) not in WHITELIST for head in heads)


def main():
    try:
        import json

        data = json.load(sys.stdin)
    except Exception:
        return  # bad input; never break the Bash call

    if data.get("tool_name") != "Bash":
        return

    tool_input = data.get("tool_input") or {}
    command = tool_input.get("command")
    if not isinstance(command, str) or not command.strip():
        return
    if tool_input.get("run_in_background") is True:
        return  # already background

    if not _should_background(command):
        return  # whitelisted -> leave foreground, emit nothing

    updated = dict(tool_input)
    updated["run_in_background"] = True
    print(json.dumps({
        "hookSpecificOutput": {
            "hookEventName": "PreToolUse",
            "updatedInput": updated,
        }
    }))


if __name__ == "__main__":
    # Fail open: a hook crash must never block the user's command.
    with contextlib.suppress(Exception):
        main()
    sys.exit(0)
