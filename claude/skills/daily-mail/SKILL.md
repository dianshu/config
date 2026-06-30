---
name: daily-mail
description: Use when the user wants to review unread emails, says "daily mail", "check my email", "unread emails", "inbox review", "mail digest", "看邮件", "未读邮件", or wants a daily email summary with actionable triage
---

# Daily Mail

Review and triage unread emails from the last 3 days, verifying actionability through external systems (ADO pipelines, S360, Azure Monitor, etc.). Verification is parallelized via sub-agents; the main agent only fetches, classifies, dispatches, and aggregates.

## Workflow

The main agent's job is: (1) compute the time window, (2) fetch + classify all unread emails inline, (3) bucket them by verification path and dispatch one sub-agent per non-empty bucket **in a single assistant message**, (4) aggregate. Do **not** run verification inline.

### Step 0 — Compute the absolute time window (main agent)

Compute once in UTC ISO 8601 (`YYYY-MM-DDTHH:MM:SSZ`) and embed verbatim in every sub-agent prompt. Sub-agents MUST NOT recompute "now":

- `END_UTC` = current UTC time
- `START_UTC` = `END_UTC − 3d`

### Step 1 — Fetch unread emails (main agent, inline)

```
SearchMessagesQueryParameters:
  queryParameters: "?$filter=isRead eq false and receivedDateTime ge <START_UTC>&$orderby=receivedDateTime desc&$select=id,subject,from,receivedDateTime,bodyPreview,importance,hasAttachments"
```

**Pagination:** When the API returns `hasMoreResults: true` with a `nextLink`, keep calling `SearchMessagesQueryParameters` with the `nextLink` until all results are fetched.

### Step 2 — Classify by verification path (main agent, inline)

