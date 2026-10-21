#Requires -Version 7.2
[CmdletBinding()]
param([string]$ConfigurationPath = 'config/demo.json')
. (Join-Path $PSScriptRoot 'Common.ps1')

$config = Get-DemoConfiguration -Path $ConfigurationPath
$files = @(Get-ClaimsFiles)
$parametersPath = Write-ArmParameters -Configuration $config
foreach ($file in Get-ChildItem -LiteralPath $PSScriptRoot -Filter '*.ps1' -File) {
    $tokens = $null
    $parseErrors = $null
    [Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref]$tokens, [ref]$parseErrors) | Out-Null
    if ($parseErrors.Count -gt 0) { throw "PowerShell syntax error in $($file.Name): $parseErrors" }
}
$templatePath = Join-Path $script:RepositoryRoot '.build/main.json'
Invoke-Az -Arguments @('bicep', 'build', '--file', (Join-Path $script:RepositoryRoot 'infra/main.bicep'), '--outfile', $templatePath) | Out-Null
$template = Get-Content -LiteralPath $templatePath -Raw | ConvertFrom-Json
$resources = if ($template.resources -is [array]) { @($template.resources) } else { @($template.resources.PSObject.Properties | ForEach-Object { $_.Value }) }
$expectedTypes = @(
    'Microsoft.Search/searchServices',
    'Microsoft.CognitiveServices/accounts',
    'Microsoft.CognitiveServices/accounts/projects',
    'Microsoft.Storage/storageAccounts',
    'Microsoft.Storage/storageAccounts/blobServices/containers',
    'Microsoft.Storage/storageAccounts/blobServices/containers',
    'Microsoft.CognitiveServices/accounts/deployments',
    'Microsoft.CognitiveServices/accounts/deployments',
    'Microsoft.Authorization/roleAssignments',
    'Microsoft.Authorization/roleAssignments'
)
if ($resources.Count -ne 10 -or @(Compare-Object $expectedTypes @($resources.type)).Count -gt 0) {
    throw 'Compiled template must contain the services, project, two containers, two model deployments, and two Search access grants.'
}
if (@(Compare-Object @($config.Keys) @($template.parameters.PSObject.Properties.Name)).Count -gt 0) {
    throw 'Configuration and Bicep parameter names differ.'
}
Write-Host "Package checks passed: ten resource declarations; $($files.Count) verified PDFs; PowerShell syntax; Bicep compilation."
Write-Host "Generated parameters: $parametersPath"
