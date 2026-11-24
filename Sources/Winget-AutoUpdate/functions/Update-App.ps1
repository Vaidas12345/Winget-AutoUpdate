<#
.SYNOPSIS
    Updates a single application using WinGet.

.DESCRIPTION
    Performs the complete update process: notification, pre-install mods,
    WinGet upgrade/install with retry logic, post-install mods, result notification.

.PARAMETER app
    PSCustomObject with Name, Id, Version, AvailableVersion properties.

.PARAMETER src
    The WinGet source to use (e.g. 'winget', 'msstore'). Defaults to 'winget'.
#>
Function Update-App ($app, $src = "winget") {
    if ([string]::IsNullOrWhiteSpace($src)) {
        $src = "winget"
    }
    else {
        $src = $src.Trim()
    }

    # Helper function to build winget command parameters
    function Get-WingetParams ($Command, $ModsOverride, $ModsCustom, $ModsArguments) {
        $params = @($Command, "--id", $app.Id, "-e", "--accept-package-agreements", "--accept-source-agreements", "-s", $src)
        if ($ageTarget -and -not $ageTarget.HasVersionArgument) { $params += '--version', $ageTarget.Version }
        if ($Command -eq "install") { $params += "--force" }

        if ($ModsOverride) {
            return @{ Params = $params + @("--override", $ModsOverride); Log = "$Command (override): $ModsOverride" }
        }
        elseif ($ModsCustom) {
            return @{ Params = $params + @("-h", "--custom", $ModsCustom); Log = "$Command (custom): $ModsCustom" }
        }
        elseif ($ModsArguments) {
            # Parse arguments respecting quotes and spaces
            $argArray = ConvertTo-WingetArgumentArray $ModsArguments
            return @{ Params = $params + $argArray + @("-h"); Log = "$Command (arguments): $ModsArguments" }
        }
        return @{ Params = $params + "-h"; Log = $Command }
    }

    # Load mods
    $ModsPreInstall, $ModsOverride, $ModsCustom, $ModsArguments, $ModsUpgrade, $ModsInstall, $ModsInstalled, $ModsNotInstalled = Test-Mods $app.Id

    # With a minimum update age, install only the version Get-WAUEligibleUpdate selects.
    # It also honors a --version pin from the arguments mod.
    $ageTarget = $null
    if ($WAUConfig.WAU_MinimumUpdateAgeDays) {
        $arguments = if (-not ($ModsOverride -or $ModsCustom)) { $ModsArguments }
        $ageTarget = Get-WAUEligibleUpdate $app $src $arguments
        if (-not $ageTarget) { return }
        $app.AvailableVersion = $ageTarget.Version
        if ($app.Version -eq $ageTarget.Version) { return }
    }
    # If arguments mod specifies --version, and no override/custom is present, pin AvailableVersion to that value
    elseif ($ModsArguments -and -not $ModsOverride -and -not $ModsCustom) {
        # Parse arguments respecting quotes and spaces, then look for --version
        $modsArgArray = ConvertTo-WingetArgumentArray $ModsArguments
        $versionIndex = [array]::IndexOf($modsArgArray, '--version')
        if ($versionIndex -ge 0 -and ($versionIndex + 1) -lt $modsArgArray.Count) {
            $pinnedVersion = $modsArgArray[$versionIndex + 1]
            $app.AvailableVersion = $pinnedVersion
            Write-ToLog "-> $($app.Name) version pinned to $($app.AvailableVersion) via arguments mod" "DarkYellow"
            if ($app.Version -like "$($app.AvailableVersion)*") {
                Write-ToLog "$($app.Name) $($app.Version) is already the pinned version, skipping." "Green"
                return
            }
        }
    }

    # Get release notes for notification button
    $ReleaseNoteURL = Get-AppInfo $app.Id $src
    $Button1Text = if ($ReleaseNoteURL) { $NotifLocale.local.outputs.output[10].message } else { $null }

    # Send "updating" notification
    Write-ToLog "Updating $($app.Name) from $($app.Version) to $($app.AvailableVersion)..." "Cyan"
    Start-NotifTask -Title ($NotifLocale.local.outputs.output[2].title -f $app.Name) `
        -Message ($NotifLocale.local.outputs.output[2].message -f $app.Version, $app.AvailableVersion) `
        -MessageType "info" -Balise $app.Name -Button1Action $ReleaseNoteURL -Button1Text $Button1Text

    Write-ToLog "##########   WINGET UPGRADE: $($app.Id)   ##########" "Gray"

    # Pre-install mod
    if ($ModsPreInstall) {
        Write-ToLog "Running pre-install mod for $($app.Id)..." "DarkYellow"
        if ((& $ModsPreInstall) -eq $false) {
            Write-ToLog "Pre-install requested skip" "Yellow"
            return
        }
    }

    # Try upgrade first
    $cmd = Get-WingetParams "upgrade" $ModsOverride $ModsCustom $ModsArguments
    Write-ToLog "-> $($cmd.Log)"
    & $Winget $cmd.Params | Where-Object { $_ -notlike "   *" } | Tee-Object -file $LogFile -Append

    if ($ModsUpgrade) {
        Write-ToLog "Running upgrade mod..." "DarkYellow"
        & $ModsUpgrade
    }

    $ConfirmInstall = Confirm-Installation $app.Id $app.AvailableVersion $src

    # Fallback to install if upgrade failed
    if (-not $ConfirmInstall) {
        $maxRetry = if (Test-PendingReboot) { Write-ToLog "-> Pending reboot detected, limiting retries" "Yellow"; 1 } else { 2 }
        $retryCommand = if ($ageTarget) { 'upgrade' } else { 'install' }
        $retryMod = if ($ageTarget) { $ModsUpgrade } else { $ModsInstall }

        for ($retry = 1; $retry -le $maxRetry -and -not $ConfirmInstall; $retry++) {
            # An app can change again after discovery. The upgrade command also checks
            # applicability inside WinGet before it installs the selected version.
            if ($ageTarget) {
                $current = @(Get-WingetOutdatedApps -src $src | Where-Object { $_.Id -eq $app.Id })
                if ($current.Count -ne 1 -or $current[0].Version -cne $app.Version) {
                    Write-ToLog "-> Skipping retry: could not confirm $($app.Id) is still installed at $($app.Version)" "Yellow"
                    break
                }
            }
            Write-ToLog "-> Upgrade failed, trying $retryCommand ($retry/$maxRetry)..." "DarkYellow"

            $cmd = Get-WingetParams $retryCommand $ModsOverride $ModsCustom $ModsArguments
            Write-ToLog "-> $($cmd.Log)"
            & $Winget $cmd.Params | Where-Object { $_ -notlike "   *" } | Tee-Object -file $LogFile -Append

            if ($retryMod) {
                Write-ToLog "Running $retryCommand mod..." "DarkYellow"
                & $retryMod
            }

            $ConfirmInstall = Confirm-Installation $app.Id $app.AvailableVersion $src
        }
    }

    # Post-install mods
    if ($ConfirmInstall -and $ModsInstalled) {
        Write-ToLog "Running post-install mod..." "DarkYellow"
        & $ModsInstalled
    }
    elseif (-not $ConfirmInstall -and $ModsNotInstalled) {
        Write-ToLog "Running failure mod..." "DarkYellow"
        & $ModsNotInstalled
    }

    Write-ToLog "##########   FINISHED: $($app.Id)   ##########" "Gray"

    # Result notification
    if ($ConfirmInstall) {
        Write-ToLog "$($app.Name) updated to $($app.AvailableVersion)!" "Green"
        Start-NotifTask -Title ($NotifLocale.local.outputs.output[3].title -f $app.Name) `
            -Message ($NotifLocale.local.outputs.output[3].message -f $app.AvailableVersion) `
            -MessageType "success" -Balise $app.Name -Button1Action $ReleaseNoteURL -Button1Text $Button1Text
        $Script:InstallOK += 1
    }
    else {
        Write-ToLog "$($app.Name) update failed." "Red"
        Start-NotifTask -Title ($NotifLocale.local.outputs.output[4].title -f $app.Name) `
            -Message $NotifLocale.local.outputs.output[4].message `
            -MessageType "error" -Balise $app.Name -Button1Action $ReleaseNoteURL -Button1Text $Button1Text
    }
}
