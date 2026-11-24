<#
.SYNOPSIS
    Returns localized WinGet installer labels and empty-inventory messages.

.DESCRIPTION
    WinGet localizes the labels in "show" independently of the installer's --locale.
    Reads them from WinGet's resources.pri, and falls back to the English labels
    when they cannot be read. The result is cached for the current run.

.OUTPUTS
    Hashtable with ShowLabelInstaller and ShowLabelInstallerReleaseDate.
#>
function Get-WAUInstallerLabelMap {
    if ($script:WAUInstallerLabels) { return $script:WAUInstallerLabels }
    $labels = @{
        ShowLabelInstaller = 'Installer:'
        ShowLabelInstallerReleaseDate = 'Release Date:'
        NoPackagesNeedUpdate = 'No packages need an update.'
        UpdateNoPackagesFound = 'No available upgrade found.'
        NoInstalledPackageFound = 'No installed package found matching input criteria.'
    }
    try {
        $pri = Join-Path (Split-Path -Parent $Winget) 'resources.pri'
        if (-not (Test-Path -LiteralPath $pri)) {
            $pri = Join-Path (Get-AppxPackage Microsoft.DesktopAppInstaller -ErrorAction Stop).InstallLocation 'resources.pri'
        }
        if (-not ('WAU.IndirectString' -as [type])) {
            Add-Type -Namespace WAU -Name IndirectString -MemberDefinition @'
[System.Runtime.InteropServices.DllImport("shlwapi.dll", CharSet = System.Runtime.InteropServices.CharSet.Unicode)]
public static extern int SHLoadIndirectString(string source, System.Text.StringBuilder value, uint size, System.IntPtr reserved);
'@ -ErrorAction Stop
        }
        foreach ($key in @($labels.Keys)) {
            $buffer = [Text.StringBuilder]::new(512)
            $resource = '@{' + $pri + '?ms-resource://Microsoft.DesktopAppInstaller/winget/' + $key + '}'
            if ([WAU.IndirectString]::SHLoadIndirectString($resource, $buffer, 512, [IntPtr]::Zero) -eq 0 -and $buffer.Length) {
                $labels[$key] = $buffer.ToString()
            }
        }
    }
    catch {
        Write-ToLog "WinGet installer labels unavailable. Undated versions use first observation." 'Yellow'
    }
    $script:WAUInstallerLabels = $labels
    return $labels
}
