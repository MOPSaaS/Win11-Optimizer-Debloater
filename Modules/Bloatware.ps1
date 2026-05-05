# Bloatware.ps1 - Safe Appx removal (current user only)
# Provisioned packages and developer/system packages are NEVER touched.

function Remove-Bloatware {
    [CmdletBinding()]
    param(
        [bool] $Teams = $true,
        [bool] $Clipchamp = $true,
        [bool] $Weather = $true,
        [bool] $News = $true,
        [bool] $Tips = $true,
        [bool] $GetHelp = $true,
        [bool] $Maps = $true,
        [bool] $People = $true,
        [bool] $MoviesTV = $true,
        [bool] $Cortana = $true,
        [bool] $Xbox = $false
    )

    Write-Log "=== Debloat ===" -Level Info

    $targets = New-Object System.Collections.Generic.List[string]

    if ($Teams)     { $targets.Add('MicrosoftTeams'); $targets.Add('MSTeams') }
    if ($Clipchamp) { $targets.Add('Clipchamp.Clipchamp') }
    if ($Weather)   { $targets.Add('Microsoft.BingWeather') }
    if ($News)      { $targets.Add('Microsoft.BingNews') }
    if ($Tips)      { $targets.Add('Microsoft.Getstarted') }
    if ($GetHelp)   { $targets.Add('Microsoft.GetHelp') }
    if ($Maps)      { $targets.Add('Microsoft.WindowsMaps') }
    if ($People)    { $targets.Add('Microsoft.People') }
    if ($MoviesTV)  { $targets.Add('Microsoft.ZuneVideo') }
    if ($Cortana)   { $targets.Add('Microsoft.549981C3F5F10') }

    if ($Xbox) {
        # Note: Microsoft.GamingServices is INTENTIONALLY excluded -
        # removing it breaks anti-cheat, Game Pass, and many launchers.
        $targets.Add('Microsoft.XboxApp')
        $targets.Add('Microsoft.GamingApp')
        $targets.Add('Microsoft.XboxGameOverlay')
        $targets.Add('Microsoft.XboxSpeechToTextOverlay')
        # Identity provider stays (anti-cheat / sign-in dependency)
    }

    # Hard guard - never touch these even if a future caller adds them
    $protectedGuard = @(
        'Microsoft.GamingServices',
        'Microsoft.WindowsStore',
        'Microsoft.DesktopAppInstaller',
        'Microsoft.VCLibs',
        'Microsoft.NET',
        'Microsoft.UI.Xaml',
        'Microsoft.WindowsCalculator',
        'Microsoft.SecHealthUI',
        'Microsoft.XboxIdentityProvider'
    )

    foreach ($name in $targets) {
        if ($protectedGuard | Where-Object { $name -like "$_*" }) {
            Write-Log "Refusing to remove protected package: $name" -Level Warning
            continue
        }

        $pkgs = Get-AppxPackage -Name $name -ErrorAction SilentlyContinue
        if (-not $pkgs) {
            Write-Log "Not installed: $name" -Level Skip
            continue
        }
        foreach ($pkg in $pkgs) {
            try {
                Backup-AppxRemoval -PackageFullName $pkg.PackageFullName -Family $pkg.PackageFamilyName
                Remove-AppxPackage -Package $pkg.PackageFullName -ErrorAction Stop
                Write-Log "Removed: $($pkg.Name)" -Level Success
            } catch {
                Write-Log "Failed to remove $($pkg.Name): $($_.Exception.Message)" -Level Warning
            }
        }
    }
}
