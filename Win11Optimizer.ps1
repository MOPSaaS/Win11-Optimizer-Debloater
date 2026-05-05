# Win11Optimizer.ps1 - WPF entry point
# Loads MainWindow.xaml, wires up handlers, and dispatches work to a background runspace.

[CmdletBinding()]
param()

#--- Setup ----------------------------------------------------------------
$ErrorActionPreference = 'Stop'

# Debug log for startup
$DebugLog = Join-Path $PSScriptRoot "startup_debug.log"
"Starting Win11 Optimizer at $(Get-Date)" | Set-Content -Path $DebugLog

function Log-Debug {
    param($msg)
    "$(Get-Date -Format 'HH:mm:ss') - $msg" | Add-Content -Path $DebugLog
    Write-Host "DEBUG: $msg"
}

# Global error handler for startup crashes
trap {
    $err = "FATAL ERROR:`n$($_.Exception.Message)`n`nStack:`n$($_.ScriptStackTrace)"
    Log-Debug $err
    [System.Windows.MessageBox]::Show($err, 'Win11 Optimizer - Fatal Error', 'OK', 'Error') | Out-Null
    exit 1
}

Log-Debug "Loading assemblies..."
Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase

$Script:Root      = $PSScriptRoot
$Script:ModuleDir = Join-Path $Script:Root 'Modules'
$Script:XamlPath  = Join-Path $Script:Root 'MainWindow.xaml'

# Modules loaded in the main runspace (admin gate, backup probe, state UI updates).
# The optimize worker dot-sources the same list minus StateDetector.
# The scan worker gets its own minimal list (StateDetector only).
$Script:ModuleFiles = @(
    'Logger.ps1', 'Backup.ps1', 'Common.ps1',
    'Performance.ps1', 'Bloatware.ps1', 'Gaming.ps1',
    'Privacy.ps1', 'DevTools.ps1', 'Restore.ps1'
) | ForEach-Object { Join-Path $Script:ModuleDir $_ }

$Script:ScanModuleFiles = @('StateDetector.ps1') |
    ForEach-Object { Join-Path $Script:ModuleDir $_ }

Log-Debug "Dot-sourcing modules..."
foreach ($m in $Script:ModuleFiles) { 
    Log-Debug "  Loading $m"
    . $m 
}
Log-Debug "  Loading StateDetector.ps1"
. (Join-Path $Script:ModuleDir 'StateDetector.ps1')

#--- Admin gate -----------------------------------------------------------
if (-not (Test-IsAdmin)) {
    [System.Windows.MessageBox]::Show(
        "This optimizer requires Administrator privileges.`n`nRelaunch via Launch.bat.",
        'Win11 Optimizer', 'OK', 'Warning') | Out-Null
    return
}

#--- Load XAML ------------------------------------------------------------
Log-Debug "Loading XAML from $Script:XamlPath"
if (-not (Test-Path $Script:XamlPath)) { throw "XAML file not found: $Script:XamlPath" }

# Load XAML content. Using a more robust method that ignores BOM issues.
$xamlContent = [System.IO.File]::ReadAllText($Script:XamlPath)
[xml]$xaml = $xamlContent

Log-Debug "Parsing XAML..."
$reader = New-Object System.Xml.XmlNodeReader $xaml
$Window = [Windows.Markup.XamlReader]::Load($reader)

Log-Debug "Binding UI elements..."
$ui = @{}
$names = $xaml.SelectNodes("//*[@*[local-name()='Name']]")
foreach ($node in $names) {
    $name = $node.GetAttribute('Name','http://schemas.microsoft.com/winfx/2006/xaml')
    if ($name) { 
        $ctrl = $Window.FindName($name)
        if ($null -eq $ctrl) { 
            Log-Debug "  WARNING: Failed to bind $name" 
        } else {
            $ui[$name] = $ctrl
        }
    }
}

$ctxData = @{ Window = $Window }
if ($ui.rtbLog) { $ctxData.Box = $ui.rtbLog }
$Script:SyncUI = [hashtable]::Synchronized($ctxData)
Set-LoggerUIContext -UIContext $Script:SyncUI

