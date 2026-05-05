# Win11 Performance Optimizer

A safe, reversible Windows 11 (24H2 / 25H2) optimization utility with a WPF GUI. Designed for primary machines used for gaming, development, and automation — not a "debloat destroyer".

Every change is captured to a JSON snapshot **before** it is applied, so the entire optimization can be rolled back from the GUI or from a snapshot file. Windows Update, Microsoft Store, Defender, anti-cheat (EAC, BattlEye, Vanguard), GPU drivers, and developer toolchains (WSL, Docker, .NET, VS Code, Git) are explicitly preserved.

---

## Features

- **One-click optimization** with a granular advanced view across five tabs: Debloat, Performance, Gaming, Dev Tools, Privacy.
- **Idempotent** — every operation checks current state before writing; rerunning is a no-op.
- **Snapshot-based rollback** — the Revert button replays the most recent snapshot in reverse.
- **Worker runspace** keeps the WPF UI responsive during long operations; live colored log.
- **Safety guards** — hard-coded protected list refuses to remove Gaming Services, Defender, the Store, runtimes, anti-cheat dependencies.
- **Logs and snapshots** persisted under `C:\ProgramData\Win11Optimizer\` (preserved on uninstall).

---

## Requirements

- Windows 11 24H2 or 25H2 (Pro / Home / Education)
- PowerShell 5.1 (ships with Windows) or PowerShell 7+
- Administrator account

---

## Quick start

```powershell
git clone https://github.com/MOPSaaS/Win11-Optimizer-Debloater.git
cd Win11-Optimizer-Debloater
.\Launch.bat
```

`Launch.bat` self-elevates, then starts the WPF GUI. Click **Optimize Now** to apply defaults, or refine via the tabs and use **Apply Selected**. Use **Revert Changes** at any time to roll back.

---

## Project layout

```
Win11Optimizer/
├── Launch.bat                  # Self-elevating launcher
├── Win11Optimizer.ps1          # WPF entry point
├── MainWindow.xaml             # WPF UI definition
├── Modules/
│   ├── Logger.ps1              # Centralized logging (file + GUI)
│   ├── Backup.ps1              # State snapshot persistence
│   ├── Common.ps1              # Idempotent registry/service helpers
│   ├── Performance.ps1         # Optimize-Performance
│   ├── Bloatware.ps1           # Remove-Bloatware
│   ├── Gaming.ps1              # Apply-GamingTweaks
│   ├── Privacy.ps1             # Apply-PrivacySettings
│   ├── DevTools.ps1            # Apply-DevToolsTweaks
│   └── Restore.ps1             # Restore-SystemDefaults
├── Build/
│   ├── Build-Exe.ps1           # PS2EXE packaging
│   └── installer.iss           # Inno Setup installer
├── .github/workflows/
│   └── ci.yml                  # PSScriptAnalyzer + parse check
├── .editorconfig
├── .gitignore
├── .gitattributes
├── CHANGELOG.md
├── CONTRIBUTING.md
├── LICENSE
└── README.md
```

---

## Architecture

### UI / engine separation

XAML defines the entire window. `Win11Optimizer.ps1` parses the XAML, looks up named controls into a `$ui` hashtable, and binds button handlers. **No system logic lives in the UI layer** — handlers gather checkbox state into a typed options object and pass it to the worker.

### Worker runspace (UI never freezes)

System operations run in a dedicated STA runspace via `[PowerShell]::Create()` with `BeginInvoke()`. A `DispatcherTimer` polls completion on the UI thread and re-enables buttons when the worker finishes. The Logger marshals every line through `Window.Dispatcher.Invoke`, so the RichTextBox updates in real time without cross-thread exceptions.

```
WPF (UI thread)            Invoke-OptimizerWork         Worker runspace
- buttons       --click--> - poll completion --args---> - dot-source modules
- RichTextBox   <--log---- - re-enable UI    <-disp--- - run operation
```

### Idempotency

`Set-RegistryValueSafe` reads the existing value and skips writes if already in the target state. `Disable-ServiceSafe` checks status before stopping. Optional features call `Get-WindowsOptionalFeature` first. Every module is safe to run repeatedly.

### Concurrency guard

`$Script:IsRunning` prevents double-execution while a worker is in flight; the buttons are also disabled visually.

---

## Module reference

| Module | Public function | Purpose |
| --- | --- | --- |
| Logger | `Write-Log`, `Set-LoggerUIContext` | Tee log to file and GUI RichTextBox |
| Backup | `Start-BackupSession`, `Backup-Service`, `Backup-RegistryValue`, `Backup-AppxRemoval`, `Backup-PowerPlan`, `Backup-Feature`, `Get-LatestBackupPath` | Persist a JSON snapshot before each change |
| Common | `Set-RegistryValueSafe`, `Disable-ServiceSafe`, `Test-IsAdmin` | Guarded helpers used by every operation |
| Performance | `Optimize-Performance` | Service tweaks, animation/transparency off, power plan, safe startup pruning |
| Bloatware | `Remove-Bloatware` | Per-user Appx removal with hard protected-list guard |
| Gaming | `Apply-GamingTweaks` | Game Mode, HAGS (`HwSchMode=2`), Game Bar/DVR off |
| Privacy | `Apply-PrivacySettings` | Advertising ID off, telemetry pinned to Required, consumer features off |
| DevTools | `Apply-DevToolsTweaks` | Enable WSL / VMP / Hyper-V / Containers (never removes) |
| Restore | `Restore-SystemDefaults` | Replay latest snapshot in reverse |

---

## What is intentionally NOT touched

- Windows Update services (`wuauserv`, `UsoSvc`, `WaaSMedicSvc`, BITS)
- Windows Defender services and `Microsoft.SecHealthUI`
- Microsoft Store (`Microsoft.WindowsStore`, `Microsoft.DesktopAppInstaller`)
- DirectX, GPU drivers, Gaming Services (`Microsoft.GamingServices`)
- Visual C++ runtimes, .NET runtimes, `Microsoft.UI.Xaml`, `Microsoft.VCLibs`
- Anti-cheat sign-in dependencies (`Microsoft.XboxIdentityProvider`)
- Network stack services
- Telemetry is set to `1` (Required), not `0`. `0` is only honored on Enterprise SKUs and reduces Defender cloud protection on Pro/Home.

---

## Snapshot format

Every change appends to a JSON file under `C:\ProgramData\Win11Optimizer\backups\backup-<timestamp>.json`:

```json
{
  "Created": "2026-05-04T19:48:31",
  "Services": [
    { "Name": "SysMain", "StartupType": "Auto", "Status": "Running" }
  ],
  "Registry": [
    { "Path": "HKLM:\\...", "Name": "HwSchMode", "Value": 1, "Type": "DWord", "Existed": true }
  ],
  "Appx": [
    { "PackageFullName": "Microsoft.BingWeather_...", "FamilyName": "Microsoft.BingWeather_8wekyb3d8bbwe" }
  ],
  "PowerPlan": "381b4222-f694-41f0-9685-ff5bb260df2e",
  "Features": [
    { "Name": "Microsoft-Hyper-V-All", "State": "Disabled" }
  ]
}
```

`Restore-SystemDefaults` reverses each section:

1. **Services** — `Set-Service -StartupType` + start if it was running.
2. **Registry** — re-create with original type if `Existed=true`; remove the value if it didn't exist before.
3. **Appx** — re-register from provisioned package manifest under `WindowsApps`. If unavailable, prompts to reinstall from Microsoft Store (the Store is never removed, so this always works).
4. **Power plan** — `powercfg /setactive <originalGUID>`.
5. **Optional features** — only re-disables features that were `Disabled` before (does not undo features the user had on already).

Snapshots are never auto-deleted. They live in `ProgramData` and survive uninstall.

---

## Manual undo reference

If the GUI revert ever fails, here's how to undo each category by hand:

| Change | Manual undo |
| --- | --- |
| Service disabled | `Set-Service <Name> -StartupType Automatic; Start-Service <Name>` |
| Registry tweak | Read the snapshot JSON for original value/type and apply with `New-ItemProperty` |
| Appx removed | Reinstall from Microsoft Store, or `Add-AppxPackage -Register "<AppxManifest.xml>" -DisableDevelopmentMode` |
| Power plan | `powercfg /setactive 381b4222-f694-41f0-9685-ff5bb260df2e` (Balanced) |
| HAGS | `HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers\HwSchMode` -> `1` (off) or `2` (on); reboot |
| Optional feature | `Disable-WindowsOptionalFeature -Online -FeatureName <Name>` |

---

## Building a distributable

### Option 1 — PS2EXE

```powershell
cd Build
.\Build-Exe.ps1
```

Produces `dist/Win11Optimizer.exe` plus `Modules/` and `MainWindow.xaml` alongside it. The exe is a thin wrapper around the launcher script — companion files must travel with it.

### Option 2 — Inno Setup installer

1. Run `Build-Exe.ps1` to produce `dist/`.
2. Install Inno Setup 6+ from <https://jrsoftware.org/isdl.php>.
3. Compile:
   ```powershell
   iscc Build\installer.iss
   ```
4. Output: `Win11Optimizer-Setup.exe`. Installs to `Program Files\Win11Optimizer`, optional desktop shortcut, optional always-as-admin task. Uninstaller leaves `ProgramData\Win11Optimizer` intact for revert.

### Option 3 — MSIX

For Store-style sideload distribution, wrap `dist/` with `MakeAppx.exe` from the Windows SDK using an `AppxManifest.xml` that declares `runFullTrust`. Requires a code-signing cert. Same payload (exe + xaml + Modules); no script changes needed.

---

## Logging

| Level | Color | Meaning |
| --- | --- | --- |
| Info    | `#C0CAF5` | Normal progress |
| Success | `#9ECE6A` | Change applied |
| Skip    | `#9AA5CE` | Already in target state — no write |
| Warning | `#E0AF68` | Non-fatal failure (e.g. service missing on this SKU) |
| Error   | `#F7768E` | Operation failed — backup preserved |

Log files: `C:\ProgramData\Win11Optimizer\logs\optimize-<timestamp>.log`.

---

## Caveats

- **HAGS** and **Optional Features** require a reboot.
- **Teams Personal** is sometimes reinstalled by Microsoft Store auto-update. Rerun the optimizer to remove again, or rely on the snapshot to restore.
- **Provisioned packages** are not removed — only the per-user install — so a new Windows user account on the same machine will still see the apps. This is by design; touching provisioned packages requires DISM and risks Windows Update integrity.
- **PrintSpooler** is unchecked by default. Only disable if you don't print or use any "Print to PDF" software.

---

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md). Pull requests welcome for additional safe tweaks. Anything that risks Update, Defender, Store, anti-cheat, or developer toolchain compatibility will be rejected.

---

## License

[MIT](LICENSE).

---

## Disclaimer

This tool modifies system settings, services, and registry keys. It is provided **as is**, without warranty. Although it is designed to be safe and reversible, you should review the modules before running on a system where data loss is unacceptable. The authors are not responsible for any damage, data loss, or downtime resulting from use.
