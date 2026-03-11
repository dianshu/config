#!/usr/bin/env python3
"""Security gate hook for Claude Code - AI-powered command review."""

import json
import sys
import os
import re
import hashlib
import time
import logging
import fnmatch
import tempfile
from urllib.request import Request, urlopen

READONLY_TOOLS = frozenset({"Read", "Glob", "Grep", "WebFetch", "WebSearch", "TodoRead",
                            "AskUserQuestion", "TaskList", "TaskGet"})
WRITE_TOOLS = frozenset({"Write", "Edit", "NotebookEdit"})

DEFAULT_CONFIG = {
    "model": "claude-sonnet-4-6",
    "max_tokens": 150,
    "timeout_seconds": 10,
    "cache_ttl_seconds": 300,
    "log_file": "~/.claude/hooks/security-gate.log",
    "bash_whitelist_prefixes": ["ls", "pwd", "echo ", "git status", "git log", "git diff"],
    "bash_deny_patterns": [
        "rm\\s+-[^\\s]*r[^\\s]*f|rm\\s+-[^\\s]*f[^\\s]*r",
        "\\bsudo\\b",
    ],
    "write_deny_paths": ["**/.env", "**/.env.*", "~/.ssh/*", "/etc/*"],
}

logger = logging.getLogger("security-gate")


def load_config(config_path):
    """Load security-gate.config.json. Returns defaults on any error."""
    try:
        with open(config_path, "r") as f:
            return json.load(f)
    except Exception:
        return dict(DEFAULT_CONFIG)


def load_api_config(settings_path):
    """Read API connection info from ~/.claude/settings.json env block."""
    defaults = {"base_url": "https://api.anthropic.com", "auth_token": ""}
    try:
        with open(settings_path, "r") as f:
            settings = json.load(f)
        env = settings.get("env", {})
        return {
            "base_url": env.get("ANTHROPIC_BASE_URL", defaults["base_url"]),
            "auth_token": env.get("ANTHROPIC_AUTH_TOKEN", defaults["auth_token"]),
        }
    except Exception:
        return defaults


def setup_logging(config):
    """Configure file logging."""
    log_path = os.path.expanduser(config.get("log_file", "~/.claude/hooks/security-gate.log"))
    try:
        os.makedirs(os.path.dirname(log_path), exist_ok=True)
        handler = logging.FileHandler(log_path)
        handler.setFormatter(logging.Formatter("%(asctime)s %(levelname)s %(message)s"))
        logger.addHandler(handler)
        logger.setLevel(logging.INFO)
    except Exception:
        pass


def is_readonly_tool(tool_name):
    """Check if tool is read-only and should always pass through."""
    if tool_name in READONLY_TOOLS:
        return True
    if tool_name.startswith("mcp__"):
        return True
    return False


def _strip_string_literals(command):
    """Remove quoted strings and heredoc content so deny patterns only match actual commands."""
    # Remove heredoc blocks: <<'EOF' ... EOF or <<EOF ... EOF
    result = re.sub(r"<<-?\s*'?(\w+)'?\s*\n.*?\n\1", "", command, flags=re.DOTALL)
    # Remove double-quoted strings (non-greedy, handles escaped quotes)
    result = re.sub(r'"(?:[^"\\]|\\.)*"', '""', result)
    # Remove single-quoted strings (no escaping in single quotes)
    result = re.sub(r"'[^']*'", "''", result)
    return result


def check_bash_deny(command, config):
    """Check command against deny patterns. Returns (denied, reason)."""
    stripped = _strip_string_literals(command)
    for pattern in config.get("bash_deny_patterns", []):
        try:
            if re.search(pattern, stripped):
                return True, f"Command matches deny pattern: {pattern}"
        except re.error:
            continue
    return False, ""


SHELL_CHAIN_RE = re.compile(r'[;&|`$\(]')


def check_bash_whitelist(command, config):
    """Check if command matches a whitelist prefix. Rejects shell chaining."""
    cmd = command.strip()
    if SHELL_CHAIN_RE.search(cmd):
        return False
    for prefix in config.get("bash_whitelist_prefixes", []):
        if cmd == prefix or cmd.startswith(prefix):
            return True
    return False


def check_write_deny(file_path, config, cwd=None):
    """Check if file path matches a denied write path pattern."""
    path = os.path.expanduser(file_path)
    if not os.path.isabs(path) and cwd:
        path = os.path.join(cwd, path)
    expanded = os.path.realpath(path)

    for pattern in config.get("write_deny_paths", []):
        pat = os.path.expanduser(pattern)
        if fnmatch.fnmatch(expanded, pat):
            return True, f"Write to sensitive path denied: {pattern}"
        if pattern.startswith("**/"):
            basename_pattern = pattern[3:]
            if fnmatch.fnmatch(os.path.basename(expanded), basename_pattern):
                return True, f"Write to sensitive path denied: {pattern}"

    return False, ""


def _get_cache_path(cache_file=None):
    """Get the cache file path."""
    if cache_file:
        return cache_file
    uid = os.getuid()
    return os.path.join(tempfile.gettempdir(), f"claude-security-gate-cache-{uid}.json")


def check_cache(key, config, cache_file=None):
    """Read cached decision. Returns decision string or None."""
    path = _get_cache_path(cache_file)
    try:
        with open(path, "r") as f:
            cache = json.load(f)
        entry = cache.get(key)
        if not entry:
            return None
        ttl = config.get("cache_ttl_seconds", 300)
        if time.time() - entry["time"] > ttl:
            return None
        return entry["decision"]
    except Exception:
        return None


