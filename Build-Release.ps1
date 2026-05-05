# Build-Release.ps1
# Compiles the Win11 Optimizer into a standalone C# EXE with embedded payload.

$ProjectDir = $PSScriptRoot
$AssetsDir = Join-Path $ProjectDir "Assets"
if (-not (Test-Path $AssetsDir)) { New-Item $AssetsDir -ItemType Directory | Out-Null }

$PngFile = Join-Path $AssetsDir "logo.png"
$IcoFile = Join-Path $AssetsDir "icon.ico"
$ZipFile = Join-Path $AssetsDir "payload.zip"
$CsFile  = Join-Path $AssetsDir "Launcher.cs"
$ExeFile = Join-Path $ProjectDir "Win11Optimizer.exe"

Write-Host "1. Generating icon..." -ForegroundColor Cyan
if (Test-Path $PngFile) {
    # Convert PNG to ICO using System.Drawing
    Add-Type -AssemblyName System.Drawing
    $img = [System.Drawing.Image]::FromFile($PngFile)
    $fs = New-Object System.IO.FileStream($IcoFile, [System.IO.FileMode]::Create)
    $icon = [System.Drawing.Icon]::FromHandle((New-Object System.Drawing.Bitmap($img, 256, 256)).GetHicon())
    $icon.Save($fs)
    $fs.Close()
    $img.Dispose()
    Write-Host "   Created icon.ico" -ForegroundColor Green
} else {
    Write-Host "   logo.png not found, skipping icon generation." -ForegroundColor Yellow
}

Write-Host "2. Zipping payload..." -ForegroundColor Cyan
if (Test-Path $ZipFile) { Remove-Item $ZipFile -Force }

# Create a staging folder to ensure we only zip what we need
$StageDir = Join-Path $AssetsDir "Stage"
if (Test-Path $StageDir) { Remove-Item $StageDir -Recurse -Force }
New-Item $StageDir -ItemType Directory | Out-Null

$filesToZip = Get-ChildItem -Path $ProjectDir -Exclude ".git", "Assets", "*.exe", "*.zip", "*.log", "sync_log.txt", "copy_log.txt"
foreach ($f in $filesToZip) {
    Copy-Item -Path $f.FullName -Destination $StageDir -Recurse -Force
}

Compress-Archive -Path "$StageDir\*" -DestinationPath $ZipFile -Force
Remove-Item $StageDir -Recurse -Force

$zipSize = (Get-Item $ZipFile).Length
Write-Host "   Created payload.zip ($($zipSize) bytes)" -ForegroundColor Green

Write-Host "3. Generating C# Launcher code..." -ForegroundColor Cyan
$launcherCode = @"
using System;
using System.Diagnostics;
using System.IO;
using System.Reflection;
using System.IO.Compression;
using System.Threading;

namespace Win11Optimizer {
    class Program {
        [STAThread]
        static void Main(string[] args) {
            string tempDir = Path.Combine(Path.GetTempPath(), "Win11Optimizer_" + Guid.NewGuid().ToString().Substring(0,8));
            Directory.CreateDirectory(tempDir);
            try {
using (Stream stream = Assembly.GetExecutingAssembly().GetManifestResourceStream("payload.zip")) {
                    if (stream == null) throw new Exception("Embedded payload not found in resources!");
                    using (FileStream fileStream = new FileStream(Path.Combine(tempDir, "payload.zip"), FileMode.Create)) {
                        stream.CopyTo(fileStream);
                    }
                }
                ZipFile.ExtractToDirectory(Path.Combine(tempDir, "payload.zip"), tempDir);
                
                string ps1Path = Path.Combine(tempDir, "Win11Optimizer.ps1");
                if (!File.Exists(ps1Path)) throw new Exception("Controller script not found after extraction!");

                ProcessStartInfo psi = new ProcessStartInfo {
                    FileName = "powershell.exe",
                    Arguments = "-NoProfile -ExecutionPolicy Bypass -File \"" + ps1Path + "\"",
                    UseShellExecute = false,
                    CreateNoWindow = false
                };
                Process p = Process.Start(psi);
                p.WaitForExit();
            }
            catch (Exception ex) {
                System.Windows.Forms.MessageBox.Show("Fatal Launcher Error:\n" + ex.Message + "\n\nStack:\n" + ex.StackTrace, "Win11 Optimizer - Error", System.Windows.Forms.MessageBoxButtons.OK, System.Windows.Forms.MessageBoxIcon.Error);
            }
            finally {
                try {
                    // Try to clean up after closing
                    Directory.Delete(tempDir, true);
                } catch { }
            }
        }
    }
}
"@
Set-Content -Path $CsFile -Value $launcherCode

Write-Host "4. Compiling EXE..." -ForegroundColor Cyan
# Find csc.exe
$csc = "$env:WINDIR\Microsoft.NET\Framework64\v4.0.30319\csc.exe"
if (-not (Test-Path $csc)) {
    Write-Host "   Error: csc.exe not found!" -ForegroundColor Red
    exit
}

$compileArgs = @(
    "/nologo",
    "/target:winexe",
    "/out:`"$ExeFile`"",
    "/res:`"$ZipFile`",payload.zip",
    "/reference:System.IO.Compression.FileSystem.dll",
    "/reference:System.Windows.Forms.dll",
    "`"$CsFile`""
)

if (Test-Path $IcoFile) {
    $compileArgs += "/win32icon:`"$IcoFile`""
}

$proc = Start-Process -FilePath $csc -ArgumentList $compileArgs -Wait -NoNewWindow -PassThru
if ($proc.ExitCode -eq 0) {
    Write-Host "   Success! Win11Optimizer.exe has been built." -ForegroundColor Green
} else {
    Write-Host "   Failed to compile EXE." -ForegroundColor Red
}

# Cleanup
Remove-Item $ZipFile -ErrorAction SilentlyContinue
Remove-Item $CsFile -ErrorAction SilentlyContinue
