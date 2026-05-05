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

# Load modules into the current runspace (used for admin gate, latest-backup probe).
# The worker runspace dot-sources them again so it has its own copies.
$Script:ModuleFiles = @(
    'Logger.ps1', 'Backup.ps1', 'Common.ps1',
    'Performance.ps1', 'Bloatware.ps1', 'Gaming.ps1',
    'Privacy.ps1', 'DevTools.ps1', 'Restore.ps1'
) | ForEach-Object { Join-Path $Script:ModuleDir $_ }

foreach ($m in $Script:ModuleFiles) { . $m }

#--- Admin gate -----------------------------------------------------------
if (-not (Test-IsAdmin)) {
    [System.Windows.MessageBox]::Show(
        "This optimizer requires Administrator privileges.`n`nRelaunch via Launch.bat.",
        'Win11 Optimizer', 'OK', 'Warning') | Out-Null
    return
}

#--- Load XAML ------------------------------------------------------------
[xml]$xaml = Get-Content -Path $Script:XamlPath -Raw
$reader   = New-Object System.Xml.XmlNodeReader $xaml
$Window   = [Windows.Markup.XamlReader]::Load($reader)

# Bind every named element into a hashtable for easy access
$ui = @{}
$xaml.SelectNodes("//*[@*[local-name()='Name']]") | ForEach-Object {
    $name = $_.GetAttribute('Name','http://schemas.microsoft.com/winfx/2006/xaml')
    if ($name) { $ui[$name] = $Window.FindName($name) }
}

Set-LoggerUIContext -Window $Window -RichTextBox $ui.rtbLog

#--- Worker runspace ------------------------------------------------------
$Script:Runspace      = $null
$Script:PowerShell    = $null
$Script:WorkerHandle  = $null
$Script:IsRunning     = $false

# The worker entry point. Dot-sources modules, wires logger, then dispatches by Action.
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
                Write-Log "Reboot recommended if you toggled HAGS or Optional Features." -Level Info
            }
            'Restore' {
                Restore-SystemDefaults
            }
        }
    } catch {
        Write-Log "Fatal: $($_.Exception.Message)" -Level Error
    }
}

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
    $ui.btnOptimize.IsEnabled       = $false
    $ui.btnApplySelected.IsEnabled  = $false
    $ui.btnRevert.IsEnabled         = $false
    $ui.progressBar.IsIndeterminate = $true
    $ui.lblStatus.Text              = 'Working...'

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
        if ($Script:WorkerHandle.IsCompleted) {
            $timer.Stop()
            try { $Script:PowerShell.EndInvoke($Script:WorkerHandle) } catch {
                Write-Log "Worker error: $($_.Exception.Message)" -Level Error
            }
            $Script:PowerShell.Dispose()
            $Script:Runspace.Close()
            $Script:Runspace.Dispose()
            $Script:IsRunning = $false
            $ui.btnOptimize.IsEnabled       = $true
            $ui.btnApplySelected.IsEnabled  = $true
            $ui.btnRevert.IsEnabled         = $true
            $ui.progressBar.IsIndeterminate = $false
            $ui.progressBar.Value           = 100
            $ui.lblStatus.Text              = 'Done'
            $latest = Get-LatestBackupPath
            if ($latest) { $ui.lblBackupInfo.Text = "Last snapshot: $(Split-Path $latest -Leaf)" }
        }
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
            DisableSysMain      = [bool]$ui.cbPerfSysMain.IsChecked
            DisableDiagTrack    = [bool]$ui.cbPerfDiagTrack.IsChecked
            DisableFax          = [bool]$ui.cbPerfFax.IsChecked
            DisableRemoteReg    = [bool]$ui.cbPerfRemoteRegistry.IsChecked
            DisablePrintSpooler = [bool]$ui.cbPerfPrintSpooler.IsChecked
            DisableAnimations   = [bool]$ui.cbPerfAnimations.IsChecked
            HighPerformance     = [bool]$ui.cbPerfHighPerf.IsChecked
            DisableStartupApps  = [bool]$ui.cbPerfStartup.IsChecked
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

# Show last backup if one already exists
$latest = Get-LatestBackupPath
if ($latest) { $ui.lblBackupInfo.Text = "Last snapshot: $(Split-Path $latest -Leaf)" }

Write-Log "Win11 Optimizer ready. Log file: $(Get-LogFilePath)" -Level Info
$null = $Window.ShowDialog()
