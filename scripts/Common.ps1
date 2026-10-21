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
    }
    if ($config.Count -ne $patterns.Count) { throw 'Configuration must contain exactly the six documented parameters.' }
    foreach ($key in $patterns.Keys) {
        if (-not $config.ContainsKey($key) -or $config[$key] -isnot [string] -or $config[$key] -cnotmatch $patterns[$key]) {
            throw "Invalid or missing configuration parameter: $key."
        }
    }
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
