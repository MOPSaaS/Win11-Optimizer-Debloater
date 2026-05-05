# Win11Optimizer — Project Context

> Context document for future Claude sessions. Read this first before making changes.

## What this is

**Win11 Performance Optimizer (Safe Mode)** — a Windows 11 (24H2 / 25H2) optimization utility with a WPF GUI and PowerShell backend. The defining trait is **safety**: every change is captured to a JSON snapshot before being applied, and the GUI's **Revert** button replays the snapshot in reverse.

Repository: <https://github.com/MOPSaaS/Win11-Optimizer-Debloater>
Local path: `F:\Claude Workspaces\Chi\Win11Optimizer`
Initial commit: `4f34671`

Created on a whim during a session that was scoped to a different project (the parent `F:\Claude Workspaces\Chi\Claude` workspace). The user later copied the files out into this dedicated folder so it could have its own session/memory going forward.

## Design principles (non-negotiable)

These exist because the user runs this on their **primary machine**. Don't soften them.

1. **Never break Windows Update, Defender, Microsoft Store, GPU drivers, anti-cheat, or developer toolchains.** A hard-coded protected list in `Modules/Bloatware.ps1` enforces this even if a future caller passes a bad name.
2. **Every state mutation backs up first.** Every `Set-RegistryValueSafe` / `Disable-ServiceSafe` / Appx removal / power plan change writes to the active snapshot under `C:\ProgramData\Win11Optimizer\backups\backup-<timestamp>.json` *before* the mutation.
3. **Idempotent.** Re-running `Optimize Now` should log everything as `Skip`. The safe helpers compare current vs target state and short-circuit when already in the target state.
4. **Telemetry stays at `1` (Required), never `0`.** `0` is only honored on Enterprise SKUs; on Pro/Home it reduces Defender cloud protection. This is a frequent "fix it" suggestion that needs to be rejected on sight.
5. **Provisioned Appx packages are not touched.** Only per-user installs are removed (so a brand-new user account on the same machine still sees the apps). Touching provisioned packages requires DISM and risks Windows Update integrity.
6. **No emojis in the UI.** The user pointed out earlier that emojis in WPF render inconsistently across Windows fonts. Plain text only in `MainWindow.xaml`. (README is also emoji-free at the user's preference.)

## Architecture quick map

```
Launch.bat                    → self-elevates, invokes Win11Optimizer.ps1
Win11Optimizer.ps1            → loads MainWindow.xaml, dot-sources Modules/*.ps1,
                                wires button handlers, dispatches to a worker runspace
MainWindow.xaml               → entire UI (5 tabs + Log), Tokyo Night-themed
Modules/Logger.ps1            → Write-Log, file + Dispatcher-marshalled GUI log
Modules/Backup.ps1            → snapshot writer (services/registry/appx/power/features)
Modules/Common.ps1            → Set-RegistryValueSafe, Disable-ServiceSafe, Test-IsAdmin
Modules/StateDetector.ps1     → Get-SystemOptimizationState (probes current state for UI)
Modules/Performance.ps1       → Optimize-Performance
Modules/Bloatware.ps1         → Remove-Bloatware (with protected-package guard)
Modules/Gaming.ps1            → Apply-GamingTweaks
Modules/Privacy.ps1           → Apply-PrivacySettings
Modules/DevTools.ps1          → Apply-DevToolsTweaks (only enables, never removes)
Modules/Restore.ps1           → Restore-SystemDefaults (replays snapshot in reverse)
Build-Release.ps1             → standalone EXE builder: zips payload, compiles C# launcher via csc.exe
                                outputs Win11Optimizer.exe to project root (no extra folders needed)
.github/workflows/ci.yml      → parse + XAML + PSScriptAnalyzer
```

## Recent Changes Summary

- **Directory Normalization**: Moved all project files from nested subdirectories to the root for better workspace management.
- **State Detection Engine**: Integrated `StateDetector.ps1` to probe system state on launch and after optimization.
- **UI Enhancements**: Added [Done] indicators and auto-dimming for already-applied tweaks in `MainWindow.xaml`.
- **Advanced Tweaks**:
    - **Gaming**: Nagle's Algorithm disablement (`TCPNoDelay`) across all interfaces.
    - **Privacy**: Windows Update Delivery Optimization (P2P) disablement.
    - **Privacy**: Microsoft Edge background telemetry and update task disablement.
    - **Debloat**: Full OneDrive uninstallation and Explorer sidebar removal.
- **Stability**: Hardened `Win11Optimizer.ps1` with better error handling and debug logging (`startup_debug.log`).


### Threading model

UI calls `Invoke-OptimizerWork` which:
1. Disables buttons, sets the progress bar indeterminate.
2. Spins up an STA runspace, hands it `($Window, $UILog, $ModuleFiles, $Action, $Options)` via `AddArgument`.
3. Worker dot-sources its own copies of the modules and calls `Set-LoggerUIContext` so logging marshals back to the UI thread via `Window.Dispatcher.Invoke`.
4. A `DispatcherTimer` polls `IsCompleted` every 250 ms; on completion it disposes the runspace and re-enables buttons.

`$using:` does **not** work with `[PowerShell]::Create()` — that was the reason for the `AddArgument` pattern. Don't switch to `$using:` in a future refactor.

Hashtable splatting in PowerShell needs a real variable: `$p = $opts.Performance; Optimize-Performance @p`. You cannot splat with a property path like `@($opts.Performance)` — that's array splat, which silently passes the hashtable as a single positional argument and hits `Test-Path` errors. The worker script in `Win11Optimizer.ps1` follows the correct pattern; preserve it.

## Storage locations

| Data | Path |
| --- | --- |
| Logs | `C:\ProgramData\Win11Optimizer\logs\optimize-<timestamp>.log` |
| Snapshots | `C:\ProgramData\Win11Optimizer\backups\backup-<timestamp>.json` |

These are intentionally **outside** the install directory and **outside** the repo. Inno Setup uninstaller leaves them in place so revert is always possible after uninstall. Don't move them.

## CI

`.github/workflows/ci.yml` runs on every push/PR to `main`:

1. Parse-check every `.ps1` / `.psm1`.
2. Validate `MainWindow.xaml` loads via `XamlReader`.
3. PSScriptAnalyzer at Warning+ severity, excluding:
   - `PSAvoidUsingWriteHost` (the worker runspace path uses Write-Host as a no-GUI fallback)
   - `PSUseShouldProcessForStateChangingFunctions` (would be noise — the UI is the consent layer)
   - `PSUseApprovedVerbs` (the project deliberately uses `Apply-`, `Optimize-` for readability)

Failures fail the build. Don't add new excluded rules without pushing a justification through CONTRIBUTING.md.

## Known caveats / quirks

- **HAGS** and **Optional Features** require a reboot before taking effect. The log says so; don't add an auto-reboot prompt.
- **Teams Personal** sometimes returns via Microsoft Store auto-update. Acceptable — running the optimizer again removes it; the snapshot still restores it.
- **PrintSpooler** is unchecked by default on the Performance tab. Don't change that default — too many users rely on "Print to PDF" / "OneNote Printer" virtual printers.
- **Build script**: `Build-Release.ps1` in the project root is the only build script. The old `Build/` folder (ps2exe + Inno Setup) has been deleted. Don't recreate it. The exe outputs to the project root, not a `dist/` subfolder.

## How to verify a change without breaking the host

The user's machine **is** the production environment. Smoke-test on a Windows 11 VM:

1. `Optimize Now` — completes, log shows operations.
2. Inspect `C:\ProgramData\Win11Optimizer\backups\backup-*.json` — confirms expected entries captured.
3. `Revert Changes` — system returns to original state.
4. `Optimize Now` again — every line logs as `Skip` (idempotency check).

## Coding conventions

- 4-space indent, CRLF on `.ps1` / `.xaml` / `.bat`, LF on docs/JSON/YAML (enforced by `.gitattributes` + `.editorconfig`).
- Verb-Noun function names. The deliberately non-approved verbs are `Apply-`, `Optimize-`, `Remove-Bloatware`, `Restore-`. PSScriptAnalyzer is configured to allow these.
- Every state-changing operation calls `Backup-*` first.
- Every action calls `Write-Log` at the right level (`Info` / `Success` / `Skip` / `Warning` / `Error`). Color is mapped in `Modules/Logger.ps1`.
- Don't write directly to the registry — use `Set-RegistryValueSafe` (idempotent + auto-backup).
- Don't write directly to services — use `Disable-ServiceSafe`.

## Where to read first when picking this back up

1. `README.md` — public-facing overview, architecture, packaging, manual undo.
2. `CONTRIBUTING.md` — hard rules on what PRs will be rejected.
3. `Modules/Common.ps1` — the helpers that enforce idempotency + backup. Most operations are 2-3 lines once you use these.
4. `Win11Optimizer.ps1` — the runspace + dispatcher pattern. Touch this carefully.
5. `TODO.md` — what's queued.
