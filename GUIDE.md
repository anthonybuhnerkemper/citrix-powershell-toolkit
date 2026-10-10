# Managing Citrix Virtual Apps and Desktops with the PowerShell SDK

*A practical guide for admins who already use PowerShell and want to manage Citrix Virtual Apps and Desktops (CVAD) and Citrix DaaS the same way.*

> **Scope and accuracy note.** This guide covers the Citrix PowerShell SDK used by on-premises Delivery Controllers and the Citrix DaaS Remote PowerShell SDK. Cmdlet names are taken from the published SDK. Property names and parameters change between releases, so where behavior depends on version that's called out. Always check `Get-Help <cmdlet> -Full` on your own controller. Nothing here replaces testing in a lab.

---

## Table of contents

1. [Why manage Citrix with PowerShell](#1-why-manage-citrix-with-powershell)
2. [Architecture: what the SDK talks to](#2-architecture-what-the-sdk-talks-to)
3. [On-premises: loading the SDK (snap-ins vs. modules)](#3-on-premises-loading-the-sdk-snap-ins-vs-modules)
4. [Citrix DaaS: the Remote PowerShell SDK](#4-citrix-daas-the-remote-powershell-sdk)
5. [Connecting with -AdminAddress](#5-connecting-with--adminaddress)
6. [SDK conventions you need to know](#6-sdk-conventions-you-need-to-know)
7. [Key cmdlet families](#7-key-cmdlet-families)
8. [Common admin workflows](#8-common-admin-workflows)
9. [Reporting](#9-reporting)
10. [Safe change practice](#10-safe-change-practice)
11. [Scheduling](#11-scheduling)
12. [Security and least privilege](#12-security-and-least-privilege)
13. [Troubleshooting](#13-troubleshooting)
14. [Quick reference](#14-quick-reference)

---

## 1. Why manage Citrix with PowerShell

Citrix Studio (the MMC console, or Web Studio in newer releases) is itself a client of the PowerShell SDK. Studio builds the same SDK calls you can run yourself, which is why Studio could show "PowerShell" tabs with the commands it ran. So anything Studio can do, the SDK can do too, and quite a bit Studio can't:

- **Bulk operations.** Put 200 machines in maintenance mode, retag a whole catalog, or reassign users without clicking through each object.
- **Repeatable reporting.** Session counts, unregistered machines, application inventories and configuration change history, exported to CSV/HTML on a schedule.
- **Auditable change.** Scripts with `-WhatIf`, logging, and Configuration Logging entries give you a better change record than "I clicked it in Studio."
- **Consistency with the rest of your stack.** If you already automate Microsoft 365, Entra ID or Exchange with PowerShell, Citrix fits the same patterns: objects through the pipeline, `Select-Object`, `Export-Csv`, and scheduled tasks.

## 2. Architecture: what the SDK talks to

A CVAD site is a set of services running on each Delivery Controller. Each service has its own PowerShell snap-in or module and its own cmdlet prefix:

| Service | Prefix | Typical cmdlets | Purpose |
|---|---|---|---|
| Broker | `Broker` | `Get-BrokerMachine`, `Get-BrokerSession`, `Get-BrokerDesktopGroup` | Machines, sessions, delivery groups, apps, power actions |
| Machine Creation (Provisioning) | `Prov` | `Get-ProvScheme`, `Get-ProvTask`, `Publish-ProvMasterVMImage` | MCS catalogs and image updates |
| Host | `Hyp` (and the `XDHyp:` PSDrive) | `Get-HypScopedObject`, `Get-ChildItem XDHyp:\` | Hosting connections and resources |
| AD Identity | `Acct` | `Get-AcctIdentityPool`, `Get-AcctADAccount` | Machine accounts for MCS |
| Configuration Logging | `Log` | `Get-LogHighLevelOperation`, `Get-LogLowLevelOperation`, `Get-LogSite` | Audit trail of admin changes |
| Delegated Administration | `Admin` | `Get-AdminAdministrator`, `Get-AdminRole`, `Get-AdminScope` | RBAC |
| Monitor | `Monitor` | `Get-MonitorConfiguration` | Monitor service settings (data itself is usually read via the OData API) |
| Analytics / Config / Environment Test | `Analytics`, `Config`, `EnvTest` | `Get-ConfigSite`, `Start-EnvTestTask` | Site config, health tests |

The SDK cmdlets don't touch the database directly. They make remote calls to the services on a Delivery Controller, which then read and write the site database. That's why every cmdlet takes an `-AdminAddress` parameter (section 5), and why you can run the SDK from any domain-joined admin workstation that has it installed, not only from a controller.

Licensing is a separate component. The License Server has its own PowerShell module (`Citrix.Licensing.Admin.V1`, with cmdlets such as `Get-LicCertificate`, `Get-LicInventory` and `Get-LicUsage`), and it's managed separately from the Broker.

## 3. On-premises: loading the SDK (snap-ins vs. modules)

### 3.1 Where the SDK comes from

The SDK gets installed with each Delivery Controller and with Studio. You can also install the individual SDK MSIs from the CVAD installation media onto an admin workstation or jump host. Check that the SDK version matches (or is newer than) your controllers. An older SDK talking to a newer site can fail on newer properties or parameters.

### 3.2 Snap-ins (classic, Windows PowerShell 5.1)

Historically every Citrix service shipped as a Windows PowerShell **snap-in**. The idiom you'll see in a lot of community scripts is:

```powershell
Add-PSSnapin Citrix*
Get-PSSnapin Citrix*   # confirm what loaded
```

Snap-ins only work in **Windows PowerShell 5.1**. PowerShell 7 doesn't support `Add-PSSnapin` at all.

### 3.3 Modules (CVAD 2203 LTSR and later)

Starting with the 2203 release, the CVAD SDK is also delivered as PowerShell **modules** (for example `Citrix.Broker.Admin.V2`, `Citrix.MachineCreation.Admin.V2`, `Citrix.ConfigurationLogging.Admin.V1`, `Citrix.DelegatedAdmin.Admin.V1`). With modules you can:

```powershell
Get-Module -ListAvailable Citrix*
Import-Module Citrix.Broker.Admin.V2
```

and PowerShell module auto-loading can find cmdlets without an explicit import. Version notes, stated carefully:

- **Before 2203:** snap-ins only. Use `Add-PSSnapin Citrix*` in Windows PowerShell 5.1.
- **2203 and later:** modules are installed, and Citrix's guidance is to move to `Import-Module`. Depending on the release, `Add-PSSnapin` may still be supported for backward compatibility. Check the release notes for your version before you rely on either one.
- **PowerShell 7:** support depends on the release. Many organizations still run Citrix automation in Windows PowerShell 5.1 because that's the configuration Citrix has documented and supported for the longest. If you want PowerShell 7, test it explicitly and check Citrix's current documentation for your version.

The scripts in this repository load the SDK defensively. They import `Citrix.Broker.Admin.V2` if it's installed, fall back to `Add-PSSnapin Citrix*` if snap-ins are available, and throw a clear error if neither works:

```powershell
function Import-CitrixSdk {
    if (Get-Command Get-BrokerSite -ErrorAction SilentlyContinue) { return }
    $mod = Get-Module -ListAvailable Citrix.Broker.Admin.V2 | Select-Object -First 1
    if ($mod) { Import-Module $mod -ErrorAction Stop; return }
    if (Get-Command Add-PSSnapin -ErrorAction SilentlyContinue) { Add-PSSnapin Citrix* -ErrorAction SilentlyContinue }
    if (-not (Get-Command Get-BrokerSite -ErrorAction SilentlyContinue)) { throw 'Citrix SDK not found.' }
}
```

### 3.4 Discovering cmdlets

```powershell
Get-Command -Module Citrix.Broker.Admin.V2 | Measure-Object
Get-Command -Noun Broker* -Verb Get
Get-Help Get-BrokerMachine -Full
Get-Help about_Broker_Filtering   # the filtering language, see section 6
```

The `about_` help topics that ship with the SDK (for example `about_Broker_Filtering`) are worth reading. They document the shared filter syntax that `Get-Broker*` cmdlets use.

## 4. Citrix DaaS: the Remote PowerShell SDK

With Citrix DaaS (formerly Virtual Apps and Desktops service), Citrix runs the Delivery Controllers. You can't log on to them, so you install the **Citrix DaaS Remote PowerShell SDK** on a Windows machine you control. It exposes the same cmdlet names (`Get-BrokerMachine`, `Get-ProvScheme` and so on) and sends them through Citrix Cloud.

### 4.1 Authentication with an API client

Interactive use pops up a Citrix Cloud sign-in the first time a cmdlet runs. For automation you create a **secure client** (API client) in the Citrix Cloud console (Identity and Access Management > API Access). That gives you a Client ID and Secret, usually downloaded as a CSV, plus your **Customer ID**.

Register the credentials with `Set-XDCredentials`:

```powershell
asnp Citrix*   # the Remote SDK has historically been loaded as snap-ins

Set-XDCredentials -CustomerId 'yourCustomerId' `
                  -SecureClientFile 'C:\Secure\secureclient.csv' `
                  -ProfileType CloudApi `
                  -StoreAs 'DaaSAutomation'
```

or pass `-APIKey` and `-SecretKey` directly instead of a file. Then, in later sessions:

```powershell
Get-XDCredentials -ProfileName 'DaaSAutomation' | Out-Null   # select a stored profile
Get-XDAuthentication -ProfileName 'DaaSAutomation'            # obtain a bearer token for this session
Get-BrokerSite
```

Key points:

- **No `-AdminAddress` in DaaS.** The Remote SDK sends calls to the cloud endpoint for your customer. Scripts in this repo treat `-AdminAddress` as optional for that reason. Leave it out in DaaS.
- **Protect the secure client.** The Client ID/Secret pair acts with the permissions of the admin who created it. Store it with restrictive NTFS ACLs or in a secret vault (for example the SecretManagement module), use a dedicated, least-privileged admin to create it, and rotate it.
- **Region.** Customers outside the default (US) region may need to specify the cloud region or endpoint when they set credentials. Check `Get-Help Set-XDCredentials -Full` for the parameters your SDK version supports.
- **Some cmdlets differ.** Site-infrastructure cmdlets (controllers, database, licensing) don't apply or behave differently in DaaS because Citrix manages that layer.

## 5. Connecting with -AdminAddress

On-premises, every SDK cmdlet accepts `-AdminAddress` to say which Delivery Controller to talk to:

```powershell
Get-BrokerMachine -AdminAddress ddc01.contoso.local -MaxRecordCount 5000
```

If you run on a controller and leave it out, the local machine is used. Practices that help:

- **Always pass it in scripts.** It makes the target explicit and lets the same script run from a jump host.
- **Use a hashtable for splatting**, so you can drop the parameter cleanly when it's empty (DaaS) or not needed:

  ```powershell
  $ap = @{}
  if ($AdminAddress) { $ap.AdminAddress = $AdminAddress }
  Get-BrokerDesktopGroup @ap
  ```

- **Session default.** Don't rely on any implicit default controller from earlier in the session. Pass `-AdminAddress` on every call, or set it once with `$PSDefaultParameterValues`:

  ```powershell
  $PSDefaultParameterValues['*-Broker*:AdminAddress'] = 'ddc01.contoso.local'
  ```

- **Failover.** For a resilient scheduled script, try a list of controllers and use the first one that answers `Get-BrokerServiceStatus` with `OK`:

  ```powershell
  $ddc = 'ddc01','ddc02' | Where-Object {
      try { (Get-BrokerServiceStatus -AdminAddress $_ -ErrorAction Stop).ServiceStatus -eq 'OK' } catch { $false }
  } | Select-Object -First 1
  ```

## 6. SDK conventions you need to know

### 6.1 MaxRecordCount (the 250-record trap)

`Get-Broker*` cmdlets return **at most 250 records by default**. When there are more, you get a warning and silently truncated data. That's the most common bug in Citrix reporting scripts. Always set `-MaxRecordCount` explicitly:

```powershell
Get-BrokerSession -MaxRecordCount 100000
```

You can also page with `-Skip` and `-ReturnTotalRecordCount` on very large sites.

### 6.2 Server-side filtering

Most `Get-Broker*` and `Get-Log*` cmdlets accept typed parameters (`-DesktopGroupName`, `-SessionState`, `-RegistrationState`, `-Tag`, `-InMaintenanceMode`) and a generic `-Filter` that uses the SDK's own expression language (`about_Broker_Filtering`). Filtering on the server is much faster than `Where-Object` because less data crosses the wire:

```powershell
# Typed parameters
Get-BrokerMachine -RegistrationState Unregistered -InMaintenanceMode $false -MaxRecordCount 5000

# Filter expression (PowerShell-like operators, evaluated by the service)
Get-BrokerSession -Filter { SessionState -eq 'Disconnected' -and DesktopGroupName -like 'Finance*' } -MaxRecordCount 5000
```

Many typed parameters accept wildcards (`-MachineName 'CONTOSO\VDA-FIN*'`). Use `-Filter` for combinations and comparisons. Fall back to `Where-Object` for computed values (for example "disconnected longer than four hours").

### 6.3 Identity: Name vs. Uid

Objects have human names and integer `Uid`s. Relationships are often exposed as Uids (for example `Get-BrokerApplication` returns `AssociatedDesktopGroupUids`). Build a lookup hashtable once rather than calling `Get-BrokerDesktopGroup -Uid` in a loop.

### 6.4 Machine names

`MachineName` is `DOMAIN\HOSTNAME`. `DNSName` is the FQDN. `HostedMachineName` is the VM name on the hypervisor. Use the right one when you join to other data sources.

### 6.5 Pipelines and InputObject

Set/Remove cmdlets accept the objects returned by Get cmdlets, either by pipeline or `-InputObject`:

```powershell
Get-BrokerMachine -Tag 'Patch-Group-A' -MaxRecordCount 1000 | Set-BrokerMachine -InMaintenanceMode $true
```

That's powerful, and easy to over-apply. Always run the Get half by itself first and count the results.

## 7. Key cmdlet families

### 7.1 Machines: Get-BrokerMachine / Set-BrokerMachine

`Get-BrokerMachine` returns one object per VDA registered to (or configured in) the site. Useful properties:

| Property | Meaning |
|---|---|
| `MachineName`, `DNSName`, `HostedMachineName` | Identity |
| `CatalogName`, `DesktopGroupName` | Membership |
| `RegistrationState` | `Registered`, `Unregistered`, `Initializing`, `AgentError` |
| `PowerState` | `On`, `Off`, `Suspended`, `TurningOn`, `Unmanaged`, `Unknown` and so on |
| `InMaintenanceMode` | Boolean |
| `SessionCount` | Current sessions |
| `FaultState` | Summary health (for example `None`, `Unregistered`, `FailedToStart`, `StuckOnBoot`) |
| `LastDeregistrationReason`, `LastDeregistrationTime` | Why the VDA last dropped |
| `AgentVersion`, `OSType` | VDA version and OS |
| `Tags` | Admin-defined tags |

Maintenance mode for a machine:

```powershell
Set-BrokerMachine -MachineName 'CONTOSO\VDA01' -InMaintenanceMode $true -AdminAddress ddc01
```

Maintenance mode blocks **new** brokered connections to that machine. Existing sessions continue. For a single-session pooled desktop, it also stops the machine being power-managed into the available pool.

Tags: `Add-BrokerTag -Name 'Reboot-Sunday' -Machine 'CONTOSO\VDA01'`, `Get-BrokerTag`, `Remove-BrokerTag`. Tags are a clean way to define ad-hoc groups for scripts (patch rings, reboot waves) without restructuring delivery groups.

### 7.2 Sessions: Get-BrokerSession and friends

```powershell
Get-BrokerSession -UserName 'CONTOSO\jdoe' -AdminAddress ddc01
```

Notable properties are `UserName`, `MachineName`, `DesktopGroupName`, `SessionState` (`Active`, `Disconnected`, `Connected`, `PreparingSession` and others), `StartTime`, `SessionStateChangeTime`, `Protocol`, `ClientName`, `ClientAddress`, `ClientVersion`, `BrokeringTime` and `LaunchedViaHostName`. Newer releases expose idle-time information too. Check `Get-BrokerSession | Get-Member` on your version before you depend on any idle property. `SessionStateChangeTime` combined with `SessionState -eq 'Disconnected'` reliably gives you "disconnected since".

Actions:

- `Stop-BrokerSession`: logs off.
- `Disconnect-BrokerSession`: disconnects.
- `Send-BrokerSessionMessage`: shows a message box in the session (good before maintenance).
- `Get-BrokerApplicationInstance`: which apps are running in which session.

### 7.3 Delivery groups: Get-BrokerDesktopGroup

Delivery groups (called "desktop groups" in the SDK for historical reasons) carry capacity counters that make quick dashboards easy: `TotalDesktops`, `DesktopsAvailable`, `DesktopsInUse`, `DesktopsDisconnected`, `DesktopsUnregistered`, plus `Enabled`, `InMaintenanceMode`, `DeliveryType` (`DesktopsOnly`, `AppsOnly`, `DesktopsAndApps`), `DesktopKind` (`Shared`/`Private`) and `SessionSupport` (`SingleSession`/`MultiSession`).

Related cmdlets: `Set-BrokerDesktopGroup` (for example group-wide `-InMaintenanceMode`), `Get-BrokerAccessPolicyRule` and `Get-BrokerEntitlementPolicyRule` (who can see what), `Get-BrokerPowerTimeScheme` (power schedules), and `Get-BrokerRebootScheduleV2` (scheduled reboots, in newer releases; older ones used `Get-BrokerRebootSchedule`).

### 7.4 Catalogs: Get-BrokerCatalog

Catalogs describe how machines are built and allocated: `AllocationType` (`Random`/`Permanent`), `ProvisioningType` (`MCS`, `PVS`, `Manual`), `SessionSupport`, `PersistUserChanges`, `MinimumFunctionalLevel` (the VDA version floor) and counts (`UsedCount`, `AvailableCount`, `UnassignedCount`). For MCS catalogs, `ProvisioningSchemeId` links to the Machine Creation service.

### 7.5 Applications: Get-BrokerApplication

Published apps have `Name` (admin name, which may include an admin folder path), `PublishedName` (what users see), `CommandLineExecutable`, `CommandLineArguments`, `WorkingDirectory`, `Enabled`, `Visible`, `ApplicationType` (for example `HostedOnDesktop`), `AssociatedDesktopGroupUids` and, when user filtering is on, `AssociatedUserNames`. `New-BrokerApplication`, `Set-BrokerApplication`, `Add-BrokerApplication` (to associate with a group) and `Remove-BrokerApplication` handle publishing changes. `Get-BrokerApplicationGroup` covers application groups.

### 7.6 Power: New-BrokerHostingPowerAction

For power-managed machines (those with a hosting connection), you don't call the hypervisor directly. You queue a power action with the Broker:

```powershell
New-BrokerHostingPowerAction -MachineName 'CONTOSO\VDA01' -Action Restart -AdminAddress ddc01
Get-BrokerHostingPowerAction -State Pending,Started -MaxRecordCount 1000
```

Actions include `TurnOn`, `TurnOff`, `Shutdown`, `Reset`, `Restart`, `Suspend` and `Resume`. `Restart` and `Shutdown` are graceful (OS-level). `Reset` and `TurnOff` are hard. The Broker sends queued actions to the hypervisor at a pace set by the hosting connection's throttling settings (`Get-BrokerHypervisorConnection`, `Set-BrokerHypervisorConnection` and the connection's advanced settings in Studio). Throttling protects storage and the hypervisor from boot storms. Use it rather than fighting it.

### 7.7 MCS: Get-ProvScheme and Get-ProvTask

The Machine Creation service (the `Prov` cmdlets) manages MCS catalogs:

```powershell
Get-ProvScheme | Select-Object ProvisioningSchemeName, MasterImageVM, HostingUnitName, CpuCount, MemoryMB
Get-ProvTask -MaxRecordCount 50 | Sort-Object DateStarted -Descending |
    Select-Object Type, TaskState, Active, DateStarted, DateFinished, ProvisioningSchemeName
```

An image update is `Publish-ProvMasterVMImage -ProvisioningSchemeName <name> -MasterImageVM <XDHyp:\ path>`. It starts a task that `Get-ProvTask` tracks. After the publish, machines pick up the new image at their next restart (usually through a staged `Start-BrokerRebootCycle` or your own staggered reboot). `Get-ProvVM` lists the VMs MCS knows about, which helps when Broker and Prov disagree (orphaned VMs).

Hosting resources are browsed through the `XDHyp:` PSDrive:

```powershell
Get-ChildItem XDHyp:\Connections
Get-ChildItem 'XDHyp:\HostingUnits\MyCluster' | Where-Object ObjectType -eq 'VM'
```

### 7.8 Configuration Logging: Get-LogHighLevelOperation / Get-LogLowLevelOperation

Every change made through Studio or the SDK can be recorded by the Configuration Logging service:

- **High-level operations** are the admin's intent ("Set maintenance mode for 3 machines"), with `User`, `Source` (Studio or SDK), `StartTime`, `EndTime`, `IsSuccessful`, `Text`, `TargetTypes`, `AdminMachineIP`.
- **Low-level operations** are the individual service calls behind a high-level operation.

```powershell
Get-LogSite                                      # is logging enabled? is it mandatory?
Get-LogHighLevelOperation -MaxRecordCount 100 | Sort-Object StartTime -Descending
Get-LogLowLevelOperation -HighLevelOperationId <guid>
```

When Configuration Logging is set to **mandatory** (`Set-LogSite -State Mandatory`) and the logging database isn't available, configuration changes are **blocked**. That's a deliberate safety feature.

If you script changes, you can wrap them in your own high-level operation with `Start-LogHighLevelOperation` / `Stop-LogHighLevelOperation`, and pass `-LoggingId` to the Broker cmdlets so that low-level calls are grouped under a meaningful description such as "CHG12345 - Patch ring A maintenance on".

```powershell
$op = Start-LogHighLevelOperation -Text 'CHG12345: maintenance on for ring A' -Source 'Scripted' -AdminAddress ddc01
try {
    Get-BrokerMachine -Tag 'Ring-A' -AdminAddress ddc01 -MaxRecordCount 1000 |
        Set-BrokerMachine -InMaintenanceMode $true -LoggingId $op.Id -AdminAddress ddc01
    $ok = $true
} catch { $ok = $false; throw }
finally { Stop-LogHighLevelOperation -HighLevelOperationId $op.Id -IsSuccessful $ok -AdminAddress ddc01 }
```

### 7.9 Site and infrastructure

`Get-BrokerSite` (site settings and licensing configuration/counters), `Get-BrokerController` (controller state and version), `Get-BrokerServiceStatus` and the matching `Get-<Prefix>ServiceStatus` for every service, `Get-BrokerHypervisorConnection`, and `Get-ConfigSite` cover site health. In DaaS many of these are managed by Citrix and return limited data.

## 8. Common admin workflows

### 8.1 Find and fix unregistered machines

```powershell
$ap = @{ AdminAddress = 'ddc01'; MaxRecordCount = 10000 }
Get-BrokerMachine @ap -RegistrationState Unregistered -InMaintenanceMode $false |
    Select-Object MachineName, DesktopGroupName, PowerState, LastDeregistrationReason, LastDeregistrationTime |
    Sort-Object LastDeregistrationTime
```

Use `LastDeregistrationReason` to triage. Common values include `AgentShutdown`, `AgentSuspended`, `AgentRequested`, `AgentWrongActiveDirectoryOU`, `BrokerRegistrationLimitReached`, `InconsistentRegistrationCapabilities`, `ContactLost` and `SessionPrepareFailure`. Machines that are `On` but unregistered usually point to VDA, DNS, time skew, firewall (TCP 80/443 to the controllers or Cloud Connectors), or the `ListOfDDCs` registry/policy configuration.

See `scripts/Get-CitrixMachineHealth.ps1 -ProblemsOnly`.

### 8.2 Drain a server for patching

1. Put the machine in maintenance mode (`scripts/Set-CitrixMaintenanceMode.ps1 -MachineName ... -Enable $true -WhatIf`, then without `-WhatIf`).
2. Optionally warn users with `Send-BrokerSessionMessage`.
3. Wait for sessions to drain (`Get-BrokerSession -MachineName ...`).
4. Patch and restart.
5. Confirm `RegistrationState -eq 'Registered'`, then turn maintenance mode off.

### 8.3 Clean up stale disconnected sessions

Report first (`scripts/Get-CitrixDisconnectedSessions.ps1 -MinimumMinutes 480`), then act (`scripts/Invoke-CitrixLogoffIdleSessions.ps1 -DisconnectedMinutes 480 -WhatIf`). For the long term, set disconnected-session timers through policy (Citrix session-limit policies or Microsoft RDS session time limits) so the script stays an exception handler rather than a crutch.

### 8.4 Staggered reboots by tag

Tag machines into waves and use `scripts/Restart-CitrixMachinesByTag.ps1`. By default it skips machines with sessions and queues restarts in batches with a delay. For multi-session delivery groups, also consider the built-in reboot schedules (`New-BrokerRebootScheduleV2` on recent releases), which already handle draining and user warnings.

### 8.5 Image update (MCS)

1. Update and seal the master VM, then take a snapshot.
2. `Publish-ProvMasterVMImage` against the snapshot path and watch `Get-ProvTask` until it finishes.
3. Restart machines in waves (reboot schedule or staggered script).
4. Check `Get-BrokerMachine` image/registration state afterwards. Keep the previous snapshot so you can roll back.

### 8.6 Who has access to what

Combine `Get-BrokerApplication` (`AssociatedUserNames`, `AssociatedDesktopGroupUids`) with `Get-BrokerEntitlementPolicyRule` / `Get-BrokerAccessPolicyRule` (`IncludedUsers`) to produce an entitlement report, then expand AD groups with the ActiveDirectory module if you need user-level detail.

## 9. Reporting

General patterns that hold up in production:

- **Shape the output with `[pscustomobject]`.** Pick and rename properties explicitly rather than exporting raw SDK objects, which carry dozens of nested properties that turn into `System.String[]` in CSV.
- **Flatten arrays** with `-join ';'` (tags, associated users).
- **Compute durations** relative to one `$now` taken at the start, so the whole report is consistent.
- **Export** with `Export-Csv -NoTypeInformation` for analysts and `ConvertTo-Html -Fragment` for quick human-readable reports. `scripts/Export-CitrixSiteDocumentation.ps1` shows a multi-section HTML/CSV export.
- **Historical data** (logon duration, session trends, failures over time) lives in the **Monitor service database**, which is exposed through the **Monitor OData API** (`http://<ddc>/Citrix/Monitor/OData/v4/Data/`), not the Broker cmdlets. The Broker shows the *current* state. Use `Invoke-RestMethod -UseDefaultCredentials` against OData on-prem, or the Citrix Cloud monitoring APIs for DaaS, when you need history.
- **Licensing.** `Get-BrokerSite` exposes the license server, edition, model and some usage counters. Detailed per-feature usage comes from the License Server (`Citrix.Licensing.Admin.V1`) or the cloud console. `scripts/Get-CitrixLicenseUsage.ps1` reads only what `Get-BrokerSite` actually exposes and warns about anything missing.

## 10. Safe change practice

The Citrix SDK can change hundreds of objects in one pipeline. Treat it the way you'd treat bulk changes in Exchange Online or Entra ID.

1. **Read before you write.** Run the selection on its own, count it, and eyeball it:

   ```powershell
   $targets = Get-BrokerMachine -Tag 'Ring-A' -MaxRecordCount 1000
   $targets.Count
   $targets | Select-Object MachineName, SessionCount | Format-Table
   ```

2. **Use `-WhatIf` and `-Confirm`.** Many Citrix Set/Remove/New cmdlets don't implement `ShouldProcess` themselves, so wrap them in your own scripts with `[CmdletBinding(SupportsShouldProcess)]` and `$PSCmdlet.ShouldProcess(...)`. Every state-changing script in this repo does that, and the high-impact ones use `ConfirmImpact = 'High'` so they prompt by default.
3. **Change windows.** Draining, reboots and image rollouts belong in agreed maintenance windows. Warn users ahead of time (`Send-BrokerSessionMessage`), and remember that maintenance mode doesn't end existing sessions.
4. **Configuration Logging.** Keep it enabled (ideally mandatory), wrap scripted changes in `Start-LogHighLevelOperation`/`Stop-LogHighLevelOperation` with a change number in the text, and review `Get-LogHighLevelOperation` after the change.
5. **Snapshot first.** Export the current state before bulk edits (`scripts/Export-CitrixSiteDocumentation.ps1` or a targeted CSV), so you know exactly what to put back.
6. **Transcripts.** `Start-Transcript` in scheduled or change scripts gives you a local record that complements Configuration Logging.
7. **Limit the blast radius.** Use tags or specific delivery groups, never an unfiltered `Get-BrokerMachine | Set-BrokerMachine`. Add `-MaxRecordCount` and sanity checks (for example "abort if more than 50 machines match").
8. **Lab first.** Property names, enum values and parameter sets do change between releases. Validate scripts against a non-production site on the same version.

## 11. Scheduling

For recurring reports and cleanup:

- **Windows Task Scheduler** on a management server or a controller:

  ```powershell
  $action  = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument '-NoProfile -ExecutionPolicy Bypass -File "C:\Scripts\Get-CitrixMachineHealth.ps1" -AdminAddress ddc01.contoso.local -ProblemsOnly -OutputPath "C:\Reports\health.csv"'
  $trigger = New-ScheduledTaskTrigger -Daily -At 6am
  Register-ScheduledTask -TaskName 'Citrix Machine Health' -Action $action -Trigger $trigger -User 'CONTOSO\svc-citrix-report' -Password (Read-Host 'Password')
  ```

  Better still, run it as a **group Managed Service Account (gMSA)** so there's no password to manage: `New-ScheduledTaskPrincipal -UserId 'CONTOSO\gmsa-citrix$' -LogonType Password`, passed to `Register-ScheduledTask -Principal`.

- **Use `powershell.exe` (5.1)** when you rely on snap-ins. Snap-ins won't load under `pwsh.exe`.
- **DaaS.** The scheduled account needs the stored `Set-XDCredentials` profile available in *its* profile (run `Set-XDCredentials ... -StoreAs` as that account), or read the secure client from a vault at runtime.
- **Outputs.** Write to a dated file, prune old reports, and send results with your normal mail or Teams tooling. Keep secrets out of the script body.
- **Monitoring the job.** Log to a file or event log and alert on failures. A silently failing health report is worse than none.

## 12. Security and least privilege

### 12.1 Delegated Administration

CVAD uses role-based access: an **administrator** (AD user or group) is granted a **role** (a set of permissions) over a **scope** (a set of objects such as catalogs and delivery groups).

```powershell
Get-AdminAdministrator | Select-Object Name, Enabled, @{n='Rights';e={$_.Rights | ForEach-Object { "$($_.RoleName) @ $($_.ScopeName)" }}}
Get-AdminRole   | Select-Object Name, IsBuiltIn, Description
Get-AdminScope  | Select-Object Name, Description
Get-AdminPermission | Select-Object Id, GroupName, Description
```

Built-in roles include **Full Administrator**, **Read Only Administrator**, **Help Desk Administrator**, **Machine Catalog Administrator**, **Delivery Group Administrator** and **Host Administrator**. Create custom roles with `New-AdminRole` and `Add-AdminPermission`, and assign them with `New-AdminAdministrator` and `Add-AdminRight -Administrator ... -Role ... -Scope ...`.

### 12.2 Recommendations

- **Reporting accounts:** Read Only Administrator over the scopes they report on. That's enough for every `Get-*` script in this repo.
- **Help desk automation (logoff/disconnect):** Help Desk Administrator, scoped to the relevant delivery groups.
- **Maintenance/reboot automation:** a custom role with only the machine power and maintenance-mode permissions, scoped to the tagged groups.
- **Avoid Full Administrator for service accounts.** If one is compromised, it can change everything, including the admin assignments themselves.
- **Groups, not individuals.** Assign roles to AD groups, review membership regularly, and audit with `Get-AdminAdministrator` as part of site documentation.
- **DaaS:** Citrix Cloud administrators and API clients get custom access to DaaS roles in the cloud console. Create API clients from an admin that has only the access the automation needs. The secure client inherits that admin's permissions.
- **Credentials:** no plaintext secrets in scripts. Use gMSAs on-prem and SecretManagement or a vault for DaaS API secrets.
- **Execution:** sign your scripts and use an `AllSigned` or `RemoteSigned` execution policy on management hosts if your organization supports it, and restrict who can edit the scheduled script files.

## 13. Troubleshooting

| Symptom | Likely cause / fix |
|---|---|
| `The term 'Get-BrokerMachine' is not recognized` | SDK not loaded or not installed. `Add-PSSnapin Citrix*` (5.1) or `Import-Module Citrix.Broker.Admin.V2` (2203+). Check `Get-PSSnapin -Registered` / `Get-Module -ListAvailable Citrix*`. |
| `Add-PSSnapin` not recognized | You're in PowerShell 7. Use Windows PowerShell 5.1, or modules if your version supports them. |
| Reports stop at exactly 250 rows | Default `MaxRecordCount`. Set `-MaxRecordCount`. |
| `Insufficient administrative privilege` | Your account's role/scope doesn't cover the object. Check `Get-AdminAdministrator` and the effective rights. |
| Cmdlets hang or time out | Controller unreachable or service down. Test `Get-BrokerServiceStatus -AdminAddress <ddc>`, port 80/443 to the controller, DNS, and whether the site database is reachable (`Get-BrokerDBConnection`). |
| Changes rejected with a logging error | Configuration Logging set to Mandatory and its database is unavailable. Fix the database connection (`Get-LogDBConnection`). Don't just switch logging off. |
| Machines `Unregistered` with `PowerState On` | VDA can't reach controllers or Cloud Connectors: DNS, time sync, firewall, `ListOfDDCs`, or the VDA service. Look at `LastDeregistrationReason` and the VDA's Application event log (Citrix Desktop Service). |
| Power actions stay `Pending` | Hosting connection in maintenance or unavailable, or throttling limits. Check `Get-BrokerHypervisorConnection` (`State`, `IsReady`) and connection throttling settings. |
| MCS update fails | `Get-ProvTask` shows `TaskState` and `TerminatingError`. Check hypervisor permissions, storage space and snapshot path validity (`Get-ChildItem XDHyp:\...`). |
| DaaS: authentication prompt in a scheduled job | No stored credentials for that account. Run `Set-XDCredentials ... -StoreAs` as the job account, then `Get-XDAuthentication -ProfileName` in the script. |
| Property is `$null` that you expected | Property doesn't exist in your SDK version. Check with `Get-Member`. |

General technique:

```powershell
$m = Get-BrokerMachine -MachineName 'CONTOSO\VDA01'
$m | Format-List *          # see every property and its actual value
$m | Get-Member -MemberType Property
Get-Command Set-BrokerMachine -Syntax
```

Use `-Verbose` on SDK cmdlets for more detail. When a Studio action works but your script doesn't, find the same high-level operation in Configuration Logging, look at the low-level operations, and compare the parameters.

## 14. Quick reference

```powershell
# Load
Add-PSSnapin Citrix*                       # Windows PowerShell 5.1, all versions
Import-Module Citrix.Broker.Admin.V2       # 2203+ module form

# DaaS auth
Set-XDCredentials -CustomerId <id> -SecureClientFile <csv> -ProfileType CloudApi -StoreAs <name>
Get-XDAuthentication -ProfileName <name>

# Read
Get-BrokerSite
Get-BrokerController
Get-BrokerMachine        -MaxRecordCount 10000 -RegistrationState Unregistered
Get-BrokerSession        -MaxRecordCount 10000 -SessionState Disconnected
Get-BrokerDesktopGroup
Get-BrokerCatalog
Get-BrokerApplication    -MaxRecordCount 10000
Get-ProvScheme; Get-ProvTask
Get-LogHighLevelOperation -MaxRecordCount 100
Get-AdminAdministrator

# Change (wrap in ShouldProcess and Configuration Logging)
Set-BrokerMachine -MachineName 'DOM\VDA01' -InMaintenanceMode $true
Set-BrokerDesktopGroup -Name 'Group' -InMaintenanceMode $true
New-BrokerHostingPowerAction -MachineName 'DOM\VDA01' -Action Restart
Stop-BrokerSession -InputObject $session
Send-BrokerSessionMessage -InputObject $session -MessageStyle Information -Title 'Maintenance' -Text 'Please save your work.'
```

---

*Companion scripts for every workflow above are in [`scripts/`](scripts/). They're tested for syntax only, so validate them in a lab on your CVAD/DaaS version before you use them in production.*
