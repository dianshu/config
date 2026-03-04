---
name: ado-code-search
description: Use when the user wants to search for text or code across Azure DevOps repositories, says "search ADO", "find in repo", "grep remote repo", or needs to locate files containing specific strings in ADO repos
---

# ADO Code Search

Search for text across Azure DevOps repositories via the Code Search REST API. Returns matching files with repo name, file path, and clickable URLs that highlight the exact match location.

## Prerequisites

- `az login` completed (used to obtain Bearer token)
- Code Search extension installed on the ADO organization
- `jq` available for JSON processing

## Authentication

The Code Search API lives on `almsearch.dev.azure.com`, which `az rest` cannot auto-authenticate. Obtain a Bearer token manually:

```bash
TOKEN=$(az account get-access-token --resource "499b84ac-1321-427f-aa17-267ca6975798" --query accessToken -o tsv)
```

The resource GUID `499b84ac-1321-427f-aa17-267ca6975798` is the Azure DevOps application ID (fixed, not org-specific).

## Search API

**Endpoint:** `POST https://almsearch.dev.azure.com/{org}/{project}/_apis/search/codesearchresults?api-version=7.0`

- Omit `{project}` to search across all projects in the organization.
- Default branch only. Configure additional branches in Project Settings > Repositories > Searchable Branches.

**Request body:**

```json
{
  "searchText": "your search text",
  "$top": 50,
  "filters": {
    "Repository": ["RepoName"],
    "Branch": ["main"]
  }
}
```

All filter fields are optional.

## Constructing Clickable URLs

The API returns `charOffset` and `length` per match but does NOT return line/column numbers. To build a URL that highlights the exact match:

1. Fetch file content via Git Items API
2. Count newlines before `charOffset` to get line number: `line = newlines_in_prefix + 1`
3. Calculate column from distance to last newline: `col = offset - last_newline_position`

**ADO file URL with line highlighting:**

```
https://dev.azure.com/{org}/{project}/_git/{repo}?path={path}&version=GB{branch}&line={line}&lineEnd={line}&lineStartColumn={col}&lineEndColumn={col+length}&lineStyle=plain&_a=contents
```

## Complete Script

```bash
TOKEN=$(az account get-access-token --resource "499b84ac-1321-427f-aa17-267ca6975798" --query accessToken -o tsv)
ORG="${1:-$CC_ADO_ORG}"
PROJECT="${2:-$CC_ADO_PROJECT}"  # set to "" for org-wide search
SEARCH_TEXT="${3:?Usage: script.sh [org] [project] <search_text>}"

if [ -n "$PROJECT" ]; then
  SEARCH_URL="https://almsearch.dev.azure.com/${ORG}/${PROJECT}/_apis/search/codesearchresults?api-version=7.0"
else
  SEARCH_URL="https://almsearch.dev.azure.com/${ORG}/_apis/search/codesearchresults?api-version=7.0"
fi

RESULTS=$(curl -s -X POST "$SEARCH_URL" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d "{\"searchText\": \"${SEARCH_TEXT}\", \"\$top\": 50}")

COUNT=$(echo "$RESULTS" | jq '.count')
echo "Found $COUNT match(es) for \"$SEARCH_TEXT\""
echo "========================================"

echo "$RESULTS" | jq -c '.results[]?' | while read -r result; do
  PROJ=$(echo "$result" | jq -r '.project.name')
  REPO=$(echo "$result" | jq -r '.repository.name')
  FILEPATH=$(echo "$result" | jq -r '.path')
  BRANCH=$(echo "$result" | jq -r '.versions[0].branchName')

  FILE_CONTENT=$(curl -s \
    "https://dev.azure.com/${ORG}/${PROJ}/_apis/git/repositories/${REPO}/items?path=${FILEPATH}&api-version=7.0" \
    -H "Authorization: Bearer $TOKEN")

  echo "$result" | jq -c '.matches.content[]?' | while read -r match; do
    OFFSET=$(echo "$match" | jq '.charOffset')
    LENGTH=$(echo "$match" | jq '.length')

    PREFIX="${FILE_CONTENT:0:$OFFSET}"
    NEWLINES=$(echo -n "$PREFIX" | tr -cd '\n' | wc -c)
    LINE=$(($NEWLINES + 1))

    LAST_NL_POS=$(echo -n "$PREFIX" | grep -bo $'\n' | tail -1 | cut -d: -f1)
    if [ -z "$LAST_NL_POS" ]; then
      COL=1
    else
      COL=$(($OFFSET - $LAST_NL_POS))
    fi
    END_COL=$(($COL + $LENGTH))

    URL="https://dev.azure.com/${ORG}/${PROJ}/_git/${REPO}?path=${FILEPATH}&version=GB${BRANCH}&line=${LINE}&lineEnd=${LINE}&lineStartColumn=${COL}&lineEndColumn=${END_COL}&lineStyle=plain&_a=contents"

    echo ""
    echo "Repo:   $REPO"
    echo "File:   $FILEPATH"
    echo "Line:   $LINE, Col: $COL-$END_COL"
    echo "URL:    $URL"
  done
done
```

## Quick Reference

| Parameter | Default | Description |
|-----------|---------|-------------|
| `ORG` | `$CC_ADO_ORG` | Azure DevOps organization name |
| `PROJECT` | `$CC_ADO_PROJECT` | Project to search (empty string = org-wide) |
| `searchText` | *(required)* | The text to search for |
| `$top` | `50` | Max results |
| `filters.Repository` | *(all repos)* | Array of repo names to restrict search |
| `filters.Branch` | *(default branch)* | Array of branch names to restrict search |

**Inline search text filters:**

| Syntax | Example |
|--------|---------|
| `proj:Name` | Restrict to project |
| `repo:Name` | Restrict to repo |
| `path:a/b/c` | Restrict to path |
| `ext:py` | Restrict to file extension |
| `file:name*` | Restrict by filename pattern |

Filters can go in the `filters` object or inline in `searchText` (e.g., `"azure-monitor-query repo:MyRepo ext:txt"`).

## Common Mistakes

| Mistake | Prevention |
|---------|-----------|
| Using `az rest` for Code Search API | `az rest` cannot auto-derive token for `almsearch.dev.azure.com`. Use `curl` with explicit Bearer token. |
| Assuming API returns line numbers | API only returns `charOffset` and `length`. Fetch file content and calculate line/column manually. |
| Searching only within a project when text may be elsewhere | Omit project from URL to search org-wide. |
| Trusting `matches[].line` field | The `line` field in API response is always 0. Ignore it; calculate from `charOffset`. |
