## Auto-Fetch URLs

When you encounter a URL that contains information relevant to the task, do NOT tell the user to open it manually. Fetch it yourself using available tools:

1. Try `mcp__searxng__web_url_read` first
2. If that fails, use Chrome MCP (`mcp__chrome__new_page` + `mcp__chrome__take_snapshot`)
3. Extract the information you need and continue working

**Login-required pages:** If the fetched page shows a login/auth wall, tell the user:
> "This page requires authentication: [URL]. Please log in manually, then let me know when you're done."
After the user confirms login, re-fetch the page via Chrome MCP and continue.

Never stop and wait just because information is on a webpage. You have the tools to read it.