#--- Shared brushes -------------------------------------------------------
$Script:BrushDone   = New-Object System.Windows.Media.SolidColorBrush(
    [System.Windows.Media.Color]::FromRgb(0x56, 0x5F, 0x89))   # dim blue-grey for already-applied items
$Script:BrushNormal = New-Object System.Windows.Media.SolidColorBrush(
    [System.Windows.Media.Color]::FromRgb(0xC0, 0xCA, 0xF5))   # Tokyo Night text colour
$Script:BrushDone.Freeze()
$Script:BrushNormal.Freeze()

#--- Optimizer runspace state ---------------------------------------------
$Script:Runspace     = $null
$Script:PowerShell   = $null
$Script:WorkerHandle = $null
$Script:IsRunning    = $false

#--- Scan runspace state --------------------------------------------------
$Script:ScanRunspace   = $null
$Script:ScanPowerShell = $null
$Script:ScanHandle     = $null
$Script:IsScan         = $false

#--- Worker entry point (optimize / restore) ------------------------------
$WorkerScript = {
    param($UIContext, $ModuleFiles, $Action, $Options)
    foreach ($m in $ModuleFiles) { . $m }
    Set-LoggerUIContext -UIContext $UIContext

    try {
        switch ($Action) {
            'Optimize' {
                $path = Start-BackupSession
                Write-Log "Backup snapshot: $path" -Level Info
                $perf = $Options.Performance; if ($perf) { Optimize-Performance @perf }
                $deb  = $Options.Debloat;     if ($deb)  { Remove-Bloatware     @deb }
                $gam  = $Options.Gaming;      if ($gam)  { Apply-GamingTweaks   @gam }
                $dev  = $Options.DevTools;    if ($dev)  { Apply-DevToolsTweaks @dev }
                $priv = $Options.Privacy;     if ($priv) { Apply-PrivacySettings @priv }
                Write-Log "All operations finished." -Level Success
                Write-Log "Reboot recommended if you toggled HAGS or optional features." -Level Info
            }
            'Restore' {
                Restore-SystemDefaults
            }
        }
    } catch {
        Write-Log "Fatal: $($_.Exception.Message)" -Level Error
    }
}

#--- Scan worker entry point ----------------------------------------------
$ScanScript = {
    param($ModuleFiles)
    try {
        foreach ($m in $ModuleFiles) { if (Test-Path $m) { . $m } }
        return Get-SystemOptimizationState
    } catch {
        return @{ Error = $_.Exception.Message }
    }
}

