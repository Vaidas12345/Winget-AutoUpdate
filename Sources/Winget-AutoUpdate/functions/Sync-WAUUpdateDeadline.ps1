<#
.SYNOPSIS
    Keeps deadlines for outdated apps and returns deadlines with an eligible target.

.DESCRIPTION
    Synchronizes deadline entries with the current machine and user inventory.
    Removes entries for apps omitted from Apps, including satisfied version pins.
    Apps waiting for the minimum age retain their existing deadlines. Only apps
    with an eligible target receive a new or updated entry and appear in the output.

.PARAMETER Apps
    Outdated app objects (machine inventory and the user-context CSV). Apps waiting
    for the minimum age have an empty AvailableVersion
    (Select-WAUAgeEligibleApp -IncludeDeferred).

.PARAMETER DeadlineDays
    Number of days from first detection until the update is forced.

.OUTPUTS
    Deadline entries (see Get-UpdateDeadlines) of the apps with an eligible target.
#>
function Sync-WAUUpdateDeadline ($Apps, $DeadlineDays) {
    # Deferred entries can come from machine inventory or the user-context CSV.
    $null = Get-UpdateDeadlines -OutdatedApps $Apps
    $offered = @($Apps | Where-Object { $_.AvailableVersion })
    foreach ($app in $offered) {
        Set-UpdateDeadline -App $app -DeadlineDays $DeadlineDays
    }
    Get-UpdateDeadlines | Where-Object { $offered.Id -contains $_.AppId }
}
