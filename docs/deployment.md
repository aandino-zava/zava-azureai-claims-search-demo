# Deployment

## 1. Prepare your Azure target

Install Azure CLI, PowerShell 7.2 or later, and Bicep 0.48.1. Azure CLI must support the `--validation-level` deployment option.

```powershell
az login --tenant '<tenant-id>'
az bicep install --version v0.48.1
```

Select a subscription and an existing resource group in your tenant. An administrator must register `Microsoft.Search`, `Microsoft.CognitiveServices`, and `Microsoft.Storage` in the subscription if needed.

The deploying identity needs **Contributor** and **Storage Blob Data Contributor** at the target resource group. These permissions cover resource deployment and the two PDF uploads.

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

Replace the example service names with your own available names. The same configuration is used for validation, deployment, and file upload. To use another configuration file locally, pass `-ConfigurationPath '<path>'` to the scripts.

The template uses Search Standard, Foundry S0, and Storage Standard ZRS with public service endpoints. Choose a region and subscription that support this configuration.

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
| Deploy | Validate, display changes, deploy, and upload both PDFs |

Review the WhatIf result before choosing Deploy. Validation checks the selected destination but does not reserve service capacity.

Deployment uses incremental mode. Reruns keep the configured names and replace the same two blob files. Matching resources created outside this package are rejected; resources managed by the package must retain their region and ownership tag.

If an upload fails after resource deployment, resolve the reported access or connectivity issue and resume the upload:

```powershell
./scripts/Upload-Claims.ps1 -SubscriptionId '<subscription-id>' -ResourceGroupName '<resource-group>'
```

The script uploads only the two manifest files, downloads them to verify their SHA-256 hashes, and preserves other blobs in the container.

## GitHub Actions

Use a fork or copy of this repository. Connect it to your Azure tenant using [Azure's GitHub Actions OIDC setup guide](https://learn.microsoft.com/en-us/azure/developer/github/connect-from-azure), following the connection inputs in the [deployment workflow](../.github/workflows/deploy.yml). Scope its Azure permissions to the target resource group as described above.

Then open **Actions → Deploy demo → Run workflow**. Choose **WhatIf** to review the changes, then **Deploy** to create the resources and upload the PDFs. Deployment runs manually; the separate validation workflow runs on pushes and pull requests.
