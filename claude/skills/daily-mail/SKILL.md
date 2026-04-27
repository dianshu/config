---
name: daily-mail
description: Use when the user wants to review unread emails, says "daily mail", "check my email", "unread emails", "inbox review", "mail digest", "看邮件", "未读邮件", or wants a daily email summary with actionable triage
---

# Daily Mail

Review and triage unread emails, categorizing them by urgency and verifying actionability through external systems (ADO pipelines, S360, etc.).

## Workflow

```dot
digraph daily_mail {
  rankdir=TB;
  "Fetch unread emails" -> "Categorize by type";
  "Categorize by type" -> "Verify actionability";
  "Verify actionability" -> "Present summary";
}
```

### Step 1: Fetch Unread Emails

Use the Mail MCP to fetch all unread emails from the last 3 days. Calculate the date dynamically (today minus 3 days in ISO 8601 format).

```
SearchMessagesQueryParameters:
  queryParameters: "?$filter=isRead eq false and receivedDateTime ge <3-days-ago>T00:00:00Z&$orderby=receivedDateTime desc&$select=id,subject,from,receivedDateTime,bodyPreview,importance,hasAttachments"
```

**Pagination:** The API returns `hasMoreResults: true` with a `nextLink` when there are more results. Keep calling `SearchMessagesQueryParameters` with the `nextLink` until all results are fetched.

### Step 2: Categorize by Type

Classify each email into one of these categories:

| Category | Examples | Default Action |
|----------|----------|----------------|
| **Needs Action** | Manual validation pending, approval requests, assigned tasks | Verify then present |
| **Alerts** | Azure Monitor alerts, build failures, Sev incidents | Verify current status |
| **Reports** | S360 daily report, digest emails | Cross-check with source system |
| **Informational** | Build succeeded, resolved incidents, newsletters | Summarize briefly |
| **Noise** | Medium articles, auto-digests, Microsoft Daily Digest | Skip unless user asks |

### Step 3: Verify Actionability

For each "Needs Action" or "Alert" email, verify against the source system before presenting:

#### ADO Pipeline Notifications

For build failure or manual validation emails:

1. Extract the build ID and pipeline name from the email body (read full email via `GetMessage` if needed)
2. Check the build status:
   ```
   az pipelines build show --id <buildId> --org <org> --project <project> --query "{status: status, result: result, finishTime: finishTime, definitionName: definition.name}" -o json
   ```
3. If the build already completed successfully → mark as "can ignore". **This includes manual validation pending emails** — if the overall build/release run has status=completed and result=succeeded, it means the validation stage was already approved or bypassed. Do NOT tell the user they still need to approve it.
4. For build failures, check if a subsequent run on the same branch succeeded:
   ```
   az pipelines build list --org <org> --project <project> --top 5 --query "[?definition.name=='<pipeline>'].{id:id, buildNumber:buildNumber, status:status, result:result, finishTime:finishTime, sourceBranch:sourceBranch}" -o json
   ```
5. If a later run succeeded on the same branch → mark as "can ignore"

#### S360 Daily Report

1. Query active action items for the service using S360 MCP:
   ```
   search_active_s360_kpi_action_items:
     request: { targetIds: ["<service-id>"], pageSize: 50 }
   ```
   **Important:** Query by service targetId, NOT by assignedTo alias (check memory for the correct service ID).
2. If no active items → mark as "can ignore"
3. If items exist → list them with KPI name, due date, and status

#### Azure Monitor Alerts

