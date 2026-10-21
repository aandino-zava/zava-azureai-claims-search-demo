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
$expectedTypes = @(
    'Microsoft.Search/searchServices',
    'Microsoft.CognitiveServices/accounts',
    'Microsoft.CognitiveServices/accounts/projects',
    'Microsoft.Storage/storageAccounts',
    'Microsoft.Storage/storageAccounts/blobServices/containers'
)
if (@($template.resources).Count -ne 5 -or @(Compare-Object $expectedTypes @($template.resources.type)).Count -gt 0) {
    throw 'Compiled template must contain only the three services, the project, and the container.'
}
if (@(Compare-Object @($config.Keys) @($template.parameters.PSObject.Properties.Name)).Count -gt 0) {
    throw 'Configuration and Bicep parameter names differ.'
}
Write-Host "Package checks passed: five resource declarations; $($files.Count) verified PDFs; PowerShell syntax; Bicep compilation."
Write-Host "Generated parameters: $parametersPath"
