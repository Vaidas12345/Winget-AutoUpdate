<#
.SYNOPSIS
    Selects the version WAU may install under the minimum update age policy.

.DESCRIPTION
    Checks the newest candidate, or the version pinned with --version by an arguments
    mod. When the newest candidate is still too new, falls back to the newest version
    between it and the installed version that has passed the minimum age, so an app
    that releases more often than the configured delay still receives updates.
    A pinned version has no fallback. Any doubt about the target defers the update.

.PARAMETER App
    PSCustomObject with Id, Version and AvailableVersion.

.PARAMETER Source
    The WinGet source name.

.PARAMETER ModArguments
    The arguments mod content, or $null when an override or custom mod replaces it.

.PARAMETER Now
    The current UTC time.

.OUTPUTS
    PSCustomObject with Version and HasVersionArgument, or no output when WAU should defer.
    When the installation already satisfies a mod pin, Version contains the installed version.
#>
function Get-WAUEligibleUpdate ($App, $Source, [string]$ModArguments, [datetime]$Now = [datetime]::UtcNow) {
    # Upper bound on extra "winget show" lookups for the fallback, per app and run.
    $maxFallbackLookups = 10
    $version = $App.AvailableVersion
    $hasVersionArgument = $false
    $installerArgs = @()
    $tokens = @(ConvertTo-WingetArgumentArray $ModArguments)
    try {
        $days = [int]$WAUConfig.WAU_MinimumUpdateAgeDays
        if ($days -lt 1 -or $days -gt 365) { throw "Expected a minimum age of 1 to 365 days" }
        for ($i = 0; $i -lt $tokens.Count; $i++) {
            $option, $value = $tokens[$i] -split '=', 2
            if ($option -in '-s', '--source', '--id', '-m', '--manifest', '--all', '-r', '--recurse', '-q', '--query', '--moniker', '--name') {
                throw "Cannot apply release age with an additional package selector ($option)"
            }
            # A quoted installer argument can itself look like a WinGet version switch.
            if ($option -in '--custom', '--override', '-l', '--location', '-o', '--log', '--header', '--authentication-mode', '--authentication-account') {
                if ($null -eq $value) { $i++ }
                continue
            }
            if ($option -notin '-v', '--version', '-a', '--architecture', '--locale', '--scope', '--installer-type') { continue }
            if ($null -eq $value) { $value = $tokens[++$i] }
            if ([string]::IsNullOrWhiteSpace($value) -or $value.StartsWith('-')) { throw "Missing value for $option" }
            if ($option -in '-v', '--version') {
                if ($hasVersionArgument) { throw 'Multiple version arguments' }
                $version = $value
                $hasVersionArgument = $true
            }
            else { $installerArgs += $option, $value }
        }
        if ([string]::IsNullOrWhiteSpace($version) -or $version -in 'Latest', 'Unknown' -or $version -match '[*?|]') {
            throw "Cannot identify an exact version ($version)"
        }
        if ($hasVersionArgument -and (Test-WAUInstalledRelease $App.Version $version)) {
            Write-ToLog "$($App.Id) $($App.Version) already matches the mod pin $version" 'Gray'
            return [PSCustomObject]@{ Version = $App.Version; HasVersionArgument = $true }
        }
        if (Test-WAUReleaseAge $App.Id $Source $version $installerArgs $days $Now) {
            return [PSCustomObject]@{ Version = $version; HasVersionArgument = $hasVersionArgument }
        }
        if ($hasVersionArgument) { return }

        $older = @(Get-WAUOlderCandidate $App.Id $Source $App.Version $version | Where-Object { $_ -notin 'Latest', 'Unknown' -and $_ -notmatch '[*?|]' })
        foreach ($candidate in ($older | Select-Object -First $maxFallbackLookups)) {
            if (Test-WAUReleaseAge $App.Id $Source $candidate $installerArgs $days $Now) {
                Write-ToLog "$Source|$($App.Id): $candidate is the newest version past the minimum age ($version is too new)" 'Yellow'
                return [PSCustomObject]@{ Version = $candidate; HasVersionArgument = $false }
            }
        }
        if ($older.Count -gt $maxFallbackLookups) {
            Write-ToLog "$Source|$($App.Id): checked the $maxFallbackLookups newest of $($older.Count) older versions" 'Gray'
        }
    }
    catch {
        Write-ToLog "Deferring $Source/$($App.Id) $version - $($_.Exception.Message)" 'Yellow'
    }
}
