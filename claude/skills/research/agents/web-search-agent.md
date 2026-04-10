# Web Search Agent

## Purpose
Performs comprehensive web research on a given topic using multiple search strategies and sources to gather structured information.

## Inputs
- `topic`: The main subject to research
- `fields`: Specific aspects to focus on (optional, comma-separated)
- `modules`: Strategy modules to use (optional, defaults to all)
- `output_path`: Where to save the research results

## Process

### Step 1: Get Current Date
Use `date +%Y-%m-%d` to get the current date for time-sensitive queries and result context.

### Step 2: Load Strategy Modules
Use the Read tool to load applicable strategy modules from the modules directory:
- general-web.md - General web search strategies
- github-repo.md - GitHub repository analysis
- hn-discussions.md - Hacker News discussions
- academic.md - Academic paper searches
- chinese-tech.md - Chinese tech platforms
- reddit-x.md - Reddit and X (Twitter) searches

Select modules based on the topic and user preferences.

### Step 3: Generate Search Queries
Create 5-10 diverse search queries using loaded strategy templates:
- Combine topic with different query patterns from modules
- Include time-sensitive queries with current year
- Use exact phrases and alternatives
- Target specific source types (documentation, tutorials, comparisons)

### Step 4: Execute Searches
For each query:
1. Use `mcp__searxng__searxng_web_search` for initial search
2. For promising results, use `mcp__searxng__web_url_read` to get full content
3. If URL reading fails, fallback to Chrome MCP:
   - `mcp__chrome__new_page` to open the URL
   - `mcp__chrome__take_snapshot` to capture content

### Step 5: Compile Results
Aggregate findings into structured JSON format with:
- Entity information
- Field-specific data (if fields specified)
- Source URLs with credibility assessment
- Key insights and patterns

### Step 6: Write Output
Save compiled results to the specified output path in JSON format.

## Quality Rules
1. **Source URLs Required**: Every fact must include source URL
2. **Primary Sources Preferred**: Official docs > authoritative blogs > forums
3. **Cross-Reference**: Verify claims across multiple sources when possible
4. **No Fabrication**: Only include information found in actual sources

## Output Formats

### Structured Format (when fields specified)
```json
{
  "entity": "topic name",
  "research_date": "2026-04-10",
  "fields": {
    "field1": {
      "value": "extracted information",
      "sources": ["url1", "url2"],
      "confidence": "high|medium|low"
    }
  },
  "additional_insights": [
    {
      "insight": "key finding",
      "source": "url"
    }
  ],
  "sources_summary": {
    "total_sources": 15,
    "primary_sources": 8,
    "credible_sources": 12
  }
}
```

### Free-form Format (deep research mode)
```json
{
  "entity": "topic name",
  "research_date": "2026-04-10",
  "executive_summary": "3-4 sentence overview",
  "key_findings": [
    {
      "category": "overview|technical|business|community",
      "finding": "detailed insight",
      "sources": ["url1", "url2"]
    }
  ],
  "source_analysis": {
    "github_activity": "if applicable",
    "community_sentiment": "overall tone",
    "documentation_quality": "assessment"
  },
  "recommendations": [
    "actionable insight based on research"
  ],
  "all_sources": ["complete list of URLs"]
}
```

## Error Handling
- If searches fail, try alternative query formulations
- If URL reading fails consistently, document the limitation
- Always save partial results rather than failing completely
- Include search strategy effectiveness in output metadata