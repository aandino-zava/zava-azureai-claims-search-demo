#Requires -Version 7.2
[CmdletBinding()]
param(
    [Parameter(Mandatory)][guid]$SubscriptionId,
    [Parameter(Mandatory)][string]$ResourceGroupName,
    [string]$ConfigurationPath = 'config/demo.json'
)
. (Join-Path $PSScriptRoot 'Common.ps1')
$config = Get-DemoConfiguration -Path $ConfigurationPath
$files = @(Get-ClaimsFiles)
$storage = Invoke-AzJson -Arguments @('storage', 'account', 'show', '--name', $config.storageAccountName, '--resource-group', $ResourceGroupName, '--subscription', "$SubscriptionId")
Assert-TargetOwnership -Resources @($storage) -Configuration $config
if ($storage.tags.managedBy -ne $script:OwnershipTag) { throw 'Upload target is not owned by this package.' }
$verificationDirectory = Join-Path ([IO.Path]::GetTempPath()) ('zava-claims-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $verificationDirectory | Out-Null
try {
    foreach ($file in $files) {
        for ($attempt = 1; $attempt -le 6; $attempt++) {
            try {
                Invoke-Az -Arguments @('storage', 'blob', 'upload', '--account-name', $config.storageAccountName, '--container-name', $config.containerName, '--name', $file.FileName, '--file', $file.Path, '--auth-mode', 'login', '--subscription', "$SubscriptionId", '--content-type', 'application/pdf', '--overwrite', 'true', '--no-progress', '--output', 'none') | Out-Null
                break
            } catch {
                if ($attempt -eq 6) { throw }
                Write-Host "Storage upload not ready; retry $attempt of 6 in five seconds."
                Start-Sleep -Seconds 5
            }
        }
        $downloadPath = Join-Path $verificationDirectory $file.FileName
        Invoke-Az -Arguments @('storage', 'blob', 'download', '--account-name', $config.storageAccountName, '--container-name', $config.containerName, '--name', $file.FileName, '--file', $downloadPath, '--auth-mode', 'login', '--subscription', "$SubscriptionId", '--no-progress', '--output', 'none') | Out-Null
        if ((Get-FileHash -LiteralPath $downloadPath -Algorithm SHA256).Hash.ToLowerInvariant() -cne $file.Sha256) { throw "Uploaded content differs: $($file.FileName)." }
        Write-Host "Uploaded and SHA-256 verified: $($file.FileName)"
    }
} finally {
    # Delete only the two known files from the unique directory created above.
    foreach ($file in $files) {
        $temporaryFile = Join-Path $verificationDirectory $file.FileName
        if (Test-Path -LiteralPath $temporaryFile) { Remove-Item -LiteralPath $temporaryFile -Force }
    }
    Remove-Item -LiteralPath $verificationDirectory
}
