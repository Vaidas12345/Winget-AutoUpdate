<#
.SYNOPSIS
    Reconciles queued updates with this context's live, eligible candidates.

.DESCRIPTION
    A user may accept a deadline prompt after the source or installed version changed.
    Keeps a queued app only when it is still outdated, still allowed by the app lists,
    and its queued version is still the eligible version. Logs why each other app
    was removed from the queue.

.PARAMETER Apps
    The queued app objects (from pending-updates.json or user-context-update.json).

.PARAMETER Source
    The WinGet source name.

.OUTPUTS
    The live app objects to update.
#>
function Select-WAUCurrentQueuedApp ($Apps, $Source) {
    if (-not $Apps) { return }
    $offered = @(Get-WingetOutdatedApps -src $Source | Where-Object { $_.Id -and $Apps.Id -contains $_.Id })
    $live = $offered
    if ($IsSystem -or $WAUConfig.WAU_BypassListForUsers -ne 1) {
        $allowList = $WAUConfig.WAU_UseWhiteList -eq 1
        $patterns = if ($allowList) { Get-IncludedApps } else { Get-ExcludedApps }
        $live = @($live | Where-Object {
            $id = $_.Id
            $matchesList = $patterns -contains $id -or [bool]($patterns | Where-Object { $_ -and $id -like $_ })
            $matchesList -eq $allowList
        })
    }
    $eligible = @(Select-WAUAgeEligibleApp $live $Source)
    foreach ($queued in $Apps) {
        $match = $eligible | Where-Object { $_.Id -eq $queued.Id } | Select-Object -First 1
        if ($match -and $match.AvailableVersion -ceq $queued.AvailableVersion) {
            $match
            continue
        }
        $reason = if (-not ($offered | Where-Object { $_.Id -eq $queued.Id })) { 'no update is offered any more' }
        elseif (-not ($live | Where-Object { $_.Id -eq $queued.Id })) { 'excluded by the app list' }
        elseif (-not $match) { 'no version has passed the minimum update age' }
        else { "the eligible version is now $($match.AvailableVersion)" }
        Write-ToLog "Removed $($queued.Id) $($queued.AvailableVersion) from the update queue: $reason" 'Yellow'
    }
}
