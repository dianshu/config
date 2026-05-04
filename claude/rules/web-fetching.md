## Web Fetching

Always use the SearXNG MCP web search tool (`mcp__searxng__searxng_web_search`) instead of the built-in WebSearch tool for all web searches.

When you encounter a URL that contains information relevant to the task, do NOT tell the user to open it manually. Fetch it yourself:

1. Try `defuddle.md` first — cleanest markdown output. Must use `curl` with a Chrome UA (other tools get 403):
   ```bash
   curl -sL -A "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 Chrome/120.0.0.0 Safari/537.36" "https://defuddle.md/<original URL with https://>"
   ```
2. If that fails, try `mcp__searxng__web_url_read` on the original URL.
3. If still failing or hits a login wall, open in Chrome (`mcp__chrome__new_page` + `mcp__chrome__take_snapshot`).
4. If Chrome shows a login wall, tell the user:
   > "I've opened [URL] in your browser, but it requires login. Please log in there, then let me know when you're done."
   After confirmation, re-snapshot and continue.

**SearXNG search results needing login:** If a page discovered via `mcp__searxng__searxng_web_search` turns out to need login (detected via `web_url_read`), open it in Chrome directly so the user can log in without having to find and open the URL themselves.

Never stop and wait just because information is on a webpage. You have the tools to read it.
