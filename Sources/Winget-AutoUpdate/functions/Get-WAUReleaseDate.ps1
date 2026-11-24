<#
.SYNOPSIS
    Reads an installer's release date from the WinGet source.

.DESCRIPTION
    Runs "winget show" for one exact version and reads the Release Date field of the
    installer section. The date comes from the package manifest: it is supplied by the
    manifest author and not verified by WinGet. Results are cached for the current run.
    Throws when WinGet cannot resolve the version.

.PARAMETER Id
    The WinGet package ID.

.PARAMETER Source
    The WinGet source name.

.PARAMETER Version
    The exact package version.

.PARAMETER InstallerArguments
    Installer selection options forwarded to "winget show".

.OUTPUTS
    DateTime (UTC midnight) of the release, or no output when the installer has no usable date.
#>
function Get-WAUReleaseDate ($Id, $Source, $Version, [string[]]$InstallerArguments) {
    if (-not $script:WAUReleaseDateCache) { $script:WAUReleaseDateCache = @{} }
    $cacheKey = "$Source|$Id|$Version|$($InstallerArguments -join ' ')"
    if ($script:WAUReleaseDateCache.ContainsKey($cacheKey)) { return $script:WAUReleaseDateCache[$cacheKey] }

    $lines = @(& $Winget show --id $Id --exact --source $Source --version $Version @InstallerArguments --accept-source-agreements --disable-interactivity)
    if ($LASTEXITCODE -ne 0) {
        throw "WinGet could not resolve $Source/$Id $Version (exit $LASTEXITCODE)"
    }
    $labels = Get-WAUInstallerLabelMap
    $releaseDate = $null
    # The installer section follows publisher-supplied descriptions and release notes.
    $header = [array]::LastIndexOf($lines, $labels.ShowLabelInstaller)
    if ($header -ge 0) {
        $field = '^\s+' + [regex]::Escape($labels.ShowLabelInstallerReleaseDate) + '\s*(\d{4}-\d{2}-\d{2})\s*$'
        $styles = [Globalization.DateTimeStyles]'AssumeUniversal, AdjustToUniversal'
        for ($i = $header + 1; $i -lt $lines.Count -and $null -eq $releaseDate; $i++) {
            $date = [datetime]::MinValue
            if ($lines[$i] -match $field -and
                [datetime]::TryParseExact($Matches[1], 'yyyy-MM-dd', [CultureInfo]::InvariantCulture, $styles, [ref]$date)) {
                $releaseDate = $date
            }
        }
    }
    $script:WAUReleaseDateCache[$cacheKey] = $releaseDate
    return $releaseDate
}
