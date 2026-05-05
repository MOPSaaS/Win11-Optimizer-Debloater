# Gaming.ps1 - Game Mode, HAGS, Game Bar / DVR

function Apply-GamingTweaks {
    [CmdletBinding()]
    param(
        [bool] $GameMode        = $true,
        [bool] $HAGS            = $true,
        [bool] $DisableGameBar  = $true,
        [bool] $DisableGameDVR  = $true,
        [bool] $TCPNoDelay      = $true
    )

    Write-Log "=== Gaming ===" -Level Info

    if ($GameMode) {
        Set-RegistryValueSafe -Path 'HKCU:\Software\Microsoft\GameBar' -Name 'AutoGameModeEnabled' -Value 1 -Type DWord
        Set-RegistryValueSafe -Path 'HKCU:\Software\Microsoft\GameBar' -Name 'AllowAutoGameMode'  -Value 1 -Type DWord
    }

    if ($HAGS) {
        # HwSchMode = 2 -> Hardware-Accelerated GPU Scheduling enabled (driver + GPU must support it)
        Set-RegistryValueSafe -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers' -Name 'HwSchMode' -Value 2 -Type DWord
        Write-Log "HAGS toggled - reboot required for the change to take effect" -Level Info
    }

    if ($DisableGameBar) {
        Set-RegistryValueSafe -Path 'HKCU:\Software\Microsoft\GameBar' -Name 'UseNexusForGameBarEnabled' -Value 0 -Type DWord
        Set-RegistryValueSafe -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\GameDVR' -Name 'AppCaptureEnabled' -Value 0 -Type DWord
        Set-RegistryValueSafe -Path 'HKCU:\System\GameConfigStore' -Name 'GameDVR_Enabled' -Value 0 -Type DWord
    }

    if ($DisableGameDVR) {
        # Policy-level DVR disable - safe, does not affect anti-cheat
        Set-RegistryValueSafe -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\GameDVR' -Name 'AllowGameDVR' -Value 0 -Type DWord
    }

    if ($TCPNoDelay) {
        Set-RegistryValueSafe -Path 'HKLM:\SOFTWARE\Microsoft\MSMQ\Parameters' -Name 'TCPNoDelay' -Value 1 -Type DWord
        
        try {
            $interfaces = Get-Item 'HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\Interfaces\*'
            foreach ($iface in $interfaces) {
                Set-RegistryValueSafe -Path $iface.PSPath -Name 'TcpAckFrequency' -Value 1 -Type DWord
                Set-RegistryValueSafe -Path $iface.PSPath -Name 'TCPNoDelay' -Value 1 -Type DWord
            }
            Write-Log "TCPNoDelay (Nagle's Algorithm disabled) applied to all network interfaces" -Level Success
        } catch {
            Write-Log "Failed to apply TCPNoDelay to network interfaces" -Level Warning
        }
    }
}
