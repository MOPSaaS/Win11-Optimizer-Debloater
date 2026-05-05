# Logger.ps1 - Centralized logging
# Writes to ProgramData log file and (when GUI present) appends to RichTextBox via Dispatcher.

$Script:LogRoot = Join-Path $env:ProgramData 'Win11Optimizer\logs'
$null = New-Item -ItemType Directory -Path $Script:LogRoot -Force -ErrorAction SilentlyContinue
$Script:LogFile = Join-Path $Script:LogRoot ("optimize-{0:yyyyMMdd-HHmmss}.log" -f (Get-Date))
$Script:UIContext = $null

function Set-LoggerUIContext {
    param(
        [Parameter(Mandatory)] $Window,
        [Parameter(Mandatory)] $RichTextBox
    )
    $Script:UIContext = @{ Window = $Window; Box = $RichTextBox }
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
            $ctx.Window.Dispatcher.Invoke([action]{
                $para = New-Object System.Windows.Documents.Paragraph
                $para.Margin = [System.Windows.Thickness]::new(0)
                $run = New-Object System.Windows.Documents.Run($line)
                $run.Foreground = (New-Object System.Windows.Media.BrushConverter).ConvertFromString($color)
                $para.Inlines.Add($run)
                $ctx.Box.Document.Blocks.Add($para)
                $ctx.Box.ScrollToEnd()
            })
        } catch { }
    } else {
        Write-Host $line
    }
}

function Get-LogFilePath { $Script:LogFile }