#--- Update checkboxes from scanned state ---------------------------------
function Update-UIFromState {
    param([hashtable] $State)

    # Map: checkbox name -> (state key, base label text)
    $map = @(
        # Debloat
        @{ CB = 'cbDebloatTeams';         Key = 'Debloat_Teams';     Text = 'Microsoft Teams (personal)' }
        @{ CB = 'cbDebloatClipchamp';     Key = 'Debloat_Clipchamp'; Text = 'Clipchamp' }
        @{ CB = 'cbDebloatWeather';       Key = 'Debloat_Weather';   Text = 'Weather' }
        @{ CB = 'cbDebloatNews';          Key = 'Debloat_News';      Text = 'News (Bing News)' }
        @{ CB = 'cbDebloatTips';          Key = 'Debloat_Tips';      Text = 'Tips / Get Started' }
        @{ CB = 'cbDebloatGetHelp';       Key = 'Debloat_GetHelp';   Text = 'Get Help' }
        @{ CB = 'cbDebloatMaps';          Key = 'Debloat_Maps';      Text = 'Maps' }
        @{ CB = 'cbDebloatPeople';        Key = 'Debloat_People';    Text = 'People' }
        @{ CB = 'cbDebloatMoviesTV';      Key = 'Debloat_MoviesTV';  Text = 'Movies & TV' }
        @{ CB = 'cbDebloatCortana';       Key = 'Debloat_Cortana';   Text = 'Cortana' }
        @{ CB = 'cbDebloatXbox';          Key = 'Debloat_Xbox';      Text = 'Xbox apps (keeps Gaming Services for anti-cheat)' }
        @{ CB = 'cbDebloatOneDrive';      Key = 'Debloat_OneDrive';  Text = 'Fully uninstall OneDrive and remove from Explorer' }
        # Performance
        @{ CB = 'cbPerfSysMain';          Key = 'Svc_SysMain';          Text = 'Disable SysMain (Superfetch) - improves SSD performance' }
        @{ CB = 'cbPerfDiagTrack';        Key = 'Svc_DiagTrack';        Text = 'Disable Connected User Experiences and Telemetry (DiagTrack)' }
        @{ CB = 'cbPerfFax';              Key = 'Svc_Fax';              Text = 'Disable Fax service' }
        @{ CB = 'cbPerfRemoteRegistry';   Key = 'Svc_RemoteRegistry';   Text = 'Disable Remote Registry' }
        @{ CB = 'cbPerfPrintSpooler';     Key = 'Svc_Spooler';          Text = "Disable Print Spooler (only if you don't print)" }
        @{ CB = 'cbPerfAnimations';       Key = 'Perf_Animations';      Text = 'Disable UI animations and transparency' }
        @{ CB = 'cbPerfHighPerf';         Key = 'Perf_HighPerf';        Text = 'Set power plan to High Performance (Ultimate if available)' }
        @{ CB = 'cbPerfStartup';          Key = 'Perf_StartupApps';     Text = 'Disable common non-essential startup apps' }
        # Gaming
        @{ CB = 'cbGameMode';             Key = 'Game_GameMode';        Text = 'Enable Game Mode' }
        @{ CB = 'cbHAGS';                 Key = 'Game_HAGS';            Text = 'Enable Hardware-Accelerated GPU Scheduling (requires reboot)' }
        @{ CB = 'cbDisableGameBar';       Key = 'Game_DisableGameBar';  Text = 'Disable Xbox Game Bar overlay' }
        @{ CB = 'cbDisableGameDVR';       Key = 'Game_DisableGameDVR';  Text = 'Disable Game DVR background recording' }
        @{ CB = 'cbGameTCPNoDelay';       Key = 'Game_TCPNoDelay';      Text = "Disable Nagle's Algorithm (TCP NoDelay) to lower network latency" }
        # Dev Tools
        @{ CB = 'cbDevWSL';               Key = 'Dev_WSL';              Text = 'Ensure WSL feature enabled' }
        @{ CB = 'cbDevVMP';               Key = 'Dev_VMP';              Text = 'Ensure Virtual Machine Platform enabled (required by WSL2 / Docker)' }
        @{ CB = 'cbDevHyperV';            Key = 'Dev_HyperV';           Text = 'Enable Hyper-V (optional - needed for Windows Sandbox / advanced VMs)' }
        @{ CB = 'cbDevContainers';        Key = 'Dev_Containers';       Text = 'Enable Containers feature' }
        # Privacy
        @{ CB = 'cbPrivAdId';             Key = 'Priv_AdvertisingId';    Text = 'Disable advertising ID' }
        @{ CB = 'cbPrivTelemetry';        Key = 'Priv_Telemetry';        Text = 'Set telemetry to minimum allowed (Security/Required)' }
        @{ CB = 'cbPrivConsumerFeatures'; Key = 'Priv_ConsumerFeatures'; Text = 'Disable Windows consumer features (suggested apps)' }
        @{ CB = 'cbPrivStartTracking';    Key = 'Priv_StartTracking';    Text = 'Disable Start menu app launch tracking' }
        @{ CB = 'cbPrivBackgroundApps';   Key = 'Priv_BackgroundApps';  Text = 'Disable background apps (current user)' }
        @{ CB = 'cbPrivacyDeliveryOpt';   Key = 'Priv_DeliveryOpt';     Text = 'Disable Windows Update Delivery Optimization (P2P uploads)' }
        @{ CB = 'cbPrivacyEdgeTelemetry'; Key = 'Priv_EdgeTelemetry';   Text = 'Disable Edge background telemetry and update tasks' }
    )

    $applied = 0
    $pending = 0
    foreach ($item in $map) {
        try {
            $cb   = $ui[$item.CB]
            if (-not $cb) { continue }
            
            $done = $false
            if ($null -ne $State -and $State.ContainsKey($item.Key)) { 
                $done = [bool]$State[$item.Key] 
            }

            if ($done) {
                $cb.Content    = "$($item.Text)  [Done]"
                $cb.Foreground = $Script:BrushDone
                $cb.IsChecked  = $false
                $applied++
            } else {
                $cb.Content    = $item.Text
                $cb.Foreground = $Script:BrushNormal
                $cb.IsChecked  = $true
                $pending++
            }
        } catch {
            Log-Debug "    ERROR updating $($item.CB): $($_.Exception.Message)"
        }
    }

    return @{ Applied = $applied; Pending = $pending }
}

