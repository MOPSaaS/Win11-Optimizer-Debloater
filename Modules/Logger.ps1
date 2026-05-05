# Logger.ps1 - Centralized logging
# Writes to ProgramData log file and (when GUI present) appends to RichTextBox via Dispatcher.

$Script:LogFile = $null
$Script:UIContext = $null

function Initialize-Logger {
    param([string]$BasePath)

    $root = if ($BasePath) { Join-Path $BasePath "logs" } else { Join-Path $env:ProgramData 'Win11Optimizer\logs' }
    try { $null = New-Item -ItemType Directory -Path $root -Force -ErrorAction SilentlyContinue } catch {}
    
    $Script:LogFile = Join-Path $root ("optimize-{0:yyyyMMdd-HHmmss}.log" -f (Get-Date))
}

# Default initialization (can be overridden by Initialize-Logger later)
Initialize-Logger
$Script:UIContext = $null

function Set-LoggerUIContext {
    param(
        [Parameter(Mandatory)] $UIContext
    )
    $Script:UIContext = $UIContext
}

function Write-Log {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)] [string] $Message,
        [ValidateSet('Info', 'Success', 'Warning', 'Error', 'Skip')] [string] $Level = 'Info'
    )

    $stamp = Get-Date -Format 'HH:mm:ss'
    $line  = "[$stamp][$Level] $Message"

    try { Add-Content -Path $Script:LogFile -Value $line -Encoding utf8 } catch { }

    $color = switch ($Level) {
        'Success' { '#9ECE6A' }
        'Warning' { '#E0AF68' }
        'Error'   { '#F7768E' }
        'Skip'    { '#9AA5CE' }
        default   { '#C0CAF5' }
    }

    if ($Script:UIContext) {
        $ctx = $Script:UIContext
        try {
            if ($null -ne $ctx['Window'] -and $null -ne $ctx['Box']) {
                $LogAction = {
                    $para = New-Object System.Windows.Documents.Paragraph
                    $para.Margin = [System.Windows.Thickness]::new(0)
                    $run = New-Object System.Windows.Documents.Run($line)
                    $run.Foreground = (New-Object System.Windows.Media.BrushConverter).ConvertFromString($color)
                    $para.Inlines.Add($run)
                    $ctx['Box'].Document.Blocks.Add($para)
                    $ctx['Box'].ScrollToEnd()
                }

                if ($ctx['Window'].Dispatcher.CheckAccess()) {
                    & $LogAction
                } else {
                    $ctx['Window'].Dispatcher.Invoke($LogAction)
                }
            }
        } catch { 
            Write-Host "Logger error: $($_.Exception.Message)"
        }
    } else {
        Write-Host $line
    }
}

function Get-LogFilePath { $Script:LogFile }
