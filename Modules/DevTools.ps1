# DevTools.ps1 - Enable optional features required by WSL/Docker/Hyper-V.
# This module ONLY enables features. It never removes runtimes or developer dependencies.

function Apply-DevToolsTweaks {
    [CmdletBinding()]
    param(
        [bool] $WSL        = $true,
        [bool] $VMP        = $true,
        [bool] $HyperV     = $false,
        [bool] $Containers = $false
    )

    Write-Log "=== Dev Tools ===" -Level Info

    $features = @()
    if ($WSL)        { $features += 'Microsoft-Windows-Subsystem-Linux' }
    if ($VMP)        { $features += 'VirtualMachinePlatform' }
    if ($HyperV)     { $features += 'Microsoft-Hyper-V-All' }
    if ($Containers) { $features += 'Containers' }

    foreach ($feature in $features) {
        try {
            $state = Get-WindowsOptionalFeature -Online -FeatureName $feature -ErrorAction Stop
            if ($state.State -eq 'Enabled') {
                Write-Log "Already enabled: $feature" -Level Skip
                continue
            }
            Backup-Feature -Name $feature
            Enable-WindowsOptionalFeature -Online -FeatureName $feature -All -NoRestart -ErrorAction Stop | Out-Null
            Write-Log "Enabled feature: $feature (reboot required)" -Level Success
        } catch {
            Write-Log "Could not enable ${feature}: $($_.Exception.Message)" -Level Warning
        }
    }
}
