<#
.SYNOPSIS
    Tests whether one exact package version has passed the minimum update age.

.DESCRIPTION
    An exact source|ID|version entry in the immediate update exceptions passes at once.
    Otherwise the age counts from the installer release date in the WinGet source,
    or from the first observation of that version when the installer has no date.
    Throws when the source lookup fails, so the caller defers the update.

.PARAMETER Id
    The WinGet package ID.

.PARAMETER Source
    The WinGet source name.

.PARAMETER Version
    The exact package version to test.

.PARAMETER InstallerArguments
    Installer selection options (architecture, locale, scope, installer type)
    forwarded to the release date lookup.

.PARAMETER Days
    The minimum age in days.

.PARAMETER Now
    The current UTC time.

.OUTPUTS
    Boolean: $true when the version is eligible.
#>
function Test-WAUReleaseAge ($Id, $Source, $Version, [string[]]$InstallerArguments, [int]$Days, [datetime]$Now) {
    $identity = "$Source|$Id|$Version"
    if ($WAUConfig.WAU_ImmediateUpdateExceptions -ccontains $identity) {
        Write-ToLog "Release age exception for $identity" 'Yellow'
        return $true
    }
    $start = Get-WAUReleaseDate $Id $Source $Version $InstallerArguments
    $basis = 'installer release date'
    if ($null -eq $start) {
        $start = Get-WAUFirstSeenUtc $Source $Id $Version $Now
        $basis = 'first observation'
    }
    $eligible = $start.AddDays($Days)
    if ($Now -lt $eligible) {
        Write-ToLog "Deferring $identity until $($eligible.ToString('u')) ($basis)" 'Gray'
        return $false
    }
    Write-ToLog "$identity eligible since $($eligible.ToString('u')) ($basis)" 'Gray'
    return $true
}
