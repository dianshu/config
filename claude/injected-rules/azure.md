## Azure

When the user provides an Azure Portal URL (e.g., `https://portal.azure.com/#@.../resource/subscriptions/.../resourceGroups/.../providers/...`), extract the resource identifiers from the URL path rather than treating it as an API endpoint. These URLs contain useful identifiers like subscription IDs, resource group names, and resource names, but they are not usable as API endpoints directly. Use the extracted identifiers with Azure CLI, SDKs, or ARM REST APIs instead.

## Azure DevOps URLs

When the user provides an Azure DevOps URL (`https://dev.azure.com/...`), do NOT open it in Chrome or fetch it via web tools. Instead, extract org, project, and resource IDs from the URL path and use `az` CLI commands to access the data. Examples:

- **Build results** (`_build/results?buildId=123`): `az pipelines build show --id 123`, `az devops invoke --area build --resource timeline` for step details, `az devops invoke --area build --resource logs --route-parameters logId=N` for logs
- **Pull requests** (`_git/Repo/pullrequest/456`): `az repos pr show --id 456`
- **Work items** (`_workitems/edit/789`): `az boards work-item show --id 789`

## Azure Resource Verification

When writing KQL queries, Bicep templates, or alert rules that reference Log Analytics tables or fields, always verify actual schema first — never guess field names, table names, or resource IDs.

Verification commands:
- **Single table schema (KQL):** `TableName | getschema`
- **Entire workspace schema (CLI):** `az monitor log-analytics workspace get-schema --resource-group <rg> --workspace-name <workspace>`
- **Resource IDs:** `az resource show` to confirm actual resource ID format before using in Bicep `resourceId()` calls

## STCA-Carina Subscription — Read-Only Guard

When an `az` CLI command targets the **STCA-Carina** subscription (by name or subscription ID), apply these rules:

- **Auto-execute** read-only operations: `show`, `list`, `get-*`, `query`, `export`, `download`, `check-name-availability`, and any command whose sole effect is retrieving or displaying data.
- **Confirm with user** before executing any mutating operation: `create`, `update`, `delete`, `set`, `start`, `stop`, `restart`, `apply`, `import`, `move`, `swap`, `failover`, `regenerate-key`, `revoke`, `scale`, `resize`, or any command that modifies, creates, or removes a resource.
- **When uncertain** whether a command is read-only, confirm with the user before executing.

When confirming, state the command, the target resource, and the expected effect.
