# Restore.ps1 - Reverses changes captured in a backup snapshot.

function Restore-SystemDefaults {
    [CmdletBinding()]
    param([string] $BackupPath)

    if (-not $BackupPath) { $BackupPath = Get-LatestBackupPath }
    if (-not $BackupPath -or -not (Test-Path $BackupPath)) {
        Write-Log "No backup snapshot found - nothing to restore." -Level Warning
        return
    }

    Write-Log "=== Restore from $BackupPath ===" -Level Info
    $snap = Get-Content -Path $BackupPath -Raw | ConvertFrom-Json

    # Services
    foreach ($s in @($snap.Services)) {
        try {
            $startup = switch ($s.StartupType) {
                'Auto'     { 'Automatic' }
                'Boot'     { 'Automatic' }
                'System'   { 'Automatic' }
                'Manual'   { 'Manual' }
                'Disabled' { 'Disabled' }
                default    { 'Manual' }
            }
            Set-Service -Name $s.Name -StartupType $startup -ErrorAction Stop
            if ($s.Status -eq 'Running') {
                Start-Service -Name $s.Name -ErrorAction SilentlyContinue
            }
            Write-Log "Service restored: $($s.Name) -> $startup" -Level Success
        } catch {
            Write-Log "Could not restore service $($s.Name): $($_.Exception.Message)" -Level Warning
        }
    }

    # Registry
    foreach ($r in @($snap.Registry)) {
        try {
            if ($r.Existed) {
                if (-not (Test-Path $r.Path)) { New-Item -Path $r.Path -Force | Out-Null }
                $type = if ($r.Type) { $r.Type } else { 'DWord' }
                New-ItemProperty -Path $r.Path -Name $r.Name -Value $r.Value -PropertyType $type -Force | Out-Null
                Write-Log "Registry restored: $($r.Path)\$($r.Name)" -Level Success
            } else {
                if (Test-Path $r.Path) {
                    Remove-ItemProperty -Path $r.Path -Name $r.Name -ErrorAction SilentlyContinue
                    Write-Log "Registry value removed (was absent): $($r.Path)\$($r.Name)" -Level Success
                }
            }
        } catch {
            Write-Log "Registry restore failed: $($r.Path)\$($r.Name): $($_.Exception.Message)" -Level Warning
        }
    }

    # Appx - reinstall via provisioned package if still on system
    foreach ($a in @($snap.Appx)) {
        try {
            $existing = Get-AppxPackage -Name $a.FamilyName.Split('_')[0] -ErrorAction SilentlyContinue
            if ($existing) { Write-Log "Appx already present: $($a.FamilyName)" -Level Skip; continue }

            $prov = Get-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue |
                    Where-Object { $_.PackageName -eq $a.PackageFullName -or $_.DisplayName -eq $a.FamilyName.Split('_')[0] }
            if ($prov) {
                $manifest = Join-Path $env:ProgramFiles ("WindowsApps\{0}\AppxManifest.xml" -f $prov.PackageName)
                if (Test-Path $manifest) {
                    Add-AppxPackage -Register $manifest -DisableDevelopmentMode -ErrorAction Stop
                    Write-Log "Appx restored: $($a.FamilyName)" -Level Success
                    continue
                }
            }
            Write-Log "Appx cannot be auto-restored (reinstall from Microsoft Store): $($a.FamilyName)" -Level Warning
        } catch {
            Write-Log "Appx restore failed for $($a.FamilyName): $($_.Exception.Message)" -Level Warning
        }
    }

    # Power plan
    if ($snap.PowerPlan) {
        try {
            $null = powercfg /setactive $snap.PowerPlan
            Write-Log "Power plan restored: $($snap.PowerPlan)" -Level Success
        } catch {
            Write-Log "Power plan restore failed: $($_.Exception.Message)" -Level Warning
        }
    }

    # Optional features - we only re-disable features that were Disabled before
    foreach ($f in @($snap.Features)) {
        try {
            if ($f.State -eq 'Disabled') {
                $cur = Get-WindowsOptionalFeature -Online -FeatureName $f.Name -ErrorAction Stop
                if ($cur.State -ne 'Disabled') {
                    Disable-WindowsOptionalFeature -Online -FeatureName $f.Name -NoRestart -ErrorAction Stop | Out-Null
                    Write-Log "Feature reverted to Disabled: $($f.Name) (reboot required)" -Level Success
                }
            }
        } catch {
            Write-Log "Feature restore failed: $($f.Name): $($_.Exception.Message)" -Level Warning
        }
    }

    Write-Log "Restore complete." -Level Success
}
