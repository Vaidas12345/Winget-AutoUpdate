# WAU Administration Template

In an enterprise environment, it's crucial that different groups can have different settings in applications or implement other mandatory settings for security/management reasons. **WAU** doesn't have any settings that can be changed except during installation (or by editing the registry/the `Winget-AutoUpdate` task as **Admin**). However, with the use of **ADML/ADMX** files, you can manage every **WAU** setting from within **GPO** or **Intune policies**.

![image](https://user-images.githubusercontent.com/102996177/213920242-7ff8e2b4-d926-4407-b860-1e5922e29c3e.png)

## Administrative Template

### To an Individual Computer
1. Copy the **`WAU.admx`** file to your Policy Definitions template folder.
   >Example: `C:\Windows\PolicyDefinitions`
2. Copy the **`WAU.adml`** file to the matching language folder in your Policy Definitions folder.
   >Example: `C:\Windows\PolicyDefinitions\en-US`

### To Active Directory
1. On a domain controller or workstation with [RSAT](https://learn.microsoft.com/en-us/troubleshoot/windows-server/system-management-components/remote-server-administration-tools), go to the **PolicyDefinitions** folder (also known as the _Central Store_) on any domain controller for your domain.
2. Copy the **`WAU.admx`** file to the PolicyDefinitions folder.
   >Example: `%systemroot%\sysvol\domain\policies\PolicyDefinitions`
3. Copy the **`WAU.adml`** file to the matching language folder in the PolicyDefinitions folder. Create the folder if it doesn't already exist.
   >Example: `%systemroot%\sysvol\domain\policies\PolicyDefinitions\en-US`
4. If your domain has more than one domain controller, the new [ADMX files](https://learn.microsoft.com/en-us/troubleshoot/windows-client/group-policy/create-and-manage-central-store) will be replicated to them at the next domain replication interval.

## Intune

Please follow the comprehensive Microsoft documentation to import and manage the WAU policies:
[Import and Manage Administrative Templates in Intune](https://learn.microsoft.com/en-us/mem/intune-service/configuration/administrative-templates-import-custom#add-the-admx-and-adml-files)

## Minimum application update age (days)

Set a machine policy from 0 to 365 days. For example, with a three-day delay a Monday release becomes eligible on Thursday at 00:00 UTC. WAU installs eligible versions on its usual schedule. Zero, Disabled and Not Configured use normal update behavior.

WAU reads the selected installer's release date from the configured WinGet source. If that date is missing or unreadable, WAU waits the full interval from the first observation of that exact version in the machine or user context. A source lookup failure defers the update until a later run.

WAU checks the latest candidate first, or the version pinned with `--version` by an arguments mod. When the latest candidate is still too new, WAU checks up to 10 earlier versions, newest first. Both the installed and offered versions must appear exactly in the source's version list. WAU selects the first eligible release between them. If none qualifies, or a mod pins a version that is still too new, WAU waits for a later scan.

An app enters deadline tracking when it first has an eligible version. If a later scan still lists the app as outdated but cannot offer an eligible version, WAU retains the existing deadline and waits to offer or enforce the update until a version qualifies again.

For an urgent fix, add one exact entry such as `winget|Example.App|1.2.3` to **Immediate update exceptions**. Source, ID and version are case-sensitive. The exception applies only to the age check. Existing allowlists, blocklists and deadline policies still apply. The update log records the date basis, eligibility time, fallback version or exception.

> [!IMPORTANT]
> The release date comes from the package manifest. It is written by the manifest author and WinGet does not verify it. The delay gives vendors time to withdraw or fix a faulty release, but it is not a protection against a malicious manifest, which can carry any date.

If the first attempt fails, WAU rechecks the installed version before each retry and uses `winget upgrade` for the same eligible target. This lets WinGet check applicability again if the app changes between discovery and execution. Store-managed updates, vendor updaters, explicit installations and WAU's own servicing run independently.

WAU stores first observations under `SOFTWARE\Romanitho\Winget-AutoUpdate\ReleaseAge` in HKLM (machine context) or HKCU (user context). After parsing the source inventory, WAU removes records for apps absent from that inventory. It keeps observations when the inventory cannot be read. Running with the policy off clears the records for that context.

## Important Notes

- This project only supports the `en-US` ADML file.
