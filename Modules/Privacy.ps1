# Privacy.ps1 - Non-destructive privacy settings (Defender / Update untouched)

function Apply-PrivacySettings {
    [CmdletBinding()]
    param(
        [bool] $AdvertisingId        = $true,
        [bool] $Telemetry            = $true,
        [bool] $ConsumerFeatures     = $true,
        [bool] $StartTracking        = $true,
        [bool] $BackgroundApps       = $true,
        [bool] $DeliveryOpt          = $true,
        [bool] $EdgeTelemetry        = $true
    )

    Write-Log "=== Privacy ===" -Level Info

    if ($AdvertisingId) {
        Set-RegistryValueSafe -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\AdvertisingInfo' -Name 'Enabled' -Value 0 -Type DWord
    }

    if ($Telemetry) {
        # AllowTelemetry = 1 (Required) - lowest setting honored on Pro/Home without breaking SmartScreen / Defender intel.
        # 0 (Security) only applies to Enterprise/Education and would reduce Defender cloud protection on Pro/Home.
        Set-RegistryValueSafe -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection' -Name 'AllowTelemetry' -Value 1 -Type DWord
    }

    if ($ConsumerFeatures) {
        Set-RegistryValueSafe -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent' -Name 'DisableWindowsConsumerFeatures' -Value 1 -Type DWord
        Set-RegistryValueSafe -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' -Name 'SilentInstalledAppsEnabled' -Value 0 -Type DWord
        Set-RegistryValueSafe -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' -Name 'SystemPaneSuggestionsEnabled' -Value 0 -Type DWord
    }

    if ($StartTracking) {
        Set-RegistryValueSafe -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' -Name 'Start_TrackProgs' -Value 0 -Type DWord
    }

    if ($BackgroundApps) {
        Set-RegistryValueSafe -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\BackgroundAccessApplications' -Name 'GlobalUserDisabled' -Value 1 -Type DWord
    }

    if ($DeliveryOpt) {
        Set-RegistryValueSafe -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DeliveryOptimization' -Name 'DODownloadMode' -Value 0 -Type DWord
    }

    if ($EdgeTelemetry) {
        try {
            $t1 = Get-ScheduledTask -TaskName 'MicrosoftEdgeUpdateTaskMachineCore' -ErrorAction SilentlyContinue
            $t2 = Get-ScheduledTask -TaskName 'MicrosoftEdgeUpdateTaskMachineUA' -ErrorAction SilentlyContinue
            if ($t1 -and $t1.State -ne 'Disabled') { Disable-ScheduledTask -TaskName 'MicrosoftEdgeUpdateTaskMachineCore' -ErrorAction Stop | Out-Null }
            if ($t2 -and $t2.State -ne 'Disabled') { Disable-ScheduledTask -TaskName 'MicrosoftEdgeUpdateTaskMachineUA' -ErrorAction Stop | Out-Null }
            Write-Log "Disabled Edge background telemetry and update tasks" -Level Success
        } catch {
            Write-Log "Failed to disable Edge tasks: $($_.Exception.Message)" -Level Warning
        }
    }
}
