#Requires -Version 7.2
[CmdletBinding()]
param(
    [Parameter(Mandatory)][guid]$SubscriptionId,
    [Parameter(Mandatory)][string]$ResourceGroupName,
    [string]$ConfigurationPath = 'config/demo.json'
)
. (Join-Path $PSScriptRoot 'Common.ps1')
$config = Get-DemoConfiguration -Path $ConfigurationPath
$searchId = "/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroupName/providers/Microsoft.Search/searchServices/$($config.searchServiceName)"
$search = Invoke-AzJson -Arguments @('resource', 'show', '--ids', $searchId, '--subscription', "$SubscriptionId")
Assert-TargetOwnership -Resources @($search) -Configuration $config
$definition = New-KnowledgeSourceDefinition -Configuration $config -SubscriptionId $SubscriptionId -ResourceGroupName $ResourceGroupName
$uri = "https://$($config.searchServiceName).search.windows.net/knowledgesources('$($config.knowledgeSourceName)')?api-version=2025-11-01-preview"
$searchToken = Invoke-AzJson -Arguments @('account', 'get-access-token', '--resource', 'https://search.azure.com', '--subscription', "$SubscriptionId")
try {
    Publish-KnowledgeSourceDefinition -Uri $uri -Definition $definition -AccessToken $searchToken.accessToken | Out-Null
} finally { $searchToken = $null }
Write-Host 'Knowledge source configured and read back. Ingestion runs asynchronously on its daily schedule.'
