#Requires -Version 7.2
[CmdletBinding()]
param()
. (Join-Path (Split-Path $PSScriptRoot -Parent) 'scripts/Common.ps1')

$config = Get-DemoConfiguration
$override = $config | ConvertTo-Json -Depth 20 | ConvertFrom-Json -AsHashtable
$override.foundryName = 'foundry-example'
$override.storageAccountName = 'stexampleclaims'
$override.containerName = 'example-documents'
$override.knowledgeSourceName = 'example-knowledge'
$override.embeddingDeployment.name = 'example-embedding'
$override.chatDeployment.name = 'example-chat'
$definition = New-KnowledgeSourceDefinition -Configuration $override -SubscriptionId '11111111-1111-1111-1111-111111111111' -ResourceGroupName 'rg-example'
$blob = $definition.azureBlobParameters
$ingestion = $blob.ingestionParameters
if ($definition.name -ne 'example-knowledge' -or $blob.containerName -ne 'example-documents' -or $blob.connectionString -ne 'ResourceId=/subscriptions/11111111-1111-1111-1111-111111111111/resourceGroups/rg-example/providers/Microsoft.Storage/storageAccounts/stexampleclaims;') { throw 'Storage or knowledge-source overrides were lost.' }
foreach ($model in @('embeddingModel', 'chatCompletionModel')) {
    if ($ingestion[$model].azureOpenAIParameters.resourceUri -ne 'https://foundry-example.openai.azure.com') { throw 'Foundry endpoint override was lost.' }
}
if ($ingestion.embeddingModel.azureOpenAIParameters.deploymentId -ne 'example-embedding' -or $ingestion.chatCompletionModel.azureOpenAIParameters.deploymentId -ne 'example-chat') { throw 'Model deployment overrides were lost.' }
if ($ingestion.contentExtractionMode -ne 'minimal' -or $ingestion.disableImageVerbalization -ne $false -or $ingestion.ingestionSchedule.interval -ne 'P1D') { throw 'Ingestion contract differs.' }
if ($definition.ContainsKey('createdResources') -or $blob.ContainsKey('createdResources')) { throw 'Generated resource names must not be sent in a create request.' }

class MockSearchHttpException : System.Exception {
    [object]$Response
    MockSearchHttpException([int]$status) : base("HTTP $status") { $this.Response = [pscustomobject]@{ StatusCode = $status } }
}

# Simulate the REST boundary; these tests never call Azure.
function Invoke-RestMethod {
    [CmdletBinding()]
    param([string]$Method, [string]$Uri, [hashtable]$Headers, [string]$ContentType, [string]$Body)
    if ($Method -eq 'Put') {
        $script:writeCount++
        $script:lastHeaders = $Headers
        $script:lastBody = $Body | ConvertFrom-Json -AsHashtable
        if ($script:scenario -eq 'concurrent-change') { throw [MockSearchHttpException]::new(412) }
        return $script:response
    }
    $script:getCount++
    if ($script:scenario -eq 'retry' -and $script:getCount -eq 1) { throw [MockSearchHttpException]::new(403) }
    if ($script:scenario -eq 'denied') { throw [MockSearchHttpException]::new(403) }
    if (($script:scenario -eq 'create' -and $script:getCount -eq 1) -or ($script:scenario -eq 'retry' -and $script:getCount -eq 2)) { throw [MockSearchHttpException]::new(404) }
    if ($script:scenario -eq 'mismatch' -and $script:writeCount -gt 0) {
        $copy = $script:response | ConvertTo-Json -Depth 20 | ConvertFrom-Json
        $copy.azureBlobParameters.containerName = 'unexpected-container'
        return $copy
    }
    return $script:response
}

foreach ($case in @('create', 'update', 'retry', 'mismatch', 'concurrent-change', 'denied')) {
    $script:scenario = $case
    $script:writeCount = 0
    $script:getCount = 0
    $script:lastHeaders = @{}
    $script:lastBody = @{}
    $script:response = $definition | ConvertTo-Json -Depth 20 | ConvertFrom-Json
    $script:response | Add-Member -NotePropertyName '@odata.etag' -NotePropertyValue '"version-1"'
    $failed = $false
    try {
        Publish-KnowledgeSourceDefinition -Uri 'https://search-example.search.windows.net/knowledgesources/example-knowledge' -Definition $definition -AccessToken 'test-token' -RetryDelaySeconds 0 -MaxAttempts 2 | Out-Null
    } catch {
        if ($case -notin @('mismatch', 'concurrent-change', 'denied')) { throw }
        $failed = $true
    }
    if ($case -in @('mismatch', 'concurrent-change', 'denied') -and -not $failed) { throw "Expected $case to fail." }
    if ($case -eq 'denied') {
        if ($script:writeCount -ne 0 -or $script:getCount -ne 2) { throw 'Permission retries were not bounded.' }
        continue
    }
    if ($script:writeCount -ne 1) { throw "Unexpected number of writes for $case." }
    if ($case -in @('create', 'retry') -and $script:lastHeaders['If-None-Match'] -ne '*') { throw 'Create must be conditional.' }
    if ($case -in @('update', 'concurrent-change') -and $script:lastHeaders['If-Match'] -ne '"version-1"') { throw 'Update must use the observed ETag.' }
    if (($script:lastBody | ConvertTo-Json -Depth 20 -Compress) -ne ($definition | ConvertTo-Json -Depth 20 -Compress)) { throw 'REST body differs from the portable definition.' }
}
Write-Host 'Knowledge source checks passed: parameter overrides, ingestion settings, conditional writes, bounded retries, and readback failures.'
