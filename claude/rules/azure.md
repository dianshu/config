## Azure

When the user provides an Azure Portal URL (e.g., `https://portal.azure.com/#@.../resource/subscriptions/.../resourceGroups/.../providers/...`), extract the resource identifiers from the URL path rather than treating it as an API endpoint. These URLs contain useful identifiers like subscription IDs, resource group names, and resource names, but they are not usable as API endpoints directly. Use the extracted identifiers with Azure CLI, SDKs, or ARM REST APIs instead.

## Azure Resource Verification

When writing KQL queries, Bicep templates, or alert rules that reference Log Analytics tables or fields, always verify actual schema first — never guess field names, table names, or resource IDs.

Verification commands:
- **Single table schema (KQL):** `TableName | getschema`
- **Entire workspace schema (CLI):** `az monitor log-analytics workspace get-schema --resource-group <rg> --workspace-name <workspace>`
- **Resource IDs:** `az resource show` to confirm actual resource ID format before using in Bicep `resourceId()` calls
