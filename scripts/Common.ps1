# Shared configuration, file integrity, and Azure CLI handling.
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false
$script:RepositoryRoot = Split-Path $PSScriptRoot -Parent
$script:OwnershipTag = 'zava-azureai-claims-search-demo'

function Invoke-Az {
    param([Parameter(Mandatory)][string[]]$Arguments)
    $result = & az @Arguments --only-show-errors
    if ($LASTEXITCODE -ne 0) { throw "Azure CLI failed: $($Arguments[0]) $($Arguments[1])." }
    return $result
}

function Invoke-AzJson {
    param([Parameter(Mandatory)][string[]]$Arguments)
    $result = Invoke-Az -Arguments ($Arguments + @('--output', 'json'))
    return ($result | Out-String | ConvertFrom-Json -AsHashtable)
}

function Get-DemoConfiguration {
    param([string]$Path = 'config/demo.json')
    if (-not [IO.Path]::IsPathRooted($Path)) { $Path = Join-Path $script:RepositoryRoot $Path }
    $config = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json -AsHashtable
    $patterns = [ordered]@{
        location = '^[a-z][a-z0-9]+$'
        searchServiceName = '^(?=.{2,60}$)[a-z0-9]+(-[a-z0-9]+)*$'
        foundryName = '^[a-z0-9][a-z0-9-]{0,62}[a-z0-9]$'
        projectName = '^[a-zA-Z0-9][a-zA-Z0-9_.-]{1,63}$'
        storageAccountName = '^[a-z0-9]{3,24}$'
        containerName = '^(?=.{3,63}$)[a-z0-9]+(-[a-z0-9]+)*$'
        imageOutputContainerName = '^(?=.{3,63}$)[a-z0-9]+(-[a-z0-9]+)*$'
        knowledgeSourceName = '^(?=.{2,100}$)[a-z0-9]+(-[a-z0-9]+)*$'
    }
    if ($config.Count -ne ($patterns.Count + 2)) { throw 'Configuration must contain the documented resource settings and two model deployments.' }
    foreach ($key in $patterns.Keys) {
        if (-not $config.ContainsKey($key) -or $config[$key] -isnot [string] -or $config[$key] -cnotmatch $patterns[$key]) {
            throw "Invalid or missing configuration parameter: $key."
        }
    }
    foreach ($key in @('embeddingDeployment', 'chatDeployment')) {
        if (-not $config.ContainsKey($key) -or $config[$key] -isnot [hashtable] -or $config[$key].Count -ne 5) { throw "Invalid model deployment: $key." }
        foreach ($field in @('name', 'modelName', 'modelVersion', 'sku')) {
            if ($config[$key][$field] -isnot [string] -or $config[$key][$field] -cnotmatch '^[A-Za-z0-9][A-Za-z0-9_.-]{0,99}$') { throw "Invalid $key.$field." }
        }
        if ($config[$key]['capacity'] -isnot [long] -and $config[$key]['capacity'] -isnot [int]) { throw "Invalid $key.capacity." }
        if ($config[$key]['capacity'] -lt 1) { throw "Invalid $key.capacity." }
    }
    if ($config.containerName -eq $config.imageOutputContainerName) { throw 'The document and image-output containers must have different names.' }
    if ($config.embeddingDeployment.name -eq $config.chatDeployment.name) { throw 'The two model deployments must have different names.' }
    return $config
}

function Get-ClaimsFiles {
    $directory = Join-Path $script:RepositoryRoot 'data/claims-docs'
    $manifest = @(Get-Content -LiteralPath (Join-Path $script:RepositoryRoot 'data/manifest.json') -Raw | ConvertFrom-Json)
    if ($manifest.Count -ne 2) { throw 'The claims manifest must contain exactly two files.' }
    $names = @($manifest | ForEach-Object { $_.fileName })
    if (@($names | Select-Object -Unique).Count -ne 2) { throw 'Duplicate claims filenames.' }
    $actualNames = @(Get-ChildItem -LiteralPath $directory -File | ForEach-Object { $_.Name })
    if (@(Compare-Object $names $actualNames).Count -ne 0) { throw 'The claims directory must match the two-file manifest.' }
    foreach ($entry in $manifest) {
        if ($entry.fileName -notmatch '^[A-Za-z0-9_.-]+\.pdf$') { throw 'Invalid claims filename.' }
        $file = Get-Item -LiteralPath (Join-Path $directory $entry.fileName)
        $hash = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
        if ($file.Length -ne $entry.sizeBytes -or $hash -cne $entry.sha256) { throw "Integrity check failed: $($entry.fileName)." }
        $header = [IO.File]::ReadAllBytes($file.FullName)
        if ([Text.Encoding]::ASCII.GetString($header, 0, 5) -ne '%PDF-') { throw "Invalid PDF header: $($entry.fileName)." }
        [pscustomobject]@{ FileName = $entry.fileName; Path = $file.FullName; Sha256 = $hash }
    }
}

