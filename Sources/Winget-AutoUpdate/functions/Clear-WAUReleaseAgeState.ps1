<#
.SYNOPSIS
    Removes first-observation records that WAU no longer needs.

.DESCRIPTION
    When the minimum update age is off, removes all records of this context
    (HKLM for SYSTEM, HKCU for a user). Otherwise removes the records of apps
    that are no longer in this context's outdated list for the source.
    Does nothing when the outdated list could not be read.

.PARAMETER Outdated
    The result of Get-WingetOutdatedApps for this context.

.PARAMETER Source
    The WinGet source name.
#>
function Clear-WAUReleaseAgeState ($Outdated, $Source) {
    $hive = if ($IsSystem) { [Microsoft.Win32.Registry]::LocalMachine } else { [Microsoft.Win32.Registry]::CurrentUser }
    $root = 'SOFTWARE\Romanitho\Winget-AutoUpdate\ReleaseAge'
    if (-not $WAUConfig.WAU_MinimumUpdateAgeDays) {
        $hive.DeleteSubKeyTree($root, $false)
        return
    }
    # Get-WingetOutdatedApps returns a message string when nothing could be parsed.
    if ($Outdated -is [string]) { return }
    $key = $hive.OpenSubKey($root + '\' + [uri]::EscapeDataString($Source), $true)
    if (-not $key) { return }
    try {
        $ids = @($Outdated | Where-Object { $_.Id } | ForEach-Object { [uri]::EscapeDataString($_.Id) })
        foreach ($name in $key.GetSubKeyNames()) {
            if ($ids -notcontains $name) {
                $key.DeleteSubKeyTree($name, $false)
                Write-ToLog "Release age records removed (no longer outdated): $([uri]::UnescapeDataString($name))" 'Gray'
            }
        }
    }
    finally { $key.Dispose() }
}
