#Requires -Version 7.2
[CmdletBinding()]
param()
. (Join-Path (Split-Path $PSScriptRoot -Parent) 'scripts/Common.ps1')
$config = Get-DemoConfiguration
$untagged = @{
    type = 'Microsoft.Storage/storageAccounts'
    name = $config.storageAccountName
    location = $config.location
    tags = @{}
}
$rejected = $false
try { Assert-TargetOwnership -Resources @($untagged) -Configuration $config }
catch {
    if ($_.Exception.Message -notlike '*Refusing to change existing resource*') { throw }
    $rejected = $true
}
if (-not $rejected) { throw 'An unowned existing target was accepted.' }
$owned = $untagged.Clone()
$owned.tags = @{ managedBy = 'zava-azureai-claims-search-demo' }
foreach ($region in @($config.location, 'westus2') | Select-Object -Unique) {
    $regionConfiguration = $config.Clone()
    $regionConfiguration.location = $region
    $owned.location = $region
    Assert-TargetOwnership -Resources @($owned) -Configuration $regionConfiguration
    $owned.location = if ($region -ieq 'westus2') { 'eastus' } else { 'westus2' }
    $rejected = $false
    try { Assert-TargetOwnership -Resources @($owned) -Configuration $regionConfiguration }
    catch {
        if ($_.Exception.Message -notlike '*different region*') { throw }
        $rejected = $true
    }
    if (-not $rejected) { throw 'An implicit region change was accepted.' }
}

$originalRoot = $script:RepositoryRoot
$fixture = Join-Path $originalRoot ('.build/guard-fixture-' + [guid]::NewGuid().ToString('N'))
$fixtureData = Join-Path $fixture 'data/claims-docs'
New-Item -ItemType Directory -Path $fixtureData -Force | Out-Null
$files = @(Get-ClaimsFiles)
try {
    Copy-Item -LiteralPath (Join-Path $originalRoot 'data/manifest.json') -Destination (Join-Path $fixture 'data/manifest.json')
    foreach ($file in $files) { Copy-Item -LiteralPath $file.Path -Destination (Join-Path $fixtureData $file.FileName) }
    $script:RepositoryRoot = $fixture
    if (@(Get-ClaimsFiles).Count -ne 2) { throw 'Valid PDF fixture was not accepted.' }
    Add-Content -LiteralPath (Join-Path $fixtureData $files[0].FileName) -Value '% tampered'
    $rejected = $false
    try { Get-ClaimsFiles | Out-Null }
    catch {
        if ($_.Exception.Message -notlike '*Integrity check failed*') { throw }
        $rejected = $true
    }
    if (-not $rejected) { throw 'Changed PDF bytes were accepted.' }
} finally {
    $script:RepositoryRoot = $originalRoot
    foreach ($file in $files) { Remove-Item -LiteralPath (Join-Path $fixtureData $file.FileName) -ErrorAction SilentlyContinue }
    Remove-Item -LiteralPath (Join-Path $fixture 'data/manifest.json') -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $fixtureData
    Remove-Item -LiteralPath (Join-Path $fixture 'data')
    Remove-Item -LiteralPath $fixture
}
Write-Host 'Guard checks passed: existing-resource ownership, region preservation, and PDF tampering.'
