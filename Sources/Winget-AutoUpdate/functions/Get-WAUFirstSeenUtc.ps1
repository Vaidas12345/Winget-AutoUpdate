<#
.SYNOPSIS
    Returns when WAU first observed a package version, recording it on first call.

.DESCRIPTION
    Used as the start of the minimum update age when the installer has no usable
    release date. Machine observations are kept in HKLM and per-user observations
    in that user's HKCU, under SOFTWARE\Romanitho\Winget-AutoUpdate\ReleaseAge.
    A QWORD is a single atomic value. Concurrent first observations can only differ
    by the time between scans; an observation of another version uses another value.
    Clear-WAUReleaseAgeState removes entries of apps that are no longer outdated.

.PARAMETER Source
    The WinGet source name.

.PARAMETER Id
    The WinGet package ID.

.PARAMETER Version
    The exact package version.

.PARAMETER Now
    The current UTC time, recorded when the version has not been observed before.

.OUTPUTS
    DateTime (UTC) of the first observation.
#>
function Get-WAUFirstSeenUtc ($Source, $Id, $Version, [datetime]$Now) {
    $hive = if ($IsSystem) { [Microsoft.Win32.Registry]::LocalMachine } else { [Microsoft.Win32.Registry]::CurrentUser }
    $path = 'SOFTWARE\Romanitho\Winget-AutoUpdate\ReleaseAge\' + [uri]::EscapeDataString($Source) + '\' + [uri]::EscapeDataString($Id)
    $key = $hive.CreateSubKey($path)
    try {
        $name = [uri]::EscapeDataString($Version)
        $ticks = $key.GetValue($name)
        if ($ticks -is [long] -and $ticks -gt 0 -and $ticks -le [datetime]::MaxValue.Ticks) {
            return [datetime]::new($ticks, [DateTimeKind]::Utc)
        }
        $key.SetValue($name, $Now.Ticks, [Microsoft.Win32.RegistryValueKind]::QWord)
        return $Now
    }
    finally { $key.Dispose() }
}
