## Large File Writing Strategy

When writing files with large content (roughly >500 lines or >15KB), the Write tool call may fail due to output token truncation — the JSON parameters get cut off, causing missing `file_path` or `content` errors.

**Prevention:** When you know the content will be large, don't attempt a single Write call. Instead:

1. **Write a skeleton first** — use the Write tool with the structural outline, boilerplate, and **unique named placeholders** for each content section (e.g. `<!-- PLACEHOLDER_INTRO -->`, `# PLACEHOLDER_IMPL`). Placeholders make Edit replacements reliable by providing exact, unique match strings.
2. **Fill in sections with Edit** — replace one placeholder at a time. Keep each Edit chunk under ~100 lines to avoid the same truncation problem on the Edit call itself.
3. **Verify** — grep for remaining placeholders (`grep -c "PLACEHOLDER" <file>`) to confirm all sections were filled, then Read the file to spot-check.

**Recovery:** If a Write call fails with missing parameter errors on large content, do not retry the same call. Switch to the skeleton + Edit approach above.
