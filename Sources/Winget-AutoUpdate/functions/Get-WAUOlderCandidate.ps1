<#
.SYNOPSIS
    Lists the source versions between the installed version and the newest candidate.

.DESCRIPTION
    Reads "winget show --versions", which lists versions newest first, and returns
    the versions strictly between the newest candidate and the installed version,
    newest first. Returns nothing when either version is not listed exactly, so WAU
    never offers a version that it cannot place above the installed one.
    Results are cached for the current run.

.PARAMETER Id
    The WinGet package ID.

.PARAMETER Source
    The WinGet source name.

.PARAMETER InstalledVersion
    The installed version reported by "winget upgrade".

.PARAMETER LatestVersion
    The newest available version reported by "winget upgrade".

.OUTPUTS
    String array of versions, newest first.
#>
function Get-WAUOlderCandidate ($Id, $Source, $InstalledVersion, $LatestVersion) {
    if (-not $script:WAUVersionListCache) { $script:WAUVersionListCache = @{} }
    $cacheKey = "$Source|$Id"
    if (-not $script:WAUVersionListCache.ContainsKey($cacheKey)) {
        $lines = @(& $Winget show --id $Id --exact --source $Source --versions --accept-source-agreements --disable-interactivity)
        if ($LASTEXITCODE -ne 0) {
            throw "WinGet could not list the versions of $Source/$Id (exit $LASTEXITCODE)"
        }
        # The column header is localized; the dashed separator line is not.
        $separator = -1
        for ($i = 0; $i -lt $lines.Count; $i++) {
            if ($lines[$i] -match '^\s*-{3,}\s*$') { $separator = $i; break }
        }
        $versions = @(if ($separator -ge 0) { $lines | Select-Object -Skip ($separator + 1) | ForEach-Object { "$_".Trim() } | Where-Object { $_ } })
        $script:WAUVersionListCache[$cacheKey] = $versions
    }
    $versions = $script:WAUVersionListCache[$cacheKey]
    $latest = [array]::IndexOf([string[]]$versions, [string]$LatestVersion)
    $installed = [array]::IndexOf([string[]]$versions, [string]$InstalledVersion)
    if ($latest -lt 0 -or $installed -le $latest) {
        Write-ToLog "$Source/$Id $InstalledVersion -> $LatestVersion has no older candidate to fall back to" 'Gray'
        return
    }
    if ($installed - $latest -gt 1) {
        $versions[($latest + 1)..($installed - 1)]
    }
}
