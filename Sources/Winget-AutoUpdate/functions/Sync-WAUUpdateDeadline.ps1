<#
.SYNOPSIS
    Keeps deadlines for outdated apps and returns deadlines with an eligible target.
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
