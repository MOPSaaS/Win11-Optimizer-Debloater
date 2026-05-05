# Backup.ps1 - State capture so every change is reversible.
# Each Optimize/Apply session writes a single JSON snapshot under ProgramData\Win11Optimizer\backups.

$Script:BackupRoot = Join-Path $env:ProgramData 'Win11Optimizer\backups'
$null = New-Item -ItemType Directory -Path $Script:BackupRoot -Force -ErrorAction SilentlyContinue

$Script:CurrentBackup = $null
$Script:CurrentBackupPath = $null

function Start-BackupSession {
    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $Script:CurrentBackupPath = Join-Path $Script:BackupRoot "backup-$stamp.json"
    $Script:CurrentBackup = [ordered]@{
        Created   = (Get-Date).ToString('o')
        Services  = @()
        Registry  = @()
        Appx      = @()
        PowerPlan = $null
        Features  = @()
        Startup   = @()
    }
    $Script:CurrentBackup | ConvertTo-Json -Depth 6 | Set-Content -Path $Script:CurrentBackupPath -Encoding utf8
    return $Script:CurrentBackupPath
}

function Save-BackupSession {
    if ($Script:CurrentBackup -and $Script:CurrentBackupPath) {
        $Script:CurrentBackup | ConvertTo-Json -Depth 6 | Set-Content -Path $Script:CurrentBackupPath -Encoding utf8
    }
}

function Get-LatestBackupPath {
    Get-ChildItem -Path $Script:BackupRoot -Filter 'backup-*.json' -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1 -ExpandProperty FullName
}

function Backup-Service {
    param([Parameter(Mandatory)][string] $Name)
    $svc = Get-Service -Name $Name -ErrorAction SilentlyContinue
    if (-not $svc) { return }
    $startup = (Get-CimInstance -ClassName Win32_Service -Filter "Name='$Name'" -ErrorAction SilentlyContinue).StartMode
    $Script:CurrentBackup.Services += [pscustomobject]@{
        Name        = $Name
        StartupType = $startup
        Status      = $svc.Status.ToString()
    }
    Save-BackupSession
}

function Backup-RegistryValue {
    param(
        [Parameter(Mandatory)][string] $Path,
        [Parameter(Mandatory)][string] $Name
    )
    $existed = $false
    $value   = $null
    $type    = $null
    try {
        if (Test-Path $Path) {
            $item = Get-ItemProperty -Path $Path -Name $Name -ErrorAction Stop
            $existed = $true
            $value   = $item.$Name
            $kind    = (Get-Item -Path $Path).GetValueKind($Name)
            $type    = $kind.ToString()
        }
    } catch { $existed = $false }

    $Script:CurrentBackup.Registry += [pscustomobject]@{
        Path    = $Path
        Name    = $Name
        Value   = $value
        Type    = $type
        Existed = $existed
    }
    Save-BackupSession
}

function Backup-AppxRemoval {
    param([Parameter(Mandatory)][string] $PackageFullName, [string] $Family)
    $Script:CurrentBackup.Appx += [pscustomobject]@{
        PackageFullName = $PackageFullName
        FamilyName      = $Family
    }
    Save-BackupSession
}

function Backup-PowerPlan {
    $active = (powercfg /getactivescheme) -replace '.*GUID:\s*([a-f0-9\-]+).*', '$1' | Select-Object -First 1
    $Script:CurrentBackup.PowerPlan = $active.Trim()
    Save-BackupSession
}

function Backup-Feature {
    param([Parameter(Mandatory)][string] $Name)
    try {
        $f = Get-WindowsOptionalFeature -Online -FeatureName $Name -ErrorAction Stop
        $Script:CurrentBackup.Features += [pscustomobject]@{
            Name  = $Name
            State = $f.State.ToString()
        }
        Save-BackupSession
    } catch { }
}

function Backup-StartupValue {
    param([Parameter(Mandatory)][string] $Path, [Parameter(Mandatory)][string] $Name, $Value)
    $Script:CurrentBackup.Startup += [pscustomobject]@{
        Path  = $Path
        Name  = $Name
        Value = $Value
    }
    Save-BackupSession
}
