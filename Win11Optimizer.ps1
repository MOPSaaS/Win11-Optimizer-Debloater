# Win11Optimizer.ps1 - WPF entry point
# Loads MainWindow.xaml, wires up handlers, and dispatches work to a background runspace.

[CmdletBinding()]
param()

#--- Setup ----------------------------------------------------------------
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase

$Script:Root      = Split-Path -Parent $MyInvocation.MyCommand.Definition
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

foreach ($m in $Script:ModuleFiles) { . $m }
. (Join-Path $Script:ModuleDir 'StateDetector.ps1')

#--- Admin gate -----------------------------------------------------------
if (-not (Test-IsAdmin)) {
    [System.Windows.MessageBox]::Show(
        "This optimizer requires Administrator privileges.`n`nRelaunch via Launch.bat.",
        'Win11 Optimizer', 'OK', 'Warning') | Out-Null
    return
}

#--- Load XAML ------------------------------------------------------------
[xml]$xaml = Get-Content -Path $Script:XamlPath -Raw -Encoding UTF8
$reader    = New-Object System.Xml.XmlNodeReader $xaml
$Window    = [Windows.Markup.XamlReader]::Load($reader)

# Bind every named element into a hashtable for easy access
$ui = @{}
$xaml.SelectNodes("//*[@*[local-name()='Name']]") | ForEach-Object {
    $name = $_.GetAttribute('Name','http://schemas.microsoft.com/winfx/2006/xaml')
    if ($name) { $ui[$name] = $Window.FindName($name) }
}

