# Common.ps1 - Shared helpers (registry, service, idempotency)

function Set-RegistryValueSafe {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string] $Path,
        [Parameter(Mandatory)][string] $Name,
        [Parameter(Mandatory)] $Value,
        [ValidateSet('String','ExpandString','DWord','QWord','MultiString','Binary')]
        [string] $Type = 'DWord'
    )

    Backup-RegistryValue -Path $Path -Name $Name

    if (-not (Test-Path $Path)) {
        $null = New-Item -Path $Path -Force
    }

    $current = $null
    try { $current = (Get-ItemProperty -Path $Path -Name $Name -ErrorAction Stop).$Name } catch { }

    if ($null -ne $current -and "$current" -eq "$Value") {
        Write-Log "Registry already set: $Path\$Name = $Value" -Level Skip
        return $false
    }

    try {
        New-ItemProperty -Path $Path -Name $Name -Value $Value -PropertyType $Type -Force -ErrorAction Stop | Out-Null
        Write-Log "Set $Path\$Name = $Value ($Type)" -Level Success
        return $true
    } catch {
        Write-Log "Failed to set registry $Path\$Name : $($_.Exception.Message)" -Level Warning
        return $false
    }
}

function Disable-ServiceSafe {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string] $Name)

    $svc = Get-Service -Name $Name -ErrorAction SilentlyContinue
    if (-not $svc) {
        Write-Log "Service not present: $Name" -Level Skip
        return
    }

    Backup-Service -Name $Name

    try {
        if ($svc.Status -eq 'Running') {
            Stop-Service -Name $Name -Force -ErrorAction Stop
        }
        Set-Service -Name $Name -StartupType Disabled -ErrorAction Stop
        Write-Log "Disabled service: $Name" -Level Success
    } catch {
        Write-Log "Failed to disable $Name : $($_.Exception.Message)" -Level Warning
    }
}

function Test-IsAdmin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    (New-Object Security.Principal.WindowsPrincipal($id)).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}
