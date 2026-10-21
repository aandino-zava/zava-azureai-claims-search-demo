#Requires -Version 7.2
[CmdletBinding()]
param(
    [Parameter(Mandatory)][guid]$SubscriptionId,
    [Parameter(Mandatory)][ValidatePattern('^[A-Za-z0-9_.()-]{1,90}$')][string]$ResourceGroupName,
    [string]$ConfigurationPath = 'config/demo.json',
    [ValidateSet('Validate', 'WhatIf', 'Deploy')][string]$Mode = 'WhatIf'
)
. (Join-Path $PSScriptRoot 'Common.ps1')
& (Join-Path $PSScriptRoot 'Test-Package.ps1') -ConfigurationPath $ConfigurationPath
$config = Get-DemoConfiguration -Path $ConfigurationPath
$parametersPath = Write-ArmParameters -Configuration $config
$account = Invoke-AzJson -Arguments @('account', 'show', '--subscription', "$SubscriptionId")
if ($account.id -ine "$SubscriptionId" -or $account.state -ne 'Enabled') { throw 'Target subscription is not enabled or does not match.' }
Write-Host 'Checking the selected deployment target.'
Invoke-Az -Arguments @('group', 'show', '--name', $ResourceGroupName, '--subscription', "$SubscriptionId", '--output', 'none') | Out-Null
$resources = @(Invoke-AzJson -Arguments @('resource', 'list', '--resource-group', $ResourceGroupName, '--subscription', "$SubscriptionId"))
Assert-TargetOwnership -Resources $resources -Configuration $config

# Provider validation evaluates the selected names, region, SKU, policy, and permissions.
$deploymentArguments = @('--subscription', "$SubscriptionId", '--resource-group', $ResourceGroupName, '--name', 'zava-claims-demo', '--template-file', (Join-Path $script:RepositoryRoot '.build/main.json'), '--parameters', "@$parametersPath")
Invoke-Az -Arguments (@('deployment', 'group', 'validate') + $deploymentArguments + @('--validation-level', 'Provider', '--output', 'none')) | Out-Null
if ($Mode -eq 'Validate') { Write-Host 'ARM validation passed. No resources deployed.'; return }
Invoke-Az -Arguments (@('deployment', 'group', 'what-if') + $deploymentArguments) | Out-Host
if ($Mode -eq 'WhatIf') { return }
$deployment = Invoke-AzJson -Arguments (@('deployment', 'group', 'create') + $deploymentArguments)
if ($deployment.properties.provisioningState -ne 'Succeeded') { throw 'Deployment did not report Succeeded.' }
& (Join-Path $PSScriptRoot 'Upload-Claims.ps1') -SubscriptionId $SubscriptionId -ResourceGroupName $ResourceGroupName -ConfigurationPath $ConfigurationPath
Write-Host 'Deployment complete: services, project, container, and two verified PDF uploads.'
