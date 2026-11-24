<#
.SYNOPSIS
    Keeps only apps with a version past the minimum update age.

.DESCRIPTION
    Runs before apps are added to deadline tracking, so only eligible versions are
    offered. Sets each returned app's AvailableVersion to the eligible version,
    which can be older than the newest candidate (see Get-WAUEligibleUpdate).

.PARAMETER Apps
    App objects from Get-WingetOutdatedApps.

.PARAMETER Source
    The WinGet source name.

.PARAMETER IncludeDeferred
    Return still-outdated apps with an empty target so deadline tracking can retain
    their existing deadline without offering an installation.

.OUTPUTS
    The eligible app objects.
#>
function Select-WAUAgeEligibleApp ($Apps, $Source, [switch]$IncludeDeferred) {
    foreach ($app in $Apps) {
        $mods = @(Test-Mods $app.Id)
        $arguments = if (-not ($mods[1] -or $mods[2])) { $mods[3] }
        $target = Get-WAUEligibleUpdate $app $Source $arguments
        if ($target -and $app.Version -ne $target.Version) {
            $app.AvailableVersion = $target.Version
            $app
        }
        elseif ($IncludeDeferred) {
            $app.AvailableVersion = ''
            $app
        }
    }
}