#--- Invoke state scan in a background runspace ---------------------------
function Invoke-StateScan {
    if ($Script:IsRunning -or $Script:IsScan) { return }

    $Script:IsScan = $true
    if ($ui.btnRescan)     { $ui.btnRescan.IsEnabled = $false }
    if ($ui.lblScanStatus) { $ui.lblScanStatus.Text  = 'Scanning system...' }

    Log-Debug "  Creating scan runspace (MTA/NewThread)..."
    $rs = [runspacefactory]::CreateRunspace()
    $rs.ApartmentState = 'MTA'
    $rs.ThreadOptions  = 'UseNewThread'
    $rs.Open()

    Log-Debug "  Creating PowerShell object..."
    $ps = [PowerShell]::Create()
    $ps.Runspace = $rs
    $null = $ps.AddScript($ScanScript).AddArgument($Script:ScanModuleFiles)

    $Script:ScanRunspace   = $rs
    $Script:ScanPowerShell = $ps
    Log-Debug "  Invoking background scan..."
    $Script:ScanHandle     = $ps.BeginInvoke()

    Log-Debug "  Starting dispatcher timer..."
    $timer = New-Object System.Windows.Threading.DispatcherTimer
    $timer.Interval = [TimeSpan]::FromMilliseconds(250)
    $timer.Add_Tick({
        try {
            $handle = $Script:ScanHandle
            if ($null -eq $handle) { return }
            
            $done = $false
            try { $done = $handle.IsCompleted } catch { return }
            if (-not $done) { return }
            
            $this.Stop()
            Log-Debug "Background scan completed. Processing results..."
            
            $psObj = $Script:ScanPowerShell
            if ($null -eq $psObj) { 
                $Script:IsScan = $false
                if ($ui.btnRescan) { $ui.btnRescan.IsEnabled = $true }
                return 
            }
            
            Log-Debug "  Calling EndInvoke..."
            $result = $psObj.EndInvoke($handle)
            Log-Debug "  EndInvoke completed. Result count: $($result.Count)"
            if ($null -eq $result -or $result.Count -eq 0) {
                Log-Debug "  Scan returned no data."
                if ($ui.lblScanStatus) { $ui.lblScanStatus.Text = 'Scan returned no data' }
            } else {
                $state = $result[0]
                if ($null -eq $state) {
                    Log-Debug "  Scan returned null."
                } elseif ($state -is [hashtable] -and $state.ContainsKey('Error')) {
                    Log-Debug "  Scan reported error: $($state.Error)"
                } elseif ($state -isnot [hashtable]) {
                    Log-Debug "  Scan returned invalid data type: $($state.GetType().FullName)"
                } else {
                    Log-Debug "  Updating UI from state..."
                    $counts = Update-UIFromState -State $state
                    
                    if ($null -ne $counts -and $ui.lblScanStatus) {
                        $ui.lblScanStatus.Text = "$($counts.Applied) items already applied, $($counts.Pending) pending"
                    }
                    Log-Debug "  UI update complete."
                }
            }
        } catch {
            $err = $_.Exception.Message
            Log-Debug "  ERROR in scan callback: $err"
            if ($ui.lblScanStatus) { $ui.lblScanStatus.Text = 'Scan failed' }
        }
        
        # Cleanup (only reaches here if IsCompleted was true, since we return early if false)
        try { if ($Script:ScanPowerShell) { $Script:ScanPowerShell.Dispose() } } catch { }
        try { if ($Script:ScanRunspace) { $Script:ScanRunspace.Close(); $Script:ScanRunspace.Dispose() } } catch { }
        $Script:IsScan = $false
        if ($ui.btnRescan) { $ui.btnRescan.IsEnabled = $true }
    })
    $timer.Start()
}