Classify each email into exactly one bucket below, based on subject/sender/bodyPreview. Use `GetMessage` inline ONLY when bodyPreview is insufficient to classify (don't deep-read here — that's the sub-agent's job).

| Bucket | Matches | Sub-agent |
|---|---|---|
| **ADO** | Build failure, manual validation pending, release notifications | A |
| **AzureMonitor** | Probe failure / Sev incident / Azure Monitor alert / `*-nodata` / `*-failure` | B |
| **S360** | S360 daily report, KPI digest | C |
| **External** | Grok daily digest, other links that require opening a webpage to read full content | D |
| **LightTouch** | Meeting invites, learning events, insurance/financial notifications, Meetup registration | E |
| **Noise** | Medium articles, Microsoft Daily Digest, marketing, "build succeeded" auto-notifications, resolved-incident emails with no companion active alert | (no sub-agent — render directly in "Ignored by Rule") |

Build a per-bucket list `[{id, subject, from, receivedDateTime}, ...]`. Skip dispatching sub-agents for empty buckets.

### Step 3 — Dispatch (single message, N parallel Agent calls)

Use `subagent_type: general-purpose` for all. Issue all sub-agent `Agent` calls in **one assistant message**. Each prompt MUST be self-contained.

**Shared context block to embed verbatim in every sub-agent prompt** (substitute `<...>` placeholders):

```
- Time window (use these EXACT timestamps, do NOT recompute):
  - START_UTC = <START_UTC>
  - END_UTC   = <END_UTC>
- ADO org: https://dev.azure.com/AIVertical, project: AIHardware
- Azure subscription: f497e8c9-69ff-4479-9f68-778e799b162a (STCA-Carina). Always pass `--subscription f497e8c9-69ff-4479-9f68-778e799b162a` to every `az` command. Read-only operations only.
- Mail MCP is available for `GetMessage`, `SearchMessages*` (read-only).
- Email list assigned to you (verbatim):
  <bucketed list of {id, subject, from, receivedDateTime}>
- **HARD RULE — no synthesized fields:** Every ID, date, count, hostname, IP, etc. you report must come from an actual API/tool response OR verbatim email text. Never infer or pattern-match. If the email lists items the source-of-truth API doesn't return, say so explicitly — don't carry them forward.
- Output format:
  - Markdown, lead with a one-line verdict: `✅ all clear` / `⚠️ N need action` / `🚨 sub-agent failed: <reason>`
  - Then for EACH email: `- [<verdict-icon>] **<subject>** — <one-line reason with concrete evidence>` where verdict-icon ∈ {✅ can-ignore, ⚠️ needs-action, ℹ️ worth-noting}.
  - For each ⚠️ item, include the actionable next step (link / command / approver).
  - If a verification command fails (auth, timeout, permission), report that email as `🚨 verify-failed: <command> → <error>` rather than silently dropping it.
```

#### Sub-agent A — ADO pipeline emails

For each assigned email:
1. Read full body via `GetMessage` to extract `buildId`, pipeline name, branch.
2. Check current build state:
   ```
   az pipelines build show --id <buildId> --org https://dev.azure.com/AIVertical --project AIHardware \
     --query "{status:status, result:result, finishTime:finishTime, definitionName:definition.name}" -o json
   ```
3. Classify:
   - `status==completed && result==succeeded` → `✅ can-ignore` (covers manual-validation-pending emails where the stage was already approved/bypassed — do NOT tell the user to approve it again)
   - `result==failed` → check for a later successful run on the same branch:
     ```
     az pipelines build list --org https://dev.azure.com/AIVertical --project AIHardware --top 5 \
       --query "[?definition.name=='<pipeline>' && sourceBranch=='<branch>'].{id:id, status:status, result:result, finishTime:finishTime}" -o json
     ```
     - Later success → `✅ can-ignore` (self-recovered)
     - No later success → `⚠️ needs-action`, include build URL + failed stage if available
   - Still running → `ℹ️ worth-noting`

#### Sub-agent B — Azure Monitor alert emails

For each assigned email (typically probe failures / scheduled-query alerts):
1. Read full HTML via `GetMessage` with `preferHtml: true`. Alert emails are large (100KB+); if needed, write the body to a tmp file and grep:
   ```bash
   grep -oP 'scheduledqueryrules/[^"\\&]+' <file> | head -1   # rule name
   grep -oP 'subscriptions/[a-f0-9-]+' <file> | head -1       # subscription
   grep -oP 'resourceGroups/[^/]+' <file> | head -1            # resource group
   ```
2. Fetch the rule's underlying KQL + workspace scope:
   ```
   az monitor scheduled-query show --name <rule> -g <rg> --subscription <sub> --query "criteria.allOf[0].query" -o tsv
   az monitor scheduled-query show --name <rule> -g <rg> --subscription <sub> --query "scopes[0]" -o tsv
   ```
   Resolve workspace customerId (the `--workspace` flag needs the GUID, not the resource path):
   ```
   az monitor log-analytics workspace show -g <ws-rg> --workspace-name <ws-name> --subscription <sub> --query "customerId" -o tsv
   ```
3. Re-run the rule's KQL with the `| where ... fail` filter REMOVED, scoped to the time window, last 10 runs:
   ```
   az monitor log-analytics query --workspace <customerId> --analytics-query "<base-query without fail filter> | where TimeGenerated between (datetime(<START_UTC>) .. datetime(<END_UTC>)) | project TimeGenerated, status=tostring(log.status) | order by TimeGenerated desc | take 10" -o table
   ```
4. Classify:
   - All 10 recent runs `pass` → `✅ can-ignore` (self-recovered)
   - Any `fail` in the last 10 → `⚠️ needs-action`, quote the latest fail reason
   - A companion RESOLVED email exists in the same conversation AND recent runs pass → `✅ can-ignore`

#### Sub-agent C — S360 daily report

For each assigned email:
1. Identify the service `targetId` from the email subject/body (or session memory). Always query by `targetIds`, NOT by `assignedTo` alias.
2. Query active items:
   ```
   search_active_s360_kpi_action_items:
     request: { targetIds: ["<service-id>"], pageSize: 50 }
   ```
3. Classify:
   - Zero active items → `✅ can-ignore`
   - Items exist → `⚠️ needs-action`, list `KpiName | dueDate | slaStatus` for each

#### Sub-agent D — External link emails (Grok etc.)

For each assigned email:
1. Read full HTML via `GetMessage` with `preferHtml: true`.
2. Extract the canonical URL from link hrefs — use the `originalsrc` attribute, NOT the Safelinks wrapper. For Grok, look for `grok.com/chat/`.
3. Fetch the URL via the web-fetching fallback chain (defuddle.md → searxng → Chrome MCP). If Chrome shows a login wall, tell the user and pause.
4. Summarize the key points in 3-5 bullets.
5. Classify as `ℹ️ worth-noting`. Include the summary inline.

#### Sub-agent E — Light-touch emails

For each assigned email:
1. Read full body via `GetMessage` only if bodyPreview is insufficient.
2. Classify per type:
   - **Meetup / team registration** ("Time to Meetup!", "Register for Meetup", etc.): `⚠️ needs-action`, include registration link + deadline.
   - **Meeting invites** (`eventMessageRequest` type), learning events: `ℹ️ worth-noting`, one-line summary `<topic> | <sender>`.
   - **Insurance / financial "do not reply" notifications** with a completed transaction: `✅ can-ignore`.
   - Anything else: `ℹ️ worth-noting` with a one-line summary.

### Step 4 — Retry failed sub-agents (main agent)

After collecting all sub-agent responses, identify any that:
- returned no response / empty body, OR
- led with `🚨 sub-agent failed`, OR
- raised a tool error during dispatch.

**Re-dispatch each failed sub-agent exactly once with the identical prompt**, again in a single assistant message (parallel retry). After this single retry:
- Success on retry → use the retried result.
- Still failing → render that bucket's section as `🚨 broken — sub-agent failed after 1 retry: <reason>`. Never imply healthy when verification didn't run.

Do NOT loop beyond one retry.

### Step 5 — Aggregate (main agent)

Render the final report in the user's language (Chinese if conversation is in Chinese):

```markdown
### Needs Action
1. **[Subject]** — [what needs to be done + link/command]

### Worth Noting
1. **[Subject]** — [brief summary]

### Can Ignore (verified)
| Email | Reason |
|-------|--------|
| [Subject] | [verification evidence, e.g. "probe recovered, last 10 runs all pass"] |

### Ignored by Rule
| Email | Rule |
|-------|------|
| [Subject] | [which rule matched, e.g. "Medium article", "Microsoft Daily Digest"] |

### Meeting Invites / Learning Events
| Subject | Sender | Description |
|---------|--------|-------------|
| [Subject] | [Sender] | [One-line summary] |

### Verification Failures (if any)
| Bucket | Reason |
|--------|--------|
| [A/B/C/D/E] | [reason after 1 retry] |
```

**Distinction:**
- **Can Ignore (verified)** — could have needed action; sub-agent verified against source system and confirmed safe.
- **Ignored by Rule** — categorically noise per the classification table; never dispatched.

## Constraints

- The 3-day window is computed once by the main agent and passed verbatim into sub-agents — they MUST NOT recompute "now".
- A sub-agent reporting empty findings still includes its `✅ all clear` verdict so the user can see it ran.
- Every Azure resource-management `az` command MUST include `--subscription f497e8c9-69ff-4479-9f68-778e799b162a`. Azure DevOps commands (`az pipelines`, `az repos`, `az devops invoke`) MUST NOT pass `--subscription`. Read-only operations only (STCA-Carina guard).
- Always read the full email (`GetMessage`) before making a verification decision — `bodyPreview` is often truncated. Classification (Step 2) can use bodyPreview; verification (sub-agents) MUST use the full body.
- When multiple emails describe the same incident (AWARENESS → RESOLVED), group them in the output.
- Failed sub-agents get exactly one retry (Step 4). Never silently drop a bucket.