Set-LoggerUIContext -Window $Window -RichTextBox $ui.rtbLog

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
    param($Window, $UILog, $ModuleFiles, $Action, $Options)
    foreach ($m in $ModuleFiles) { . $m }
    Set-LoggerUIContext -Window $Window -RichTextBox $UILog

    try {
        switch ($Action) {
            'Optimize' {
                $path = Start-BackupSession
                Write-Log "Backup snapshot: $path" -Level Info
                $perf = $Options.Performance; Optimize-Performance @perf
                $deb  = $Options.Debloat;     Remove-Bloatware     @deb
                $gam  = $Options.Gaming;      Apply-GamingTweaks   @gam
                $dev  = $Options.DevTools;    Apply-DevToolsTweaks @dev
                $priv = $Options.Privacy;     Apply-PrivacySettings @priv
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
    foreach ($m in $ModuleFiles) { . $m }
    Get-SystemOptimizationState
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
    )

    $applied = 0
    $pending = 0
    foreach ($item in $map) {
        $cb   = $ui[$item.CB]
        $done = [bool]$State[$item.Key]
        if ($done) {
            $cb.Content    = "$($item.Text)  [Done]"
            $cb.Foreground = $Script:BrushDone
            $applied++
        } else {
            $cb.Content    = $item.Text
            $cb.Foreground = $Script:BrushNormal
            $pending++
        }
    }

    return @{ Applied = $applied; Pending = $pending }
}

#--- Invoke state scan in a background runspace ---------------------------
function Invoke-StateScan {
    if ($Script:IsRunning -or $Script:IsScan) { return }

    $Script:IsScan = $true
    $ui.btnRescan.IsEnabled  = $false
    $ui.lblScanStatus.Text   = 'Scanning system...'

    $rs = [runspacefactory]::CreateRunspace()
    $rs.ApartmentState = 'STA'
    $rs.ThreadOptions  = 'ReuseThread'
    $rs.Open()

    $ps = [PowerShell]::Create()
    $ps.Runspace = $rs
    $null = $ps.AddScript($ScanScript).AddArgument($Script:ScanModuleFiles)

    $Script:ScanRunspace   = $rs
    $Script:ScanPowerShell = $ps
    $Script:ScanHandle     = $ps.BeginInvoke()

    $timer = New-Object System.Windows.Threading.DispatcherTimer
    $timer.Interval = [TimeSpan]::FromMilliseconds(250)
    $timer.Add_Tick({
        if (-not $Script:ScanHandle.IsCompleted) { return }
        $timer.Stop()
        try {
            $result = $Script:ScanPowerShell.EndInvoke($Script:ScanHandle)
            $state  = $result[0]
            if ($state -is [hashtable]) {
                $counts = Update-UIFromState -State $state
                $ui.lblScanStatus.Text = "$($counts.Applied) items already applied, $($counts.Pending) pending"
            } else {
                $ui.lblScanStatus.Text = 'Scan returned no data'
            }
        } catch {
            $ui.lblScanStatus.Text = 'Scan failed'
            Write-Log "State scan error: $($_.Exception.Message)" -Level Warning
        } finally {
            try { $Script:ScanPowerShell.Dispose() } catch { }
            try { $Script:ScanRunspace.Close(); $Script:ScanRunspace.Dispose() } catch { }
            $Script:IsScan          = $false
            $ui.btnRescan.IsEnabled = $true
        }
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
    $ui.btnOptimize.IsEnabled      = $false
    $ui.btnApplySelected.IsEnabled = $false
    $ui.btnRevert.IsEnabled        = $false
    $ui.btnRescan.IsEnabled        = $false
    $ui.progressBar.IsIndeterminate = $true
    $ui.lblStatus.Text             = 'Working...'

    # Switch to Log tab so the user can watch progress live
    $ui.tabMain.SelectedIndex = 5

    $rs = [runspacefactory]::CreateRunspace()
    $rs.ApartmentState = 'STA'
    $rs.ThreadOptions  = 'ReuseThread'
    $rs.Open()

    $ps = [PowerShell]::Create()
    $ps.Runspace = $rs
    $null = $ps.AddScript($WorkerScript).
                AddArgument($Window).
                AddArgument($ui.rtbLog).
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
        $timer.Stop()

        $hadError = $false
        try {
            $Script:PowerShell.EndInvoke($Script:WorkerHandle)
        } catch {
            Write-Log "Worker error: $($_.Exception.Message)" -Level Error
            $hadError = $true
        }
        try { $Script:PowerShell.Dispose() } catch { }
        try { $Script:Runspace.Close(); $Script:Runspace.Dispose() } catch { }

        $Script:IsRunning                = $false
        $ui.btnOptimize.IsEnabled        = $true
        $ui.btnApplySelected.IsEnabled   = $true
        $ui.btnRevert.IsEnabled          = $true
        $ui.btnRescan.IsEnabled          = $true
        $ui.progressBar.IsIndeterminate  = $false
        $ui.progressBar.Value            = 100
        $ui.lblStatus.Text               = if ($hadError) { 'Completed with errors' } else { 'Done' }

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
            Teams     = [bool]$ui.cbDebloatTeams.IsChecked
            Clipchamp = [bool]$ui.cbDebloatClipchamp.IsChecked
            Weather   = [bool]$ui.cbDebloatWeather.IsChecked
            News      = [bool]$ui.cbDebloatNews.IsChecked
            Tips      = [bool]$ui.cbDebloatTips.IsChecked
            GetHelp   = [bool]$ui.cbDebloatGetHelp.IsChecked
            Maps      = [bool]$ui.cbDebloatMaps.IsChecked
            People    = [bool]$ui.cbDebloatPeople.IsChecked
            MoviesTV  = [bool]$ui.cbDebloatMoviesTV.IsChecked
            Cortana   = [bool]$ui.cbDebloatCortana.IsChecked
            Xbox      = [bool]$ui.cbDebloatXbox.IsChecked
        }
        Performance = @{
            DisableSysMain       = [bool]$ui.cbPerfSysMain.IsChecked
            DisableDiagTrack     = [bool]$ui.cbPerfDiagTrack.IsChecked
            DisableFax           = [bool]$ui.cbPerfFax.IsChecked
            DisableRemoteReg     = [bool]$ui.cbPerfRemoteRegistry.IsChecked
            DisablePrintSpooler  = [bool]$ui.cbPerfPrintSpooler.IsChecked
            DisableAnimations    = [bool]$ui.cbPerfAnimations.IsChecked
            HighPerformance      = [bool]$ui.cbPerfHighPerf.IsChecked
            DisableStartupApps   = [bool]$ui.cbPerfStartup.IsChecked
        }
        Gaming = @{
            GameMode       = [bool]$ui.cbGameMode.IsChecked
            HAGS           = [bool]$ui.cbHAGS.IsChecked
            DisableGameBar = [bool]$ui.cbDisableGameBar.IsChecked
            DisableGameDVR = [bool]$ui.cbDisableGameDVR.IsChecked
        }
        DevTools = @{
            WSL        = [bool]$ui.cbDevWSL.IsChecked
            VMP        = [bool]$ui.cbDevVMP.IsChecked
            HyperV     = [bool]$ui.cbDevHyperV.IsChecked
            Containers = [bool]$ui.cbDevContainers.IsChecked
        }
        Privacy = @{
            AdvertisingId    = [bool]$ui.cbPrivAdId.IsChecked
            Telemetry        = [bool]$ui.cbPrivTelemetry.IsChecked
            ConsumerFeatures = [bool]$ui.cbPrivConsumerFeatures.IsChecked
            StartTracking    = [bool]$ui.cbPrivStartTracking.IsChecked
            BackgroundApps   = [bool]$ui.cbPrivBackgroundApps.IsChecked
        }
    }
}

#--- Button handlers ------------------------------------------------------
$ui.btnOptimize.Add_Click({
    $opts = Get-OptionsFromUI
    Invoke-OptimizerWork -Action 'Optimize' -Options $opts
})

$ui.btnApplySelected.Add_Click({
    $opts = Get-OptionsFromUI
    Invoke-OptimizerWork -Action 'Optimize' -Options $opts
})

$ui.btnRevert.Add_Click({
    $confirm = [System.Windows.MessageBox]::Show(
        "Revert all changes from the most recent backup snapshot?",
        'Confirm Revert', 'YesNo', 'Question')
    if ($confirm -ne 'Yes') { return }
    Invoke-OptimizerWork -Action 'Restore'
})

$ui.btnRescan.Add_Click({
    Invoke-StateScan
})

#--- Startup initialisation -----------------------------------------------
$latest = Get-LatestBackupPath
if ($latest) { $ui.lblBackupInfo.Text = "Last snapshot: $(Split-Path $latest -Leaf)" }

Write-Log "Win11 Optimizer ready. Log file: $(Get-LogFilePath)" -Level Info

# Kick off an initial state scan so [Done] indicators populate on first launch
Invoke-StateScan

$null = $Window.ShowDialog()