#--- Dispatch optimize / restore work to background runspace --------------
function Invoke-OptimizerWork {
    param(
        [Parameter(Mandatory)][ValidateSet('Optimize','Restore')] [string] $Action,
        [hashtable] $Options = @{}
    )

    if ($Script:IsRunning) {
        Write-Log "An operation is already running - ignoring." -Level Warning
        return
    }
    $Script:IsRunning = $true
    if ($ui.btnOptimize)      { $ui.btnOptimize.IsEnabled      = $false }
    if ($ui.btnApplySelected) { $ui.btnApplySelected.IsEnabled = $false }
    if ($ui.btnRevert)        { $ui.btnRevert.IsEnabled        = $false }
    if ($ui.btnRescan)        { $ui.btnRescan.IsEnabled        = $false }
    if ($ui.progressBar)      { $ui.progressBar.IsIndeterminate = $true }
    if ($ui.lblStatus)        { $ui.lblStatus.Text             = 'Working...' }

    # Switch to Log tab so the user can watch progress live
    if ($ui.tabMain) { $ui.tabMain.SelectedIndex = 5 }

    $rs = [runspacefactory]::CreateRunspace()
    $rs.ApartmentState = 'STA'
    $rs.ThreadOptions  = 'ReuseThread'
    $rs.Open()

    $ps = [PowerShell]::Create()
    $ps.Runspace = $rs
    $null = $ps.AddScript($WorkerScript).
                AddArgument($Script:SyncUI).
                AddArgument($Script:ModuleFiles).
                AddArgument($Action).
                AddArgument($Options)

    $Script:Runspace     = $rs
    $Script:PowerShell   = $ps
    $Script:WorkerHandle = $ps.BeginInvoke()

    $timer = New-Object System.Windows.Threading.DispatcherTimer
    $timer.Interval = [TimeSpan]::FromMilliseconds(250)
    $timer.Add_Tick({
        if (-not $Script:WorkerHandle.IsCompleted) { return }
        $this.Stop()

        try {
            $Script:PowerShell.EndInvoke($Script:WorkerHandle)
        } catch {
            Write-Log "Worker error: $($_.Exception.Message)" -Level Error
            $hadError = $true
        }
        try { $Script:PowerShell.Dispose() } catch { }
        try { $Script:Runspace.Close(); $Script:Runspace.Dispose() } catch { }

        $Script:IsRunning                = $false
        if ($ui.btnOptimize)      { $ui.btnOptimize.IsEnabled      = $true }
        if ($ui.btnApplySelected) { $ui.btnApplySelected.IsEnabled = $true }
        if ($ui.btnRevert)        { $ui.btnRevert.IsEnabled        = $true }
        if ($ui.btnRescan)        { $ui.btnRescan.IsEnabled        = $true }
        if ($ui.progressBar) {
            $ui.progressBar.IsIndeterminate = $false
            $ui.progressBar.Value           = 100
        }
        if ($ui.lblStatus) { $ui.lblStatus.Text = if ($hadError) { 'Completed with errors' } else { 'Done' } }

        try {
            $latest = Get-LatestBackupPath
            if ($latest) { $ui.lblBackupInfo.Text = "Last snapshot: $(Split-Path $latest -Leaf)" }
        } catch { }

        $msg = if ($hadError) {
            "Optimization completed with errors.`n`nSee the Log tab for details."
        } else {
            "Optimization complete.`n`nSee the Log tab for a full breakdown.`n`nNote: changes to HAGS or optional features require a reboot to take effect."
        }
        [System.Windows.MessageBox]::Show($msg, 'Win11 Optimizer', 'OK', 'Information') | Out-Null

        # Refresh [Done] indicators now that changes have been applied
        Invoke-StateScan
    })
    $timer.Start()
}

