# Performance.ps1 - Service tweaks, animations, power plan, startup

function Optimize-Performance {
    [CmdletBinding()]
    param(
        [bool] $DisableSysMain     = $true,
        [bool] $DisableDiagTrack   = $true,
        [bool] $DisableFax         = $true,
        [bool] $DisableRemoteReg   = $true,
        [bool] $DisablePrintSpooler= $false,
        [bool] $DisableAnimations  = $true,
        [bool] $HighPerformance    = $true,
        [bool] $DisableStartupApps = $true
    )

    Write-Log "=== Performance ===" -Level Info

    if ($DisableSysMain)      { Disable-ServiceSafe -Name 'SysMain' }
    if ($DisableDiagTrack)    { Disable-ServiceSafe -Name 'DiagTrack' }
    if ($DisableFax)          { Disable-ServiceSafe -Name 'Fax' }
    if ($DisableRemoteReg)    { Disable-ServiceSafe -Name 'RemoteRegistry' }
    if ($DisablePrintSpooler) { Disable-ServiceSafe -Name 'Spooler' }

    if ($DisableAnimations) {
        try {
            # VisualFXSetting=2 -> Adjust for best performance (still keeps essentials available)
            Set-RegistryValueSafe -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects' -Name 'VisualFXSetting' -Value 2 -Type DWord
            # Transparency off
            Set-RegistryValueSafe -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize' -Name 'EnableTransparency' -Value 0 -Type DWord
            # Window animations + menu fade
            Set-RegistryValueSafe -Path 'HKCU:\Control Panel\Desktop\WindowMetrics' -Name 'MinAnimate' -Value '0' -Type String
            Set-RegistryValueSafe -Path 'HKCU:\Control Panel\Desktop' -Name 'MenuShowDelay' -Value '0' -Type String
        } catch { Write-Log "Animation tweak failed: $($_.Exception.Message)" -Level Warning }
    }

    if ($HighPerformance) {
        try {
            Backup-PowerPlan
            $highPerfGuid = '8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c'
            $ultimateGuid = 'e9a42b02-d5df-448d-aa00-03f14749eb61'

            $schemes = (powercfg /list) -join "`n"
            if ($schemes -notmatch $ultimateGuid) {
                $null = powercfg /duplicatescheme $ultimateGuid 2>&1
            }
            $schemes = (powercfg /list) -join "`n"

            if ($schemes -match $ultimateGuid) {
                $null = powercfg /setactive $ultimateGuid
                Write-Log "Power plan -> Ultimate Performance" -Level Success
            } elseif ($schemes -match $highPerfGuid) {
                $null = powercfg /setactive $highPerfGuid
                Write-Log "Power plan -> High Performance" -Level Success
            } else {
                Write-Log "No high-performance plan available on this SKU" -Level Warning
            }
        } catch { Write-Log "Power plan change failed: $($_.Exception.Message)" -Level Warning }
    }

    if ($DisableStartupApps) {
        # Conservative list - only entries that are commonly safe to silence.
        # Anti-cheat, Defender, GPU drivers, Windows Security are NEVER touched.
        $targets = @(
            'OneDriveSetup',         # initial OneDrive bootstrap (existing OneDrive runs unaffected)
            'MicrosoftEdgeAutoLaunch'# Edge background autolaunch
        )
        $approvedKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run'
        foreach ($name in $targets) {
            try {
                $exists = $false
                if (Test-Path $approvedKey) {
                    $exists = (Get-Item $approvedKey).GetValueNames() -contains $name
                }
                if ($exists) {
                    Backup-RegistryValue -Path $approvedKey -Name $name
                    # 0x03,0x00,... = disabled per StartupApproved encoding
                    $bytes = [byte[]](3,0,0,0,0,0,0,0,0,0,0,0)
                    Set-ItemProperty -Path $approvedKey -Name $name -Value $bytes -Type Binary
                    Write-Log "Disabled startup entry: $name" -Level Success
                }
            } catch { Write-Log "Startup tweak failed for $name : $($_.Exception.Message)" -Level Warning }
        }
    }
}