1. Read the full email to get alert details (severity, resource, timestamp)
2. Check if a "RESOLVED" email exists in the same conversation
3. For **probe failure** alerts (e.g., "LB Probe Failure", "Mem0 Probe Failure"):
   a. Read the full email HTML via `GetMessage` with `preferHtml: true`. Alert emails are typically very large (100KB+), so save to file and use `grep` to extract identifiers:
      ```bash
      grep -oP 'scheduledqueryrules/[^"\\&]+' <saved-file> | head -1   # rule name
      grep -oP 'subscriptions/[a-f0-9-]+' <saved-file> | head -1       # subscription
      grep -oP 'resourceGroups/[^/]+' <saved-file> | head -1            # resource group
      ```
   b. Get the alert rule's underlying KQL query:
      ```
      az monitor scheduled-query show --name <rule-name> --resource-group <rg> --subscription <sub> --query "criteria.allOf[0].query" -o tsv
      ```
   c. Get the workspace scope and resolve its customer ID (the `--workspace` parameter requires the GUID, not the resource path):
      ```
      az monitor scheduled-query show --name <rule-name> --resource-group <rg> --subscription <sub> --query "scopes[0]" -o tsv
      # Extract workspace-name and its resource-group from the scope path, then:
      az monitor log-analytics workspace show --resource-group <ws-rg> --workspace-name <ws-name> --subscription <sub> --query "customerId" -o tsv
      ```
   d. Modify the KQL query to show **both pass and fail** results (remove the `| where log.status == 'fail'` filter), then query the last 10 runs:
      ```
      az monitor log-analytics query --workspace <customer-id-guid> --analytics-query "<base-query without fail filter> | project TimeGenerated, status = tostring(log.status) | order by TimeGenerated desc | take 10" -o table
      ```
   e. If all recent runs show `pass` → mark as "can ignore" (self-recovered). If any show `fail` → surface as active alert in **Needs Action**.
4. For other alerts, present current status

#### Insurance / Financial Notifications

1. Read full email to determine if it's a pure notification or requires action
2. System-generated "do not reply" emails with completed transactions → mark as "can ignore"

#### Grok AI Daily Digest

**IMPORTANT: Always execute these steps for Grok emails. Do NOT just summarize the email body — it is always truncated.**

1. Read the full email HTML via `GetMessage` with `preferHtml: true`
2. Extract the Grok chat URL from the HTML (search for `grok.com/chat/` in link hrefs, use the `originalsrc` attribute, not the safelinks wrapper)
3. Open the URL using Chrome MCP (`new_page`)
4. If login is required, use Google login flow (click "使用 Google 登录", select account)
5. Take a snapshot (`take_snapshot`) and extract the full content
6. Summarize the key points and present in **Worth Noting**

#### Meetup Registration / Team Events

**IMPORTANT: Meetup registration emails (e.g., "Time to Meetup!", "Register for Meetup") are high-priority — always surface them in "Needs Action" with the registration link.**

1. Read the full email via `GetMessage` to extract the registration link
2. Present in **Needs Action** with the registration deadline and link

#### Meeting Invites / Learning Events

1. For calendar invites (`eventMessageRequest` type) and activity/learning invitations, do NOT deep-verify
2. Present a brief one-line summary table with: sender, topic description
3. Format as: `| Subject | Sender | Brief description |`

### Step 4: Present Summary

Output a structured summary table:

```markdown
### Needs Action
1. **[Subject]** — [what needs to be done]

### Worth Noting
1. **[Subject]** — [brief summary]

### Can Ignore (verified)
| Email | Reason |
|-------|--------|
| [Subject] | [why — with verification result, e.g. "probe recovered, last 10 runs all pass"] |

### Ignored by Rule
| Email | Rule |
|-------|------|
| [Subject] | [which rule matched, e.g. "Medium article", "build succeeded notification", "Microsoft Daily Digest"] |

### Meeting Invites / Learning Events
| Subject | Sender | Description |
|---------|--------|-------------|
| [Subject] | [Sender name] | [One-line summary of the event/meeting] |
```

**Distinction:**
- **Can Ignore (verified)**: Emails that *could* have needed action, but were verified against the source system and confirmed safe to skip (e.g., build failure with subsequent success, probe alert that self-recovered, S360 report with zero items)
- **Ignored by Rule**: Emails that are categorically noise and don't need verification (e.g., Medium articles, Microsoft Daily Digest, build succeeded notifications, marketing emails, newsletters)

## Notes

- Always read the full email (`GetMessage`) before making triage decisions — `bodyPreview` is often truncated
- For ADO pipeline emails, the org/project info can be extracted from URLs in the email body
- Grok daily digest emails may contain truncated content in the email body; always open the linked Grok chat for full content
- When multiple emails are about the same incident (e.g., AWARENESS → RESOLVED), group them together
- Present the summary in the user's language (Chinese if the conversation is in Chinese)