#--- Read UI selections into options object -------------------------------
function Get-OptionsFromUI {
    @{
        Debloat = @{
            Teams     = if ($ui.cbDebloatTeams) { [bool]$ui.cbDebloatTeams.IsChecked } else { $false }
            Clipchamp = if ($ui.cbDebloatClipchamp) { [bool]$ui.cbDebloatClipchamp.IsChecked } else { $false }
            Weather   = if ($ui.cbDebloatWeather) { [bool]$ui.cbDebloatWeather.IsChecked } else { $false }
            News      = if ($ui.cbDebloatNews) { [bool]$ui.cbDebloatNews.IsChecked } else { $false }
            Tips      = if ($ui.cbDebloatTips) { [bool]$ui.cbDebloatTips.IsChecked } else { $false }
            GetHelp   = if ($ui.cbDebloatGetHelp) { [bool]$ui.cbDebloatGetHelp.IsChecked } else { $false }
            Maps      = if ($ui.cbDebloatMaps) { [bool]$ui.cbDebloatMaps.IsChecked } else { $false }
            People    = if ($ui.cbDebloatPeople) { [bool]$ui.cbDebloatPeople.IsChecked } else { $false }
            MoviesTV  = if ($ui.cbDebloatMoviesTV) { [bool]$ui.cbDebloatMoviesTV.IsChecked } else { $false }
            Cortana   = if ($ui.cbDebloatCortana) { [bool]$ui.cbDebloatCortana.IsChecked } else { $false }
            Xbox      = if ($ui.cbDebloatXbox) { [bool]$ui.cbDebloatXbox.IsChecked } else { $false }
            OneDrive  = if ($ui.cbDebloatOneDrive) { [bool]$ui.cbDebloatOneDrive.IsChecked } else { $false }
        }
        Performance = @{
            DisableSysMain       = if ($ui.cbPerfSysMain) { [bool]$ui.cbPerfSysMain.IsChecked } else { $false }
            DisableDiagTrack     = if ($ui.cbPerfDiagTrack) { [bool]$ui.cbPerfDiagTrack.IsChecked } else { $false }
            DisableFax           = if ($ui.cbPerfFax) { [bool]$ui.cbPerfFax.IsChecked } else { $false }
            DisableRemoteReg     = if ($ui.cbPerfRemoteRegistry) { [bool]$ui.cbPerfRemoteRegistry.IsChecked } else { $false }
            DisablePrintSpooler  = if ($ui.cbPerfPrintSpooler) { [bool]$ui.cbPerfPrintSpooler.IsChecked } else { $false }
            DisableAnimations    = if ($ui.cbPerfAnimations) { [bool]$ui.cbPerfAnimations.IsChecked } else { $false }
            HighPerformance      = if ($ui.cbPerfHighPerf) { [bool]$ui.cbPerfHighPerf.IsChecked } else { $false }
            DisableStartupApps   = if ($ui.cbPerfStartup) { [bool]$ui.cbPerfStartup.IsChecked } else { $false }
        }
        Gaming = @{
            GameMode       = if ($ui.cbGameMode) { [bool]$ui.cbGameMode.IsChecked } else { $false }
            HAGS           = if ($ui.cbHAGS) { [bool]$ui.cbHAGS.IsChecked } else { $false }
            DisableGameBar = if ($ui.cbDisableGameBar) { [bool]$ui.cbDisableGameBar.IsChecked } else { $false }
            DisableGameDVR = if ($ui.cbDisableGameDVR) { [bool]$ui.cbDisableGameDVR.IsChecked } else { $false }
            TCPNoDelay     = if ($ui.cbGameTCPNoDelay) { [bool]$ui.cbGameTCPNoDelay.IsChecked } else { $false }
        }
        DevTools = @{
            WSL        = if ($ui.cbDevWSL) { [bool]$ui.cbDevWSL.IsChecked } else { $false }
            VMP        = if ($ui.cbDevVMP) { [bool]$ui.cbDevVMP.IsChecked } else { $false }
            HyperV     = if ($ui.cbDevHyperV) { [bool]$ui.cbDevHyperV.IsChecked } else { $false }
            Containers = if ($ui.cbDevContainers) { [bool]$ui.cbDevContainers.IsChecked } else { $false }
        }
        Privacy = @{
            AdvertisingId    = if ($ui.cbPrivAdId) { [bool]$ui.cbPrivAdId.IsChecked } else { $false }
            Telemetry        = if ($ui.cbPrivTelemetry) { [bool]$ui.cbPrivTelemetry.IsChecked } else { $false }
            ConsumerFeatures = if ($ui.cbPrivConsumerFeatures) { [bool]$ui.cbPrivConsumerFeatures.IsChecked } else { $false }
            StartTracking    = if ($ui.cbPrivStartTracking) { [bool]$ui.cbPrivStartTracking.IsChecked } else { $false }
            BackgroundApps   = if ($ui.cbPrivBackgroundApps) { [bool]$ui.cbPrivBackgroundApps.IsChecked } else { $false }
            DeliveryOpt      = if ($ui.cbPrivacyDeliveryOpt) { [bool]$ui.cbPrivacyDeliveryOpt.IsChecked } else { $false }
            EdgeTelemetry    = if ($ui.cbPrivacyEdgeTelemetry) { [bool]$ui.cbPrivacyEdgeTelemetry.IsChecked } else { $false }
        }
    }
}