function Assert-TargetOwnership {
    param([object[]]$Resources, [hashtable]$Configuration)
    $targets = @{
        'Microsoft.Search/searchServices' = $Configuration.searchServiceName
        'Microsoft.CognitiveServices/accounts' = $Configuration.foundryName
        'Microsoft.Storage/storageAccounts' = $Configuration.storageAccountName
    }
    foreach ($resource in $Resources) {
        if ($targets.ContainsKey($resource.type) -and $targets[$resource.type] -eq $resource.name) {
            $resourceTags = $resource['tags']
            if (-not $resourceTags -or $resourceTags['managedBy'] -ne $script:OwnershipTag) {
                throw "Refusing to change existing resource '$($resource.name)': it is not owned by this package. Choose a separate target and available names."
            }
            if (($resource.location -replace ' ', '') -ine $Configuration.location) { throw "Existing resource '$($resource.name)' is in a different region." }
        }
    }
}

function Write-ArmParameters {
    param([hashtable]$Configuration)
    $buildDirectory = Join-Path $script:RepositoryRoot '.build'
    New-Item -ItemType Directory -Path $buildDirectory -Force | Out-Null
    $parameters = [ordered]@{}
    foreach ($key in $Configuration.Keys) { $parameters[$key] = @{ value = $Configuration[$key] } }
    $path = Join-Path $buildDirectory 'demo.parameters.json'
    @{ '$schema' = 'https://schema.management.azure.com/schemas/2019-04-01/deploymentParameters.json#'; contentVersion = '1.0.0.0'; parameters = $parameters } |
        ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $path -Encoding utf8
    return $path
}

function New-KnowledgeSourceDefinition {
    param([hashtable]$Configuration, [guid]$SubscriptionId, [string]$ResourceGroupName)
    $modelEndpoint = 'https://' + $Configuration.foundryName + '.openai.azure.com'
    $storageId = "/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroupName/providers/Microsoft.Storage/storageAccounts/$($Configuration.storageAccountName)"
    return @{
        name = $Configuration.knowledgeSourceName
        kind = 'azureBlob'
        azureBlobParameters = @{
            connectionString = "ResourceId=$storageId;"
            containerName = $Configuration.containerName
            ingestionParameters = @{
                contentExtractionMode = 'minimal'
                disableImageVerbalization = $false
                ingestionPermissionOptions = @()
                ingestionSchedule = @{ interval = 'P1D' }
                embeddingModel = @{
                    kind = 'azureOpenAI'
                    azureOpenAIParameters = @{
                        resourceUri = $modelEndpoint
                        deploymentId = $Configuration.embeddingDeployment.name
                        modelName = $Configuration.embeddingDeployment.modelName
                    }
                }
                chatCompletionModel = @{
                    kind = 'azureOpenAI'
                    azureOpenAIParameters = @{
                        resourceUri = $modelEndpoint
                        deploymentId = $Configuration.chatDeployment.name
                        modelName = $Configuration.chatDeployment.modelName
                    }
                }
            }
        }
    }
}

function Publish-KnowledgeSourceDefinition {
    param(
        [string]$Uri,
        [hashtable]$Definition,
        [string]$AccessToken,
        [int]$RetryDelaySeconds = 10,
        [int]$MaxAttempts = 12
    )
    $headers = @{ Authorization = "Bearer $AccessToken" }
    for ($attempt = 1; $attempt -le $MaxAttempts; $attempt++) {
        try {
            $writeHeaders = $headers.Clone()
            $writeHeaders.Prefer = 'return=representation'
            try {
                $existing = Invoke-RestMethod -Method Get -Uri $Uri -Headers $headers -ErrorAction Stop
                $writeHeaders['If-Match'] = $existing.'@odata.etag'
            } catch {
                $responseProperty = $_.Exception.PSObject.Properties['Response']
                if ($responseProperty -and $responseProperty.Value -and [int]$responseProperty.Value.StatusCode -eq 404) { $writeHeaders['If-None-Match'] = '*' }
                else { throw }
            }
            Invoke-RestMethod -Method Put -Uri $Uri -Headers $writeHeaders -ContentType 'application/json' -Body ($Definition | ConvertTo-Json -Depth 20) -ErrorAction Stop | Out-Null
            $readback = Invoke-RestMethod -Method Get -Uri $Uri -Headers $headers -ErrorAction Stop
            $expected = $Definition.azureBlobParameters
            $actual = $readback.azureBlobParameters
            if ($readback.name -ne $Definition.name -or $readback.kind -ne 'azureBlob' -or $actual.containerName -ne $expected.containerName) { throw 'Knowledge source readback does not match the target.' }
            $expectedIngestion = $expected.ingestionParameters
            $actualIngestion = $actual.ingestionParameters
            if ($actualIngestion.contentExtractionMode -ne 'minimal' -or $actualIngestion.disableImageVerbalization -ne $false -or $actualIngestion.ingestionSchedule.interval -ne 'P1D') { throw 'Knowledge source ingestion settings differ after configuration.' }
            foreach ($model in @('embeddingModel', 'chatCompletionModel')) {
                foreach ($property in @('resourceUri', 'deploymentId', 'modelName')) {
                    if ($actualIngestion.$model.azureOpenAIParameters.$property -ne $expectedIngestion[$model].azureOpenAIParameters[$property]) { throw 'Knowledge source model settings differ after configuration.' }
                }
            }
            return $readback
        } catch {
            $responseProperty = $_.Exception.PSObject.Properties['Response']
            if ($responseProperty -and $responseProperty.Value -and [int]$responseProperty.Value.StatusCode -eq 403 -and $attempt -lt $MaxAttempts) {
                Write-Host "Waiting for Search access propagation; attempt $attempt of $MaxAttempts."
                Start-Sleep -Seconds $RetryDelaySeconds
                continue
            }
            throw
        }
    }
}
