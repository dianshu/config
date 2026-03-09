## Azure

When the user provides an Azure Portal URL (e.g., `https://portal.azure.com/#@.../resource/subscriptions/.../resourceGroups/.../providers/...`), extract the resource identifiers from the URL path rather than treating it as an API endpoint. These URLs contain useful identifiers like subscription IDs, resource group names, and resource names, but they are not usable as API endpoints directly. Use the extracted identifiers with Azure CLI, SDKs, or ARM REST APIs instead.
