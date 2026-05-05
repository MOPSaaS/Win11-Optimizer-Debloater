# Contributing

Thanks for your interest in improving Win11 Performance Optimizer. The project's value comes from being **safe**, so contributions are evaluated against that bar first.

## Hard rules

A pull request will be rejected if it:

- Removes or disables Windows Update services
- Removes or disables Windows Defender services or `Microsoft.SecHealthUI`
- Removes Microsoft Store, Desktop App Installer, or any runtime (VC++, .NET, UI.Xaml, VCLibs)
- Disables Gaming Services or `Microsoft.XboxIdentityProvider` (anti-cheat dependency)
- Sets `AllowTelemetry` to `0` (only honored on Enterprise; reduces Defender cloud protection on Pro/Home)
- Touches provisioned Appx packages via DISM
- Bypasses the snapshot/backup system

## Style

- Verb-Noun PowerShell function names (`Apply-`, `Disable-`, `Optimize-`, `Restore-`).
- Every state-changing operation must call the matching `Backup-*` helper first.
- Use `Set-RegistryValueSafe` and `Disable-ServiceSafe` from `Modules/Common.ps1` rather than writing directly — they handle idempotency and backup.
- Log every action with `Write-Log` at the appropriate level (`Info`, `Success`, `Skip`, `Warning`, `Error`).
- Indent: 4 spaces. CRLF line endings on `.ps1`/`.psm1`/`.xaml`/`.bat`. See `.editorconfig`.

## Adding a new tweak

1. Pick the right module (or create one in `Modules/` if it's a new category).
2. Add a parameter to the module function with a sensible default.
3. Capture state via the appropriate `Backup-*` call **before** mutating.
4. Use the safe helpers — they're idempotent.
5. Add a checkbox in `MainWindow.xaml` and wire it through `Get-OptionsFromUI` in `Win11Optimizer.ps1`.
6. Update `CHANGELOG.md` under `[Unreleased]`.
7. Run the local checks below before pushing.

## Local checks

```powershell
# Parse-check every script
Get-ChildItem -Recurse -Include *.ps1,*.psm1 | ForEach-Object {
    $errors = $null
    [System.Management.Automation.Language.Parser]::ParseFile($_.FullName, [ref]$null, [ref]$errors) | Out-Null
    if ($errors) { Write-Host "FAIL $($_.Name)"; $errors }
}

# PSScriptAnalyzer
Install-Module PSScriptAnalyzer -Scope CurrentUser -Force
Invoke-ScriptAnalyzer -Path . -Recurse -Severity Warning
```

CI runs both of these on every PR.

## Commit messages

Conventional Commits style is encouraged:

```
feat(performance): disable WSearch as opt-in tweak
fix(restore): handle missing PackageFullName field gracefully
docs: clarify HAGS reboot requirement
```

## Testing

There is no automated functional test of system mutations (it would require a sacrificial VM per change). Smoke-test on a Windows 11 VM before submitting a PR that touches a module under `Modules/`. Confirm:

1. `Optimize Now` completes without errors in the GUI log.
2. Snapshot JSON contains the expected entries under `ProgramData\Win11Optimizer\backups`.
3. `Revert Changes` restores the original state.
4. Re-running `Optimize Now` is a no-op (everything logs as `Skip`).

## Reporting issues

Open a GitHub issue with:

- Windows edition + version (`winver`)
- A copy of the relevant log file from `C:\ProgramData\Win11Optimizer\logs`
- Reproduction steps
