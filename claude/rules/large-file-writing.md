## Large File Writing Strategy

When writing files with large content (roughly >500 lines or >15KB), the Write tool call may fail due to output token truncation — the JSON parameters get cut off, causing missing `file_path` or `content` errors.

**Prevention:** When you know the content will be large, don't attempt a single Write call. Instead:

1. **Write a skeleton first** — use the Write tool with just the structural outline / boilerplate (imports, function signatures, empty blocks)
2. **Fill in sections with Edit** — use multiple Edit calls to populate each section incrementally
3. **Verify** — Read the final file to confirm completeness

**Recovery:** If a Write call fails with missing parameter errors on large content, do not retry the same call. Switch to the skeleton + Edit approach above.
