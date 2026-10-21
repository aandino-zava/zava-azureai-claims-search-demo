# Deployment

## 1. Prepare your Azure target

Install Azure CLI, PowerShell 7.2 or later, and Bicep 0.48.1. Azure CLI must support the `--validation-level` deployment option.

```powershell
az login --tenant '<tenant-id>'
az bicep install --version v0.48.1
```

Select a subscription and an existing resource group in your tenant. An administrator must register `Microsoft.Search`, `Microsoft.CognitiveServices`, and `Microsoft.Storage` in the subscription if needed.

The deploying identity needs **Contributor**, **Storage Blob Data Contributor**, and **Search Index Data Contributor** at the target resource group. These permissions cover resource deployment, the two PDF uploads, and keyless blob knowledge-source setup. Contributor includes the Search service management permissions; it does not include Search index data access. See the [blob knowledge-source prerequisites](https://learn.microsoft.com/en-us/azure/search/agentic-knowledge-source-how-to-blob#prerequisites).

It also needs permission to create the template's two access grants for Search. An administrator can use a conditional **Role Based Access Control Administrator** assignment scoped to the target resource group, allowing only **Storage Blob Data Reader** and **Cognitive Services OpenAI User** assignments to service principals. The incremental deployment does not need permission to delete role assignments. Do not grant directory administration for deployment.

## 2. Set the resource names

Edit [config/demo.json](../config/demo.json):

| Setting | Purpose |
| --- | --- |
| `location` | Region for the services and project |
| `searchServiceName` | Globally unique Search service name |
| `foundryName` | Foundry resource name and unique subdomain |
| `projectName` | Foundry project name |
| `storageAccountName` | Globally unique storage account name |
| `containerName` | Container for the two PDFs |
| `imageOutputContainerName` | Separate private container for image outputs |
| `knowledgeSourceName` | Stable name for the blob knowledge source |
| `embeddingDeployment` | Embedding deployment name, model version, SKU, and capacity |
| `chatDeployment` | Image-description deployment name, model version, SKU, and capacity |

Replace the example service names with your own available names. The same configuration is used for validation, deployment, and file upload. To use another configuration file locally, pass `-ConfigurationPath '<path>'` to the scripts.

The template uses Search Standard, Foundry S0, and Storage Standard ZRS with public service endpoints. The example model settings are `text-embedding-3-large` version `1` on Standard capacity `1`, and `gpt-5-mini` version `2025-08-07` on GlobalStandard capacity `10`. Choose a region and subscription with support and quota for these deployments, or explicitly configure supported model settings.

## 3. Preview and deploy

Run these commands from the repository root:

```powershell
./scripts/Test-Package.ps1
./scripts/Deploy.ps1 -SubscriptionId '<subscription-id>' -ResourceGroupName '<resource-group>' -Mode Validate
./scripts/Deploy.ps1 -SubscriptionId '<subscription-id>' -ResourceGroupName '<resource-group>' -Mode WhatIf
./scripts/Deploy.ps1 -SubscriptionId '<subscription-id>' -ResourceGroupName '<resource-group>' -Mode Deploy
```

| Mode | Result |
| --- | --- |
| Validate | Check the package and run ARM provider validation |
| WhatIf | Validate, then display proposed changes |
| Deploy | Validate, display changes, deploy infrastructure, upload both PDFs, and configure the knowledge source |

Review the WhatIf result before choosing Deploy. Validation checks the selected destination but does not reserve service capacity.

ARM validation and WhatIf cover the Bicep resources. The separate Search REST request is saved to `.build/knowledge-source.json` for review and runs only in Deploy mode. Search knowledge sources are data-plane objects, so they are configured after Bicep through the `2025-11-01-preview` Search API.

Deployment uses incremental mode. Reruns keep the configured names and replace the same two blob files. Matching resources created outside this package are rejected; resources managed by the package must retain their region and ownership tag.

If an upload fails after resource deployment, resolve the reported access or connectivity issue and resume the upload:

```powershell
./scripts/Upload-Claims.ps1 -SubscriptionId '<subscription-id>' -ResourceGroupName '<resource-group>'
```

The script uploads only the two manifest files, downloads them to verify their SHA-256 hashes, and preserves other blobs in the container.

After the infrastructure and files are ready, the knowledge source can be configured or resumed separately:

```powershell
./scripts/Configure-KnowledgeSource.ps1 -SubscriptionId '<subscription-id>' -ResourceGroupName '<resource-group>'
```

The source uses minimal content extraction, image verbalization, and a daily (`P1D`) ingestion schedule. Search uses its managed identity to access storage and the two models. Setup reads back the saved definition; ingestion completes asynchronously. Retries for access propagation are bounded, and updates use the existing definition's ETag to avoid overwriting a concurrent change.

The image-output container is created empty. This package does not configure an image-export projection or asset-store binding.

## GitHub Actions

1. Fork or copy this repository, enable Actions in your copy, and commit your changes to [config/demo.json](../config/demo.json).
2. Under **Settings → Environments**, create an environment named `demo`.
3. Connect that environment to your own Azure tenant using [Azure's GitHub Actions OIDC setup guide](https://learn.microsoft.com/en-us/azure/developer/github/connect-from-azure-openid-connect). Use your repository and its `demo` environment for the federation binding. Supply your own Azure connection inputs, shown in the [deployment workflow](../.github/workflows/deploy.yml), through the environment's settings. Give the deployment identity the permissions under **Prepare your Azure target** above.
4. Open **Actions → Deploy demo → Run workflow**. Choose **WhatIf** to review the changes, then **Deploy** to create the infrastructure, upload the PDFs, and configure the knowledge source.

Keep tenant-specific connection values in GitHub's environment settings. Deployment runs manually; the separate validation workflow runs on pushes and pull requests.
