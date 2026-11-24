<#
.SYNOPSIS
    Verifies application installation at expected version.

.PARAMETER AppName
    WinGet package identifier.

.PARAMETER AppVer
    Expected version prefix.

.PARAMETER src
    The WinGet source to query (e.g. "winget", "msstore"). Defaults to
    "winget".

.PARAMETER MatchRelease
    Use the minimum-age policy's release comparison when confirming a selected target.

.OUTPUTS
    Boolean: True if installed at version.
#>
Function Confirm-Installation ($AppName, $AppVer, $src = "winget", [switch]$MatchRelease) {
    if ([string]::IsNullOrWhiteSpace($src)) {
        $src = "winget"
    }
    else {
        $src = $src.Trim()
    }

    $JsonFile = "$env:TEMP\InstalledApps.json"
    & $Winget export -s $src -o $JsonFile --include-versions | Out-Null

    $Packages = (Get-Content $JsonFile -Raw | ConvertFrom-Json).Sources.Packages
    $installed = $Packages | Where-Object { $_.PackageIdentifier -eq $AppName }
    if ($MatchRelease) {
        return [bool]($installed | Where-Object { Test-WAUInstalledRelease $_.Version $AppVer })
    }
    return [bool]($installed | Where-Object { $_.Version -like "$AppVer*" })
}
