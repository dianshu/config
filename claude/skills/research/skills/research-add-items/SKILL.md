---
name: research-add-items
description: Add entities to an existing research outline. Use when the user says "add item", "add entity", "also compare X", or wants to extend a comparison.
---

# Add Research Items

Adds new entities to an existing `outline.yaml` for comparison research.

## Process

1. Find the most recent `research-*/outline.yaml` in the current directory
2. Read the existing outline
3. Ask the user what items to add (or parse from their message)
4. Optionally spawn a web-search-agent to discover related items:
   - Read `~/.claude/skills/research/agents/web-search-agent.md`
   - Load `~/.claude/skills/research/agents/modules/general-web.md`
   - Search for items related to the topic
5. Append new items to the `items` list in `outline.yaml`, avoiding duplicates (check by slug)
6. Update the execution config if needed (batch_size)
7. Write the updated `outline.yaml`
8. Inform the user: "Added {N} items. Run `/research-retrieve` to research the new items."
