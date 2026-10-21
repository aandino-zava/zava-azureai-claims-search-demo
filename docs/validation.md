# Validation

## Package checks

Run from PowerShell:

```powershell
./scripts/Test-Package.ps1
./tests/Test-Guards.ps1
```

The checks compile Bicep, validate PowerShell syntax, match configuration fields to template parameters, and confirm the template contains only the three services, project, and container. Both PDFs are checked against their sizes, SHA-256 hashes, and PDF headers.

Safeguard tests check that unowned resources, implicit region changes, and altered PDF contents are rejected. The **Validate package** GitHub Actions workflow runs the same checks.

## Deployment checks

Run the deployment script in **Validate** mode to check ARM provider validation in your target subscription. Use **WhatIf** to inspect the proposed changes before deployment.

After **Deploy**, the script requires a successful ARM deployment and compares each uploaded PDF's SHA-256 hash with its local file. Compilation and preview checks alone do not establish a successful deployment.

## Acceptance

In your Azure tenant, confirm:

1. The configured Search service and Foundry resource exist in the selected region.
2. Foundry contains the configured project.
3. The storage account contains the private `claims-docs` container, or the container name you selected.
4. The container contains the two manifest files, and both upload hash checks passed.

Record the code revision, workflow run or command used, and the observed result for your deployment. Application behavior is outside this package's scope.
