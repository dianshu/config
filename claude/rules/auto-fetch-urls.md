## Auto-Fetch URLs

When you encounter a URL that contains information relevant to the task, do NOT tell the user to open it manually. Fetch it yourself using available tools:

1. Try `mcp__searxng__web_url_read` first
2. If that fails or returns a login/auth wall, open the URL directly in Chrome (`mcp__chrome__new_page`) and take a snapshot (`mcp__chrome__take_snapshot`)
3. If the Chrome snapshot shows a login/auth wall, tell the user:
   > "I've opened [URL] in your browser, but it requires login. Please log in there, then let me know when you're done."
   After the user confirms login, re-snapshot via Chrome and continue.
4. Extract the information you need and continue working

**SearXNG search results needing login:** If a page discovered via `mcp__searxng__searxng_web_search` turns out to need login (detected via `web_url_read`), open it in Chrome directly so the user can log in without having to find and open the URL themselves.

Never stop and wait just because information is on a webpage. You have the tools to read it.
