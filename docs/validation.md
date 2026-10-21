# Validation

## Package checks

Run from PowerShell:

```powershell
./scripts/Test-Package.ps1
./tests/Test-Guards.ps1
./tests/Test-KnowledgeSource.ps1
```

The checks compile Bicep, validate PowerShell syntax, match configuration fields to template parameters, and check the declared services, project, two containers, two model deployments, and Search access grants. Both PDFs are checked against their sizes, SHA-256 hashes, and PDF headers.

Safeguard tests check that unowned resources, implicit region changes, and altered PDF contents are rejected. The **Validate package** GitHub Actions workflow runs the same checks.

Knowledge source tests check parameter overrides, model and storage references, extraction settings, and the daily schedule. A simulated REST boundary checks conditional creation, ETag updates, bounded permission retries, and readback failures. These tests do not call Azure.

## Deployment checks

Run the deployment script in **Validate** mode to check ARM provider validation in your target subscription. Use **WhatIf** to inspect the proposed changes before deployment.

After **Deploy**, the script requires a successful ARM deployment, compares each uploaded PDF's SHA-256 hash with its local file, and reads back the knowledge source definition. ARM previews do not validate the Search REST operation. Compilation, simulated REST tests, and previews alone do not establish successful live ingestion.

## Acceptance

In your Azure tenant, confirm:

1. The configured Search service and Foundry resource exist in the selected region.
2. Foundry contains the configured project and both model deployments.
3. Storage contains both configured private containers: `claims-docs` and `claims-image-outputs` by default.
4. The document container contains the two manifest files, and both upload hash checks passed.
5. Search contains the configured blob knowledge source, with the expected document container, models, and daily schedule.
6. Check the generated indexer's ingestion result separately. A saved knowledge source definition does not establish that document processing succeeded.

The image-output container remains empty until an image-export projection or asset-store binding is configured.

Record the code revision, workflow run or command used, and the observed result for your deployment. Application behavior is outside this package's scope.