def update_cache(key, decision, config, cache_file=None):
    """Write decision to cache file (atomic write). Prunes expired entries."""
    path = _get_cache_path(cache_file)
    try:
        try:
            with open(path, "r") as f:
                cache = json.load(f)
        except Exception:
            cache = {}
        now = time.time()
        ttl = config.get("cache_ttl_seconds", 300)
        cache = {k: v for k, v in cache.items() if now - v.get("time", 0) <= ttl}
        cache[key] = {"decision": decision, "time": now}
        tmp = path + ".tmp"
        with open(tmp, "w") as f:
            json.dump(cache, f)
        os.replace(tmp, path)
    except Exception:
        pass


def call_reviewer(tool_name, tool_input, cwd, api_config, config):
    """Call Sonnet API for security review. Returns 'SAFE' or 'UNSAFE: reason'."""
    try:
        if tool_name == "Bash":
            subject = f"COMMAND: {tool_input.get('command', '')}\nWORKING DIRECTORY: {cwd}"
        else:
            subject = f"TOOL: {tool_name}\nINPUT: {json.dumps(tool_input)}"

        prompt = (
            "You are a security reviewer for a developer's CLI tool.\n"
            "Evaluate if this operation is safe for a software development environment.\n\n"
            f"{subject}\n\n"
            "RULES:\n"
            "- Normal dev operations (build, test, lint, git, package managers) → SAFE\n"
            "- File deletion of project files (rm specific files) → SAFE\n"
            "- Destructive system operations, credential access, piping to shell → UNSAFE\n"
            "- If unsure → UNSAFE\n\n"
            "Reply with EXACTLY one line: SAFE or UNSAFE: <reason>"
        )

        base_url = api_config["base_url"].rstrip("/")
        url = f"{base_url}/v1/messages"

        body = json.dumps({
            "model": config.get("model", "claude-sonnet-4-6"),
            "max_tokens": config.get("max_tokens", 150),
            "messages": [{"role": "user", "content": prompt}],
        }).encode()

        headers = {
            "Content-Type": "application/json",
            "x-api-key": api_config["auth_token"],
            "anthropic-version": "2023-06-01",
        }

        req = Request(url, data=body, headers=headers, method="POST")
        timeout = config.get("timeout_seconds", 10)

        with urlopen(req, timeout=timeout) as resp:
            result = json.loads(resp.read())
            text = result["content"][0]["text"].strip()
            return text

    except Exception as e:
        logger.warning("Reviewer API error: %s", e)
        return "SAFE"


def _review_and_decide(cache_key, tool_name, tool_input, cwd, api_config, config):
    """Check cache, call reviewer if needed. Returns exit code: 0=allow, 2=deny."""
    cached = check_cache(cache_key, config)
    if cached:
        if cached.startswith("UNSAFE"):
            logger.warning("DENIED (cached): %s — %s", cache_key[:12], cached)
            print(cached, file=sys.stderr)
            return 2
        return 0

    decision = call_reviewer(tool_name, tool_input, cwd, api_config, config)
    update_cache(cache_key, decision, config)

    if decision.startswith("UNSAFE"):
        logger.warning("DENIED (reviewed) %s — %s", tool_name, decision)
        print(decision, file=sys.stderr)
        return 2

    logger.info("ALLOWED (reviewed) %s", tool_name)
    return 0


def _resolve_api_config(_test_config):
    """Load API config from settings or use test defaults."""
    if _test_config:
        return {"base_url": "http://localhost:29427", "auth_token": "test"}
    settings_path = os.path.expanduser("~/.claude/settings.json")
    return load_api_config(settings_path)


def main(config_path=None, _test_config=None):
    """Main entry point. Returns exit code: 0=allow, 2=deny."""
    if _test_config:
        config = _test_config
    else:
        if config_path is None:
            config_path = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                                       "security-gate.config.json")
        config = load_config(config_path)

    setup_logging(config)

    try:
        raw = sys.stdin.read()
        data = json.loads(raw)
    except Exception as e:
        logger.warning("Failed to parse input: %s", e)
        return 0

    tool_name = data.get("tool_name", "")
    tool_input = data.get("tool_input", {})
    cwd = data.get("cwd", os.getcwd())

    if is_readonly_tool(tool_name):
        logger.debug("Readonly tool %s — passthrough", tool_name)
        return 0

    if tool_name == "Bash":
        command = tool_input.get("command", "")

        denied, reason = check_bash_deny(command, config)
        if denied:
            logger.warning("DENIED bash: %s — %s", command, reason)
            print(reason, file=sys.stderr)
            return 2

        if check_bash_whitelist(command, config):
            logger.debug("Whitelisted bash: %s", command)
            return 0

        api_config = _resolve_api_config(_test_config)
        cache_key = hashlib.sha256(f"Bash:{cwd}:{command}".encode()).hexdigest()
        return _review_and_decide(cache_key, tool_name, tool_input, cwd, api_config, config)

    if tool_name in WRITE_TOOLS:
        file_path = tool_input.get("file_path", "")
        denied, reason = check_write_deny(file_path, config, cwd=cwd)
        if denied:
            logger.warning("DENIED %s to %s — %s", tool_name, file_path, reason)
            print(reason, file=sys.stderr)
            return 2
        return 0

    # Unknown tools — call reviewer
    if _test_config:
        return 0
    api_config = _resolve_api_config(_test_config)
    cache_key = hashlib.sha256(f"{tool_name}:{cwd}:{json.dumps(tool_input)}".encode()).hexdigest()
    return _review_and_decide(cache_key, tool_name, tool_input, cwd, api_config, config)


if __name__ == "__main__":
    sys.exit(main())
