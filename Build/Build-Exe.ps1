# Build-Exe.ps1 - Package Win11Optimizer.ps1 to a standalone .exe via PS2EXE.
# PS2EXE wraps the launcher only; modules and XAML are bundled alongside.

[CmdletBinding()]
param(
    [string] $OutputDir = (Join-Path $PSScriptRoot '..\dist')
)

$ErrorActionPreference = 'Stop'

if (-not (Get-Module -ListAvailable -Name ps2exe)) {
    Write-Host "Installing ps2exe..."
    Install-Module ps2exe -Scope CurrentUser -Force
}
Import-Module ps2exe

$root = Resolve-Path (Join-Path $PSScriptRoot '..')
$null = New-Item -ItemType Directory -Path $OutputDir -Force

$src  = Join-Path $root 'Win11Optimizer.ps1'
$exe  = Join-Path $OutputDir 'Win11Optimizer.exe'

Invoke-PS2EXE -InputFile $src -OutputFile $exe `
              -NoConsole `
              -Title 'Win11 Performance Optimizer' `
              -Company 'Local' `
              -Product 'Win11 Performance Optimizer' `
              -RequireAdmin `
              -STA

Copy-Item -Path (Join-Path $root 'MainWindow.xaml') -Destination $OutputDir -Force
Copy-Item -Path (Join-Path $root 'Modules')         -Destination $OutputDir -Recurse -Force

Write-Host "`nBuild complete: $exe"
Write-Host "Distribute the entire '$OutputDir' folder (exe + Modules + xaml)."
