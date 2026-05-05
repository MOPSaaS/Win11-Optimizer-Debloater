# StateDetector.ps1 - Reads current system state to identify already-applied optimizations.
# Returns a flat hashtable: true = already in desired state, false = needs action.
# Called in a background runspace so slow operations (Get-WindowsOptionalFeature) don't block the UI.

function Get-SystemOptimizationState {
    $s = @{}

    # --- Services ---
    foreach ($name in @('SysMain', 'DiagTrack', 'Fax', 'RemoteRegistry')) {
        try {
            $svc = Get-Service -Name $name -ErrorAction SilentlyContinue
            $s["Svc_$name"] = (-not $svc) -or ($svc.StartType -eq 'Disabled')
        } catch { $s["Svc_$name"] = $false }
    }
    try {
        $spooler = Get-Service -Name 'Spooler' -ErrorAction SilentlyContinue
        $s['Svc_Spooler'] = (-not $spooler) -or ($spooler.StartType -eq 'Disabled')
    } catch { $s['Svc_Spooler'] = $false }

    # --- Animations ---
    try {
        $vfx   = (Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects' `
                                   -Name 'VisualFXSetting' -ErrorAction SilentlyContinue).VisualFXSetting
        $trans = (Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize' `
                                   -Name 'EnableTransparency' -ErrorAction SilentlyContinue).EnableTransparency
        $s['Perf_Animations'] = ($vfx -eq 2) -and ($trans -eq 0)
    } catch { $s['Perf_Animations'] = $false }

    # --- High-performance power plan ---
    try {
        $activeScheme  = (powercfg /getactivescheme) -join ''
        $highPerfGuid  = '8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c'
        $ultimateGuid  = 'e9a42b02-d5df-448d-aa00-03f14749eb61'
        $s['Perf_HighPerf'] = ($activeScheme -match $highPerfGuid) -or ($activeScheme -match $ultimateGuid)
    } catch { $s['Perf_HighPerf'] = $false }

    # --- Startup apps (conservative: only the two entries Performance.ps1 touches) ---
    $approvedKey  = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run'
    $startupDone  = $true
    foreach ($entry in @('OneDriveSetup', 'MicrosoftEdgeAutoLaunch')) {
        try {
            if (Test-Path $approvedKey) {
                $val = (Get-ItemProperty $approvedKey -Name $entry -ErrorAction SilentlyContinue).$entry
                # First byte 3 = disabled in StartupApproved binary encoding; absent entry also counts as done
                if ($val -and $val.Length -gt 0 -and $val[0] -ne 3) { $startupDone = $false }
            }
        } catch { }
    }
    $s['Perf_StartupApps'] = $startupDone

    # --- Gaming ---
    try {
        $gbPath    = 'HKCU:\Software\Microsoft\GameBar'
        $autoMode  = (Get-ItemProperty $gbPath -Name 'AutoGameModeEnabled' -ErrorAction SilentlyContinue).AutoGameModeEnabled
        $allowMode = (Get-ItemProperty $gbPath -Name 'AllowAutoGameMode'   -ErrorAction SilentlyContinue).AllowAutoGameMode
        $s['Game_GameMode'] = ($autoMode -eq 1) -and ($allowMode -eq 1)

        $hags = (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers' `
                                  -Name 'HwSchMode' -ErrorAction SilentlyContinue).HwSchMode
        $s['Game_HAGS'] = ($hags -eq 2)

        $nexus = (Get-ItemProperty $gbPath -Name 'UseNexusForGameBarEnabled' -ErrorAction SilentlyContinue).UseNexusForGameBarEnabled
        $s['Game_DisableGameBar'] = ($nexus -eq 0)

        $dvr = (Get-ItemProperty 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\GameDVR' `
                                 -Name 'AllowGameDVR' -ErrorAction SilentlyContinue).AllowGameDVR
        $s['Game_DisableGameDVR'] = ($dvr -eq 0)

        $tcp = (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\MSMQ\Parameters' `
                                 -Name 'TCPNoDelay' -ErrorAction SilentlyContinue).TCPNoDelay
        $s['Game_TCPNoDelay'] = ($tcp -eq 1)
    } catch {
        $s['Game_GameMode'] = $false
        $s['Game_HAGS'] = $false
        $s['Game_DisableGameBar'] = $false
        $s['Game_DisableGameDVR'] = $false
        $s['Game_TCPNoDelay'] = $false
    }

    # --- Dev Tools (optional Windows features) ---
    $featureMap = @{
        'Dev_WSL'        = 'Microsoft-Windows-Subsystem-Linux'
        'Dev_VMP'        = 'VirtualMachinePlatform'
        'Dev_HyperV'     = 'Microsoft-Hyper-V-All'
        'Dev_Containers' = 'Containers'
    }
    foreach ($key in $featureMap.Keys) {
        try {
            $f = Get-WindowsOptionalFeature -Online -FeatureName $featureMap[$key] -ErrorAction Stop
            $s[$key] = ($f.State -eq 'Enabled')
        } catch { $s[$key] = $false }
    }

    # --- Privacy ---
    try {
        $s['Priv_AdvertisingId'] = (
            (Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\AdvertisingInfo' `
                              -Name 'Enabled' -ErrorAction SilentlyContinue).Enabled -eq 0
        )
        $s['Priv_Telemetry'] = (
            (Get-ItemProperty 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection' `
                              -Name 'AllowTelemetry' -ErrorAction SilentlyContinue).AllowTelemetry -eq 1
        )
        $cdm       = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'
        $consumerA = (Get-ItemProperty 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent' `
                                       -Name 'DisableWindowsConsumerFeatures' -ErrorAction SilentlyContinue).DisableWindowsConsumerFeatures
        $consumerB = (Get-ItemProperty $cdm -Name 'SilentInstalledAppsEnabled'    -ErrorAction SilentlyContinue).SilentInstalledAppsEnabled
        $consumerC = (Get-ItemProperty $cdm -Name 'SystemPaneSuggestionsEnabled'  -ErrorAction SilentlyContinue).SystemPaneSuggestionsEnabled
        $s['Priv_ConsumerFeatures'] = ($consumerA -eq 1) -and ($consumerB -eq 0) -and ($consumerC -eq 0)

        $s['Priv_StartTracking'] = (
            (Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' `
                              -Name 'Start_TrackProgs' -ErrorAction SilentlyContinue).Start_TrackProgs -eq 0
        )
        $s['Priv_BackgroundApps'] = (
            (Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\BackgroundAccessApplications' `
                              -Name 'GlobalUserDisabled' -ErrorAction SilentlyContinue).GlobalUserDisabled -eq 1
        )
        $s['Priv_DeliveryOpt'] = (
            (Get-ItemProperty 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DeliveryOptimization' `
                              -Name 'DODownloadMode' -ErrorAction SilentlyContinue).DODownloadMode -eq 0
        )
        
        $taskCore = Get-ScheduledTask -TaskName 'MicrosoftEdgeUpdateTaskMachineCore' -ErrorAction SilentlyContinue
        $taskUA = Get-ScheduledTask -TaskName 'MicrosoftEdgeUpdateTaskMachineUA' -ErrorAction SilentlyContinue
        $s['Priv_EdgeTelemetry'] = (($null -eq $taskCore -or $taskCore.State -eq 'Disabled') -and 
                                    ($null -eq $taskUA -or $taskUA.State -eq 'Disabled'))
    } catch {
        $s['Priv_AdvertisingId'] = $false
        $s['Priv_Telemetry'] = $false
        $s['Priv_ConsumerFeatures'] = $false
        $s['Priv_StartTracking'] = $false
        $s['Priv_BackgroundApps'] = $false
        $s['Priv_DeliveryOpt'] = $false
        $s['Priv_EdgeTelemetry'] = $false
    }

    # --- Debloat: true = package already removed (desired state), false = still installed ---
    $pkgChecks = [ordered]@{
        'Debloat_Teams'     = @('MicrosoftTeams', 'MSTeams')
        'Debloat_Clipchamp' = @('Clipchamp.Clipchamp')
        'Debloat_Weather'   = @('Microsoft.BingWeather')
        'Debloat_News'      = @('Microsoft.BingNews')
        'Debloat_Tips'      = @('Microsoft.Getstarted')
        'Debloat_GetHelp'   = @('Microsoft.GetHelp')
        'Debloat_Maps'      = @('Microsoft.WindowsMaps')
        'Debloat_People'    = @('Microsoft.People')
        'Debloat_MoviesTV'  = @('Microsoft.ZuneVideo')
        'Debloat_Cortana'   = @('Microsoft.549981C3F5F10')
        'Debloat_Xbox'      = @('Microsoft.XboxApp','Microsoft.GamingApp','Microsoft.XboxGameOverlay','Microsoft.XboxSpeechToTextOverlay')
    }
    foreach ($key in $pkgChecks.Keys) {
        try {
            $found = $false
            foreach ($name in $pkgChecks[$key]) {
                if (Get-AppxPackage -Name $name -ErrorAction SilentlyContinue) { $found = $true; break }
            }
            $s[$key] = -not $found
        } catch { $s[$key] = $false }
    }

    try {
        $odSys = "$env:SystemRoot\SysWOW64\OneDriveSetup.exe"
        $odApp = "$env:LOCALAPPDATA\Microsoft\OneDrive\OneDrive.exe"
        $odProg = "$env:ProgramFiles\Microsoft OneDrive\OneDrive.exe"
        $s['Debloat_OneDrive'] = (-not (Test-Path $odSys)) -and (-not (Test-Path $odApp)) -and (-not (Test-Path $odProg))
    } catch { $s['Debloat_OneDrive'] = $false }

    return $s
}
