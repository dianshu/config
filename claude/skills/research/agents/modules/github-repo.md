# GitHub Repository Analysis Strategy

## Commands
Use the GitHub CLI (`gh`) for repository analysis:

### Basic Repository Information
```bash
gh repo view {owner}/{repo} --json name,description,stargazerCount,forkCount,createdAt,updatedAt,primaryLanguage,topics,isArchived,visibility
```

### Recent Commits Activity
```bash
gh api repos/{owner}/{repo}/commits --paginate --per-page=100 | jq '[.[] | {sha: .sha, date: .commit.author.date, message: .commit.message}] | .[0:20]'
```

### Issues Analysis
```bash
gh api repos/{owner}/{repo}/issues?state=all --paginate | jq '{open_issues: [.[] | select(.state == "open")] | length, closed_issues: [.[] | select(.state == "closed")] | length}'
```

### Contributors Count
```bash
gh api repos/{owner}/{repo}/contributors --paginate | jq '. | length'
```

### Latest Releases
```bash
gh api repos/{owner}/{repo}/releases | jq '[.[] | {tag: .tag_name, name: .name, published: .published_at, prerelease: .prerelease}] | .[0:5]'
```

### Dependencies Analysis (if available)
```bash
gh api repos/{owner}/{repo}/contents/package.json | jq -r '.content' | base64 -d | jq '.dependencies | keys | length'
# Or for other languages: requirements.txt, Gemfile, etc.
```

## Interpretation Guide

### Repository Health Indicators
- **Stars**: >1k = popular, >10k = very popular, >50k = widely adopted
- **Commit Frequency**: Daily commits = active, Weekly = maintained, Monthly = stable/mature
- **Issue Ratio**: Open/(Open+Closed) < 0.3 = well-maintained
- **Contributors**: >10 = community project, >100 = large community
- **Recent Activity**: Last commit <1 month = active development

### Red Flags
- No commits in 6+ months
- High ratio of open issues
- No releases or tags
- Single contributor with no recent activity
- Many forks but few stars (indicates abandonment)

## What to Extract
- Project maturity and adoption
- Community health and activity
- Development velocity
- Maintenance status
- Technology stack and dependencies