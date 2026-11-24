<#
.SYNOPSIS
    Checks an installed version against the release selected by the minimum-age policy.

.DESCRIPTION
    Numeric releases can have additional dotted build components in installed
    inventory, for example 8.0.0.137 for release 8.0.0. Other versions match in full.

.PARAMETER InstalledVersion
    Version reported by WinGet for the installed package.

.PARAMETER ReleaseVersion
    Release selected from the source or specified in an arguments mod.

.OUTPUTS
    Boolean indicating whether the installed version matches the release.
#>
function Test-WAUInstalledRelease ([string]$InstalledVersion, [string]$ReleaseVersion) {
    if ([string]::IsNullOrEmpty($InstalledVersion) -or [string]::IsNullOrEmpty($ReleaseVersion)) { return $false }
    if ($InstalledVersion.Equals($ReleaseVersion, [StringComparison]::OrdinalIgnoreCase)) { return $true }
    return $InstalledVersion.StartsWith("$ReleaseVersion.", [StringComparison]::Ordinal) -and
        $InstalledVersion -match '^[0-9]+(?:\.[0-9]+)+$'
}
