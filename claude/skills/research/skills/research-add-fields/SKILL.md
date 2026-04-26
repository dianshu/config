---
name: research-add-fields
description: Add comparison dimensions to an existing research fields definition. Use when the user says "add field", "also compare by X", "add dimension", or wants to extend comparison criteria.
---

# Add Research Fields

Adds new comparison dimensions to an existing `fields.yaml`.

## Process

1. Find the most recent `research-*/fields.yaml` in the current directory
2. Read the existing fields
3. Ask the user what dimensions to add (or parse from their message)
4. Optionally spawn a web-search-agent to suggest relevant dimensions:
   - Read `~/.claude/skills/research/agents/web-search-agent.md`
   - Load `~/.claude/skills/research/agents/modules/general-web.md`
   - Search for commonly compared dimensions for this topic
5. Determine the appropriate category for each new field (match existing categories or create new)
6. Append new fields to `fields.yaml`, avoiding duplicates (check by field name)
7. Write the updated `fields.yaml`
8. Inform the user: "Added {N} fields. Run `/research-retrieve` to gather data for new fields."
