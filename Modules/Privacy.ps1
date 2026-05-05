# Privacy.ps1 - Non-destructive privacy settings (Defender / Update untouched)

function Apply-PrivacySettings {
    [CmdletBinding()]
    param(
        [bool] $AdvertisingId        = $true,
        [bool] $Telemetry            = $true,
        [bool] $ConsumerFeatures     = $true,
        [bool] $StartTracking        = $true,
        [bool] $BackgroundApps       = $true
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
}
