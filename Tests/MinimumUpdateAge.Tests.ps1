# Run with Pester 5 under Windows PowerShell 5.1.
BeforeAll {
    $sourceDir = Join-Path $PSScriptRoot '..\Sources\Winget-AutoUpdate\functions'
    foreach ($file in 'Get-WAUReleaseDate', 'Get-WAUInstallerLabelMap', 'Get-WAUFirstSeenUtc', 'Test-WAUReleaseAge',
        'Get-WAUOlderCandidate', 'Get-WAUEligibleUpdate', 'Select-WAUAgeEligibleApp', 'Select-WAUCurrentQueuedApp',
        'Clear-WAUReleaseAgeState', 'Update-App', 'ConvertTo-WingetArgumentArray',
        'Test-Mods', 'Get-AppInfo', 'Start-NotifTask', 'Confirm-Installation', 'Test-PendingReboot', 'Write-ToLog',
        'Get-WingetOutdatedApps', 'Get-ExcludedApps', 'Get-IncludedApps', 'Get-WAUConfig',
        'Get-UpdateDeadlines', 'Set-UpdateDeadline', 'Sync-WAUUpdateDeadline', 'Test-WAUInstalledRelease') {
        . (Join-Path $sourceDir "$file.ps1")
    }
}

Describe 'Minimum application update age' {
    BeforeEach {
        $app = [PSCustomObject]@{ Id = 'Example.App'; Name = 'Example'; Version = '1'; AvailableVersion = '2' }
        $WAUConfig = [PSCustomObject]@{ WAU_MinimumUpdateAgeDays = 3; WAU_ImmediateUpdateExceptions = @() }
        $monday = [datetime]::new(2026, 11, 23, 0, 0, 0, [DateTimeKind]::Utc)
        $script:WAUReleaseDateCache = $null
        $script:WAUVersionListCache = $null
        Mock Write-ToLog {}
        Mock Get-WAUOlderCandidate {}
    }

    It 'falls back to the newest older version past the minimum age when the latest is too new' {
        Mock Get-WAUReleaseDate { if ($Version -eq '2') { $monday } else { $monday.AddDays(-10) } }
        Mock Get-WAUOlderCandidate { '1.9', '1.8' }
        $target = Get-WAUEligibleUpdate $app winget '' $monday.AddDays(1)
        $target.Version | Should -Be '1.9'
        $target.HasVersionArgument | Should -BeFalse
        Should -Invoke Get-WAUReleaseDate -Exactly -Times 0 -ParameterFilter { $Version -eq '1.8' }
        Should -Invoke Get-WAUOlderCandidate -Exactly -Times 1 -ParameterFilter {
            $InstalledVersion -eq '1' -and $LatestVersion -eq '2'
        }
    }

    It 'skips non-exact versions in older source entries' {
        Mock Get-WAUReleaseDate { if ($Version -eq '2') { $monday } else { $monday.AddDays(-10) } }
        Mock Get-WAUOlderCandidate { 'Latest', 'Unknown', '1.8' }
        (Get-WAUEligibleUpdate $app winget '' $monday.AddDays(1)).Version | Should -Be '1.8'
        Should -Invoke Get-WAUReleaseDate -Exactly -Times 0 -ParameterFilter { $Version -in 'Latest', 'Unknown' }
    }

    It 'defers when no older version is past the minimum age, and limits the fallback lookups' {
        Mock Get-WAUReleaseDate { $monday }
        Mock Get-WAUOlderCandidate { 1..15 | ForEach-Object { "1.$_" } }
        Get-WAUEligibleUpdate $app winget '' $monday.AddDays(1) | Should -BeNullOrEmpty
        Should -Invoke Get-WAUReleaseDate -Exactly -Times 11
    }

    It 'never falls back from a version pinned by an arguments mod' {
        Mock Get-WAUReleaseDate { $monday }
        Mock Get-WAUOlderCandidate { '1.4' }
        Get-WAUEligibleUpdate $app winget '--version 1.5' $monday.AddDays(1) | Should -BeNullOrEmpty
        Should -Invoke Get-WAUOlderCandidate -Exactly -Times 0
    }

    It 'caches release date lookups, including missing dates, for the run' {
        $Winget = 'Invoke-TestShow'
        Mock Get-WAUInstallerLabelMap { @{ ShowLabelInstaller = 'Installer:'; ShowLabelInstallerReleaseDate = 'Release Date:' } }
        function Invoke-TestShow { $script:showCalls++; $script:LASTEXITCODE = 0; 'Installer:', '  Type: exe' }
        $script:showCalls = 0
        Get-WAUReleaseDate $app.Id winget '2' | Should -BeNullOrEmpty
        Get-WAUReleaseDate $app.Id winget '2' | Should -BeNullOrEmpty
        $script:showCalls | Should -Be 1
        Get-WAUReleaseDate $app.Id winget '2' @('--scope', 'user') | Out-Null
        $script:showCalls | Should -Be 2
    }

    It 'distinguishes a confirmed empty inventory from an inconclusive scan' {
        $Winget = 'Invoke-TestInventory'
        Mock Get-WAUInstallerLabelMap { @{ NoPackagesNeedUpdate = 'Keine Updates.' } }
        function Invoke-TestInventory { $script:LASTEXITCODE = $exitCode; $outputLines }
        $exitCode = 0
        $outputLines = 'Keine Updates.'
        Get-WingetOutdatedApps winget -AllowEmptyInventory | Should -BeNullOrEmpty
        Get-WingetOutdatedApps winget | Should -BeLike 'No update found.*'
        $outputLines = 'Source unavailable', 'Keine Updates.'
        Get-WingetOutdatedApps winget -AllowEmptyInventory | Should -BeLike 'No update found.*'
        $exitCode = 1
        $outputLines = 'Source failed', '-----'
        Get-WingetOutdatedApps winget -AllowEmptyInventory | Should -BeLike 'No update found.*'
    }

    It 'removes first-observation records of apps that are no longer outdated' {
        $IsSystem = $false
        $source = 'WAUTest-' + [guid]::NewGuid()
        $path = "SOFTWARE\Romanitho\Winget-AutoUpdate\ReleaseAge\$source"
        try {
            Get-WAUFirstSeenUtc $source 'Kept.App' '1' $monday | Out-Null
            Get-WAUFirstSeenUtc $source 'Gone.App' '1' $monday | Out-Null
            Clear-WAUReleaseAgeState 'No update found.' $source
            @([Microsoft.Win32.Registry]::CurrentUser.OpenSubKey($path).GetSubKeyNames()).Count | Should -Be 2
            Clear-WAUReleaseAgeState @([pscustomobject]@{ Id = 'Kept.App' }) $source
            [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey($path).GetSubKeyNames() | Should -Be 'Kept.App'
        }
        finally {
            [Microsoft.Win32.Registry]::CurrentUser.DeleteSubKeyTree($path, $false)
        }
    }

    It 'uses UTC calendar days and admits the version exactly at the boundary' {
        Mock Get-WAUReleaseDate { $monday }
        Get-WAUEligibleUpdate $app winget '' $monday.AddDays(3).AddTicks(-1) | Should -BeNullOrEmpty
        (Get-WAUEligibleUpdate $app winget '' $monday.AddDays(3)).Version | Should -Be '2'
    }

    It 'waits 72 hours from first observation if no release date is available' {
        Mock Get-WAUReleaseDate {}
        Mock Get-WAUFirstSeenUtc { $monday.AddHours(13) }
        Get-WAUEligibleUpdate $app winget '' $monday.AddDays(3) | Should -BeNullOrEmpty
        (Get-WAUEligibleUpdate $app winget '' $monday.AddDays(3).AddHours(13)).Version | Should -Be '2'
    }

    It 'persists observations separately by source, ID and version in the user registry' {
        $IsSystem = $false
        $source = 'WAUTest-' + [guid]::NewGuid()
        try {
            Get-WAUFirstSeenUtc $source 'app' '1' $monday | Should -Be $monday
            Get-WAUFirstSeenUtc $source 'app' '1' $monday.AddDays(8) | Should -Be $monday
            Get-WAUFirstSeenUtc $source 'app' '2' $monday.AddDays(1) | Should -Be $monday.AddDays(1)
            Get-WAUFirstSeenUtc $source 'other' '1' $monday.AddDays(2) | Should -Be $monday.AddDays(2)
        }
        finally {
            [Microsoft.Win32.Registry]::CurrentUser.DeleteSubKeyTree("SOFTWARE\Romanitho\Winget-AutoUpdate\ReleaseAge\$source", $false)
        }
    }

    It 'defers when the source lookup fails or first-seen state cannot be persisted' {
        Mock Get-WAUReleaseDate { throw 'unavailable' }
        Get-WAUEligibleUpdate $app winget '' $monday | Should -BeNullOrEmpty
        Mock Get-WAUReleaseDate {}
        Mock Get-WAUFirstSeenUtc { throw 'cannot write' }
        Get-WAUEligibleUpdate $app winget '' $monday | Should -BeNullOrEmpty
    }

    It 'applies an urgent exception only to the exact version and source' {
        $WAUConfig.WAU_ImmediateUpdateExceptions = @('winget|Example.App|2')
        Mock Get-WAUReleaseDate { $monday }
        (Get-WAUEligibleUpdate $app winget '' $monday).Version | Should -Be '2'
        Get-WAUEligibleUpdate $app other '' $monday | Should -BeNullOrEmpty
        $app.AvailableVersion = '3'
        Get-WAUEligibleUpdate $app winget '' $monday | Should -BeNullOrEmpty
    }

    It 'reads the release date only from the final localized installer section' {
        $Winget = 'Invoke-TestShow'
        $script:WAUInstallerLabels = @{ ShowLabelInstaller = 'Diegimo programa:'; ShowLabelInstallerReleaseDate = 'Data:' }
        function Invoke-TestShow {
            $script:LASTEXITCODE = 0
            'Diegimo programa:', '  Data: 2000-01-01', 'Diegimo programa:', '  Data: 2026-11-23'
        }
        try { Get-WAUReleaseDate $app.Id winget '2' | Should -Be $monday }
        finally { $script:WAUInstallerLabels = $null }
    }

    It 'uses first observation for an invalid calendar date' {
        $Winget = 'Invoke-TestShow'
        Mock Get-WAUInstallerLabelMap { @{ ShowLabelInstaller = 'Installer:'; ShowLabelInstallerReleaseDate = 'Release Date:' } }
        function Invoke-TestShow { $script:LASTEXITCODE = 0; 'Installer:', '  Release Date: 2026-02-31' }
        Get-WAUReleaseDate $app.Id winget '2' | Should -BeNullOrEmpty
    }

    It 'ignores a date printed in release notes when the installer has no date' {
        $Winget = 'Invoke-TestShow'
        Mock Get-WAUInstallerLabelMap { @{ ShowLabelInstaller = 'Installer:'; ShowLabelInstallerReleaseDate = 'Release Date:' } }
        function Invoke-TestShow { $script:LASTEXITCODE = 0; 'Notes:', '  Release Date: 2000-01-01', 'Installer:', '  Type: exe' }
        Get-WAUReleaseDate $app.Id winget '2' | Should -BeNullOrEmpty
    }

    It 'defers ambiguous targets before querying metadata' {
        Mock Get-WAUReleaseDate { throw 'unexpected lookup' }
        foreach ($arguments in '--all', '--version', '--version 1 --version 2', '--version Latest', '--source other') {
            Get-WAUEligibleUpdate $app winget $arguments $monday | Should -BeNullOrEmpty
        }
        Should -Invoke Get-WAUReleaseDate -Times 0 -Exactly
    }

    It 'treats a quoted installer switch as data and pins the chosen fallback explicitly' {
        Mock Get-WAUReleaseDate { if ($Version -eq '2') { $monday } else { $monday.AddDays(-7) } }
        Mock Get-WAUOlderCandidate { '1.8' }
        $target = Get-WAUEligibleUpdate $app winget '--custom "--version=1.9"' $monday
        $target.Version | Should -Be '1.8'
        $target.HasVersionArgument | Should -BeFalse
    }

    It 'evaluates the mod pin and forwards installer-selection options to the lookup' {
        Mock Get-WAUReleaseDate { $monday }
        $target = Get-WAUEligibleUpdate $app winget '-v 1.5 --scope user --architecture=x64' $monday.AddDays(3)
        $target.Version | Should -Be '1.5'
        $target.HasVersionArgument | Should -BeTrue
        Should -Invoke Get-WAUReleaseDate -Exactly -Times 1 -ParameterFilter {
            $Version -eq '1.5' -and ($InstallerArguments -join ' ') -eq '--scope user --architecture x64'
        }
    }

    It 'omits superseded queued versions and holds newly detected apps out of deadline prompts' {
        Mock Test-Mods {}
        Mock Get-ExcludedApps {}
        Mock Get-WAUReleaseDate { [datetime]::UtcNow }
        @(Select-WAUAgeEligibleApp @($app) winget).Count | Should -Be 0
        Mock Get-WAUReleaseDate { [datetime]::UtcNow.AddYears(-1) }
        Mock Get-WingetOutdatedApps { $app }
        $queued = [PSCustomObject]@{ Id = $app.Id; AvailableVersion = '1.5' }
        @(Select-WAUCurrentQueuedApp @($queued) winget).Count | Should -Be 0
        Should -Invoke Write-ToLog -Exactly -Times 1 -ParameterFilter {
            $LogMsg -eq 'Removed Example.App 1.5 from the update queue: the eligible version is now 2'
        }
        $queued.AvailableVersion = '2'
        @(Select-WAUCurrentQueuedApp @($queued) winget).Count | Should -Be 1
    }

    It 'preserves the first deadline across a deferred scan and removes it when the app is current' {
        $root = (Get-Item 'TestRegistry:\').Name
        New-PSDrive -Name HKLM -PSProvider Registry -Root $root -Scope Local -ErrorAction Stop | Out-Null
        (Get-Item 'HKLM:\').Name | Should -BeExactly $root
        Mock Test-Mods {}
        Mock Get-WAUReleaseDate { [datetime]::UtcNow.AddYears(-1) }
        $first = Sync-WAUUpdateDeadline @(Select-WAUAgeEligibleApp $app winget -IncludeDeferred) 7
        $first.AvailableVersion | Should -Be '2'
        $app.AvailableVersion = '3'
        Mock Get-WAUReleaseDate { [datetime]::UtcNow }
        $held = @(Select-WAUAgeEligibleApp $app winget -IncludeDeferred)
        $held.Count | Should -Be 1
        $held[0].AvailableVersion | Should -BeNullOrEmpty
        # Exercise the same serialization used to hand user inventory to SYSTEM.
        $rows = @($held | ConvertTo-Csv -NoTypeInformation | ConvertFrom-Csv)
        Sync-WAUUpdateDeadline $rows 30 | Should -BeNullOrEmpty
        (Get-UpdateDeadlines).Deadline | Should -Be $first.Deadline
        $app.AvailableVersion = '3'
        Mock Get-WAUReleaseDate { [datetime]::UtcNow.AddYears(-1) }
        $next = Sync-WAUUpdateDeadline @(Select-WAUAgeEligibleApp $app winget -IncludeDeferred) 30
        $next.AvailableVersion | Should -Be '3'
        $next.Deadline | Should -Be $first.Deadline
        Sync-WAUUpdateDeadline @() 7 | Should -BeNullOrEmpty
        Get-UpdateDeadlines | Should -BeNullOrEmpty
    }

    It 'rechecks exclusions when a queued update has an immediate exception' {
        $WAUConfig.WAU_ImmediateUpdateExceptions = @('winget|Example.App|2')
        Mock Get-WingetOutdatedApps { $app }
        Mock Get-ExcludedApps { 'Example.*' }
        Mock Test-Mods {}
        @(Select-WAUCurrentQueuedApp @($app) winget).Count | Should -Be 0
        Should -Invoke Test-Mods -Times 0 -Exactly
    }

    It 'preserves existing arguments-mod behavior for an installed version with a build suffix' {
        $app.Version = '1.5.0.0'
        Mock Get-WAUReleaseDate { throw 'unexpected lookup' }
        $target = Get-WAUEligibleUpdate $app winget '--version 1.5' $monday
        $target.Version | Should -Be '1.5.0.0'
        Should -Invoke Get-WAUReleaseDate -Times 0 -Exactly
    }

    It 'drops an app already at its mod-pinned version from deadline tracking instead of holding it' {
        $root = (Get-Item 'TestRegistry:\').Name
        New-PSDrive -Name HKLM -PSProvider Registry -Root $root -Scope Local -ErrorAction Stop | Out-Null
        (Get-Item 'HKLM:\').Name | Should -BeExactly $root
        (Sync-WAUUpdateDeadline @($app) 7).AppId | Should -Be $app.Id
        $app.Version = '1.5.0.0'
        Mock Test-Mods { $null, $null, $null, '--version 1.5', $null, $null, $null, $null }
        Mock Get-WAUReleaseDate { throw 'unexpected lookup' }
        $tracked = @(Select-WAUAgeEligibleApp @($app) winget -IncludeDeferred)
        $tracked.Count | Should -Be 0
        Sync-WAUUpdateDeadline $tracked 7 | Should -BeNullOrEmpty
        Get-UpdateDeadlines | Should -BeNullOrEmpty
        $app.AvailableVersion | Should -Be '2'
    }

    It 'keeps a pinned release waiting when the installed version is <installed>' -ForEach @(
        @{ installed = '1.5-rc1' }
        @{ installed = '1.50' }
    ) {
        $app.Version = $installed
        Mock Test-Mods { $null, $null, $null, '--version 1.5', $null, $null, $null, $null }
        Mock Get-WAUReleaseDate { [datetime]::UtcNow }
        $held = @(Select-WAUAgeEligibleApp @($app) winget -IncludeDeferred)
        $held.Count | Should -Be 1
        $held[0].AvailableVersion | Should -BeNullOrEmpty
    }

    It 'confirms an age-checked release using its installed version and numeric build suffix' {
        $Winget = 'Invoke-TestExport'
        function Invoke-TestExport {
            $file = $args[[array]::IndexOf($args, '-o') + 1]
            @{ Sources = @(@{ Packages = @(@{ PackageIdentifier = $app.Id; Version = $app.Version }) }) } |
                ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $file
        }
        $originalTemp = $env:TEMP
        try {
            $env:TEMP = $TestDrive
            $app.Version = '1.5-rc1'
            Confirm-Installation $app.Id '1.5' winget -MatchRelease | Should -BeFalse
            Confirm-Installation $app.Id -src winget | Should -BeTrue
            $app.Version = '1.50'
            Confirm-Installation $app.Id '1.5' winget -MatchRelease | Should -BeFalse
            $app.Version = '1.5.0.0'
            Confirm-Installation $app.Id '1.5' winget -MatchRelease | Should -BeTrue
        }
        finally { $env:TEMP = $originalTemp }
    }

    It 'skips an app already at its mod-pinned version without installing or changing it' {
        $app.Version = '1.5.0.0'
        $Winget = 'Invoke-UnexpectedInstaller'
        function Invoke-UnexpectedInstaller { throw 'unexpected installer call' }
        Mock Test-Mods { $null, $null, $null, '--version 1.5', $null, $null, $null, $null }
        Mock Get-AppInfo {}
        Mock Start-NotifTask {}
        Update-App $app winget
        $app.AvailableVersion | Should -Be '2'
        Should -Invoke Start-NotifTask -Times 0 -Exactly
    }

    Context 'installation' {
        BeforeEach {
            $Winget = 'Invoke-TestInstaller'
            $LogFile = Join-Path $TestDrive 'update.log'
            $script:commands = [Collections.Generic.List[object]]::new()
            function Invoke-TestInstaller ([string[]]$Arguments) { $script:commands.Add($Arguments) }
            $NotifLocale = @{ local = @{ outputs = @{ output = @(1..11 | ForEach-Object { @{ title = 'title'; message = 'message' } }) } } }
            Mock Test-Mods {}
            Mock Get-AppInfo {}
            Mock Start-NotifTask {}
            Mock Confirm-Installation { $false }
            Mock Test-PendingReboot { $false }
            Mock Get-WingetOutdatedApps { $app }
        }

        It 'skips notifications and installer invocation while deferred' {
            Mock Get-WAUReleaseDate { [datetime]::UtcNow }
            Update-App $app winget
            $script:commands.Count | Should -Be 0
            Should -Invoke Start-NotifTask -Times 0 -Exactly
        }

        It 'uses the native upgrade version check on every attempt, including after the inventory check' {
            Mock Get-WAUReleaseDate { [datetime]::UtcNow.AddYears(-1) }
            Update-App $app winget
            $script:commands.Count | Should -Be 3
            ($script:commands | ForEach-Object { $_[0] }) -join ',' | Should -Be 'upgrade,upgrade,upgrade'
            foreach ($command in $script:commands) {
                ($command -join ' ') | Should -Match '--version 2(?: |$)'
                $command | Should -Not -Contain '--force'
            }
            Should -Invoke Start-NotifTask -Times 1 -Exactly -ParameterFilter { $MessageType -eq 'error' }
        }

        It 'stops before retrying when inventory reports <case>' -ForEach @(
            @{ case = 'a newer installed version'; versions = @('3') }
            @{ case = 'a removed application'; versions = @() }
            @{ case = 'ambiguous installed versions'; versions = @('1', '3') }
        ) {
            Mock Get-WAUReleaseDate { [datetime]::UtcNow.AddYears(-1) }
            Mock Get-WingetOutdatedApps {
                foreach ($version in $versions) {
                    [pscustomobject]@{ Id = $app.Id; Version = $version; AvailableVersion = '4' }
                }
            }
            $script:failureHooks = 0
            Mock Test-Mods { $null, $null, $null, $null, $null, $null, $null, { $script:failureHooks++ } }
            Update-App $app winget
            $script:commands.Count | Should -Be 1
            Should -Invoke Start-NotifTask -Times 0 -Exactly -ParameterFilter { $MessageType -eq 'success' }
            # The user saw "updating", so the normal failure path still reports the result.
            Should -Invoke Start-NotifTask -Times 1 -Exactly -ParameterFilter { $MessageType -eq 'error' }
            $script:failureHooks | Should -Be 1
        }

        It 'stops if the installation changes between retries' {
            Mock Get-WAUReleaseDate { [datetime]::UtcNow.AddYears(-1) }
            Mock Get-WingetOutdatedApps {
                if ($script:commands.Count -eq 1) { return $app }
                [pscustomobject]@{ Id = $app.Id; Version = '3'; AvailableVersion = '4' }
            }
            Update-App $app winget
            ($script:commands | ForEach-Object { $_[0] }) -join ',' | Should -Be 'upgrade,upgrade'
        }

        It 'runs the upgrade mod on a successful retry and stops checking inventory' {
            $script:upgradeHooks = 0
            $script:installHooks = 0
            $script:InstallOK = 0
            Mock Test-Mods {
                $null, $null, $null, $null, { $script:upgradeHooks++ }, { $script:installHooks++ }, $null, $null
            }
            Mock Get-WAUReleaseDate { [datetime]::UtcNow.AddYears(-1) }
            Mock Confirm-Installation { $script:commands.Count -eq 2 }
            Update-App $app winget
            ($script:commands | ForEach-Object { $_[0] }) -join ',' | Should -Be 'upgrade,upgrade'
            $script:upgradeHooks | Should -Be 2
            $script:installHooks | Should -Be 0
            $script:InstallOK | Should -Be 1
            Should -Invoke Get-WingetOutdatedApps -Times 1 -Exactly -ParameterFilter { $src -eq 'winget' }
        }

        It 'passes the effective mod pin only once on each attempt' {
            Mock Test-Mods { $null, $null, $null, '--version 1.5', $null, $null, $null, $null }
            Mock Get-WAUReleaseDate { [datetime]::UtcNow.AddYears(-1) }
            Update-App $app winget
            $script:commands.Count | Should -Be 3
            foreach ($command in $script:commands) {
                @($command | Where-Object { $_ -eq '--version' }).Count | Should -Be 1
                ($command -join ' ') | Should -Match '--version 1\.5(?: |$)'
            }
        }

        It 'preserves the normal install command and performs no age lookup when disabled' {
            $WAUConfig.WAU_MinimumUpdateAgeDays = 0
            Mock Get-WAUReleaseDate { throw 'unexpected lookup' }
            Mock Get-WAUFirstSeenUtc { throw 'unexpected state write' }
            Update-App $app winget
            $script:commands.Count | Should -Be 3
            $script:commands[0] | Should -Not -Contain '--version'
            $script:commands[1][0] | Should -Be 'install'
            $script:commands[1] | Should -Contain '--force'
            Should -Invoke Get-WingetOutdatedApps -Times 0 -Exactly
            Should -Invoke Get-WAUReleaseDate -Times 0 -Exactly
            Should -Invoke Get-WAUFirstSeenUtc -Times 0 -Exactly
        }
    }
}

Describe 'Older candidate lookup' {
    BeforeEach {
        $script:WAUVersionListCache = $null
        $Winget = 'Invoke-TestShow'
        Mock Write-ToLog {}
    }

    It 'lists only the source versions strictly between the installed and the latest version' {
        function Invoke-TestShow {
            $script:showCalls++
            $script:LASTEXITCODE = 0
            'Found Example [Example.App]', 'Versija', '---------', '3', '2.5', '2', '1', '0.9'
        }
        $script:showCalls = 0
        (Get-WAUOlderCandidate 'Example.App' winget '1' '3') -join ',' | Should -Be '2.5,2'
        Get-WAUOlderCandidate 'Example.App' winget '2' '2.5' | Should -BeNullOrEmpty
        Get-WAUOlderCandidate 'Example.App' winget '1.0.0.0' '3' | Should -BeNullOrEmpty
        Get-WAUOlderCandidate 'Example.App' winget '3' '2' | Should -BeNullOrEmpty
        $script:showCalls | Should -Be 1
    }

    It 'returns nothing when the output has no version list' {
        function Invoke-TestShow { $script:LASTEXITCODE = 0; 'Found Example [Example.App]', 'Version', '-------' }
        Get-WAUOlderCandidate 'Example.App' winget '1' '3' | Should -BeNullOrEmpty
    }

    It 'throws when the version list cannot be read' {
        function Invoke-TestShow { $script:LASTEXITCODE = 1 }
        { Get-WAUOlderCandidate 'Example.App' winget '1' '3' } | Should -Throw
    }
}

Describe 'Release age administrative template' {
    BeforeAll {
        $templateDir = Join-Path $PSScriptRoot '..\Sources\Policies\ADMX'
        $admx = [xml](Get-Content -Raw (Join-Path $templateDir 'WAU.admx'))
        $adml = [xml](Get-Content -Raw (Join-Path $templateDir 'en-US\WAU.adml'))
        $policies = $admx.policyDefinitions.policies.policy
        $resources = $adml.policyDefinitionResources.resources
    }

    It 'exposes the 0-365 machine DWORD through a numeric control defaulting to zero' {
        $policy = $policies | Where-Object name -eq MinimumUpdateAgeDays
        $control = ($resources.presentationTable.presentation | Where-Object id -eq MinimumUpdateAgeDays).decimalTextBox
        $policy.class | Should -Be Machine
        $policy.elements.decimal.valueName | Should -Be 'WAU_MinimumUpdateAgeDays'
        $policy.elements.decimal.minValue | Should -Be '0'
        $policy.elements.decimal.maxValue | Should -Be '365'
        $control.refId | Should -Be $policy.elements.decimal.id
        $control.defaultValue | Should -Be '0'
    }

    It 'binds exceptions to the machine policy subkey and resolves the new resource references' {
        $policy = $policies | Where-Object name -eq ImmediateUpdateExceptions
        $policy.elements.list.key | Should -Be 'Software\Policies\Romanitho\Winget-AutoUpdate\ImmediateUpdateExceptions'
        $box = ($resources.presentationTable.presentation | Where-Object id -eq ImmediateUpdateExceptions).listBox
        $box.refId | Should -Be $policy.elements.list.id
        foreach ($name in 'MinimumUpdateAgeDays', 'ImmediateUpdateExceptions') {
            $resources.stringTable.string.id | Should -Contain ($name + '_Name')
            $resources.stringTable.string.id | Should -Contain ($name + '_Explain')
        }
    }

    It 'reads the template values from the registry and applies the exception only to an allowed release' {
        # All writes go to Pester's temporary HKCU subtree. Redirect only this scope's HKLM reads.
        $root = (Get-Item 'TestRegistry:\').Name
        New-PSDrive -Name HKLM -PSProvider Registry -Root $root -Scope Local -ErrorAction Stop | Out-Null
        (Get-Item 'HKLM:\').Name | Should -BeExactly $root
        $base = New-Item 'TestRegistry:\Software\Romanitho\Winget-AutoUpdate' -Force
        New-ItemProperty $base.PSPath -Name ProductVersion -Value '3.0.0' | Out-Null
        $age = $policies | Where-Object name -eq MinimumUpdateAgeDays
        $policy = New-Item (Join-Path 'TestRegistry:\' $age.key) -Force
        New-ItemProperty $policy.PSPath -Name $age.elements.decimal.valueName -PropertyType DWord -Value 30 | Out-Null
        New-ItemProperty $policy.PSPath -Name WAU_UseWhiteList -PropertyType DWord -Value 1 | Out-Null
        $list = ($policies | Where-Object name -eq ImmediateUpdateExceptions).elements.list
        $exceptions = New-Item (Join-Path 'TestRegistry:\' $list.key) -Force
        New-ItemProperty $exceptions.PSPath -Name '1' -Value 'winget|Example.App|1.2.3' | Out-Null
        $allowed = New-Item (Join-Path $policy.PSPath 'WhiteList')
        New-ItemProperty $allowed.PSPath -Name '1' -Value 'Example.App' | Out-Null

        Mock Write-ToLog {}
        Mock Test-Mods {}
        Mock Get-WAUReleaseDate { [datetime]::UtcNow }
        $IsSystem = $true
        $WAUConfig = Get-WAUConfig
        $WAUConfig.WAU_MinimumUpdateAgeDays | Should -Be 30
        $app = [pscustomobject]@{ Id = 'Example.App'; Version = '1.0'; AvailableVersion = '1.2.3' }
        Mock Get-WingetOutdatedApps { $app }
        @(Select-WAUCurrentQueuedApp @($app) winget).Count | Should -Be 1
        $app.AvailableVersion = '1.2.4'
        @(Select-WAUCurrentQueuedApp @($app) winget).Count | Should -Be 0
        $app.AvailableVersion = '1.2.3'
        Set-ItemProperty $allowed.PSPath -Name '1' -Value 'Other.App'
        @(Select-WAUCurrentQueuedApp @($app) winget).Count | Should -Be 0
    }
}