#--- Button handlers ------------------------------------------------------
if ($ui.btnOptimize) {
    $ui.btnOptimize.Add_Click({
        $opts = Get-OptionsFromUI
        Invoke-OptimizerWork -Action 'Optimize' -Options $opts
    })
}

if ($ui.btnApplySelected) {
    $ui.btnApplySelected.Add_Click({
        $opts = Get-OptionsFromUI
        Invoke-OptimizerWork -Action 'Optimize' -Options $opts
    })
}

if ($ui.btnRevert) {
    $ui.btnRevert.Add_Click({
        $confirm = [System.Windows.MessageBox]::Show(
            "Revert all changes from the most recent backup snapshot?",
            'Confirm Revert', 'YesNo', 'Question')
        if ($confirm -ne 'Yes') { return }
        Invoke-OptimizerWork -Action 'Restore'
    })
}

if ($ui.btnRescan) {
    $ui.btnRescan.Add_Click({
        Invoke-StateScan
    })
}

if ($ui.lnkSouthOpsForge) {
    $ui.lnkSouthOpsForge.Add_RequestNavigate({
        param($sender, $e)
        try { [System.Diagnostics.Process]::Start($e.Uri.AbsoluteUri) | Out-Null } catch {}
        $e.Handled = $true
    })
}

#--- Startup initialisation -----------------------------------------------
try {
    $latest = Get-LatestBackupPath
    if ($latest -and $ui.lblBackupInfo) { 
        $ui.lblBackupInfo.Text = "Last snapshot: $(Split-Path $latest -Leaf)" 
    }
} catch {
    Log-Debug "  Warning: Failed to read backup path: $($_.Exception.Message)"
}

try {
    Write-Log "Win11 Optimizer ready. Log file: $(Get-LogFilePath)" -Level Info
} catch { }

# Kick off an initial state scan so [Done] indicators populate on first launch
Log-Debug "Re-enabling initial scan..."
try {
    Invoke-StateScan
} catch {
    Log-Debug "  Warning: Initial state scan failed: $($_.Exception.Message)"
}

Log-Debug "Checking Window status: $(if ($Window) { 'OK' } else { 'NULL' })"
if ($null -eq $Window) { throw "Window object is null right before ShowDialog!" }

Log-Debug "Starting UI (ShowDialog)..."
try {
    $null = $Window.ShowDialog()
} catch {
    $e = $_.Exception
    Log-Debug "  !!! CRITICAL ShowDialog Error !!!"
    while ($e) {
        Log-Debug "  Exception: $($e.Message)"
        if ($e.StackTrace) { Log-Debug "  Stack: $($e.StackTrace)" }
        $e = $e.InnerException
    }
    throw $_
}
Log-Debug "Window closed."
