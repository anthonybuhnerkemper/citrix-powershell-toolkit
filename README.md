# Citrix PowerShell Toolkit

[![PowerShell Gallery](https://img.shields.io/powershellgallery/v/ABK.CitrixToolkit?label=PowerShell%20Gallery)](https://www.powershellgallery.com/packages/ABK.CitrixToolkit) [![Downloads](https://img.shields.io/powershellgallery/dt/ABK.CitrixToolkit)](https://www.powershellgallery.com/packages/ABK.CitrixToolkit)

PowerShell scripts and a long-form guide for managing **Citrix Virtual Apps and Desktops (on-prem)** and **Citrix DaaS** with the Citrix PowerShell SDK. The scripts lean toward read-only reporting. The few that change state support `-WhatIf` and `-Confirm`.

📘 **Start with the guide:** [GUIDE.md](GUIDE.md), *Managing Citrix Virtual Apps and Desktops with the PowerShell SDK*


## Install from PowerShell Gallery

```powershell
Install-Module ABK.CitrixToolkit -Scope CurrentUser
Import-Module ABK.CitrixToolkit
Get-Command -Module ABK.CitrixToolkit
```

Each script is also exported as a function with the same name and parameters (e.g. `Get-Help <FunctionName> -Full`). Prerequisite modules (Microsoft Graph, ExchangeOnlineManagement, ConfigMgr console, Citrix SDK, etc.) are not auto-installed; install the ones the functions you use need, as described below. The module source lives in [`ABK.CitrixToolkit/`](ABK.CitrixToolkit/).

## Requirements

- Windows PowerShell 5.1 (recommended; required if you load the SDK as snap-ins). PowerShell 7 works only where your SDK version supports modules.
- One of:
  - **On-prem:** the Citrix CVAD PowerShell SDK (installed with Delivery Controllers and Studio). CVAD 2203+ also ships modules (`Citrix.Broker.Admin.V2` etc.).
  - **Citrix DaaS:** the Citrix DaaS Remote PowerShell SDK, authenticated with `Set-XDCredentials` / `Get-XDAuthentication`.
- A Citrix delegated admin role appropriate to the script. Read Only Administrator covers all `Get-*` scripts.

Every script loads the SDK itself: module first, then `Add-PSSnapin Citrix*` as a fallback. Every script takes an optional `-AdminAddress` (Delivery Controller FQDN). Leave it out for DaaS.

## Scripts

| Script | Type | Description |
|---|---|---|
| `Get-CitrixSessionReport.ps1` | Read-only | All sessions with user, machine, state, protocol, client, duration |
| `Get-CitrixMachineHealth.ps1` | Read-only | Registration, maintenance, power and fault state; `-ProblemsOnly` |
| `Get-CitrixDeliveryGroupSummary.ps1` | Read-only | Delivery group capacity and state counters |
| `Get-CitrixApplicationInventory.ps1` | Read-only | Published apps, executables, delivery groups, assigned users |
| `Get-CitrixDisconnectedSessions.ps1` | Read-only | Sessions disconnected longer than N minutes |
| `Get-CitrixCatalogReport.ps1` | Read-only | Catalogs plus MCS scheme (master image, CPU/RAM) and last Prov task |
| `Get-CitrixConfigLogReport.ps1` | Read-only | Configuration Logging: who changed what, when (optional low-level detail) |
| `Get-CitrixLicenseUsage.ps1` | Read-only | License config/usage counters exposed by `Get-BrokerSite` (not a full license-server inventory; see script help) |
| `Export-CitrixSiteDocumentation.ps1` | Read-only | Multi-section site snapshot to HTML + CSV |
| `Invoke-CitrixLogoffIdleSessions.ps1` | **Changes state** | Logs off long-disconnected sessions (ShouldProcess, ConfirmImpact High) |
| `Set-CitrixMaintenanceMode.ps1` | **Changes state** | Maintenance mode on/off for machines or a delivery group (ShouldProcess) |
| `Restart-CitrixMachinesByTag.ps1` | **Changes state** | Staggered restart of tagged machines in batches (ShouldProcess, ConfirmImpact High) |

Each script has comment-based help: `Get-Help .\scripts\<name>.ps1 -Full`.

## Examples

```powershell
.\scripts\Get-CitrixMachineHealth.ps1 -AdminAddress ddc01.contoso.local -ProblemsOnly -OutputPath .\health.csv
.\scripts\Set-CitrixMaintenanceMode.ps1 -DesktopGroupName 'Finance Apps' -Enable $true -WhatIf
.\scripts\Restart-CitrixMachinesByTag.ps1 -Tag 'Reboot-Wave1' -BatchSize 10 -DelaySeconds 600 -WhatIf
.\scripts\Export-CitrixSiteDocumentation.ps1 -AdminAddress ddc01.contoso.local -OutputFolder C:\Reports\Citrix
```

## Disclaimer

These scripts are **tested for syntax only** (they parse cleanly with the PowerShell parser). They have **not** been run against a live Citrix site. SDK property names and parameters vary between CVAD/DaaS releases. **Validate everything in a lab first**, run state-changing scripts with `-WhatIf` before you run them for real, and follow your change-management process. Provided as-is under the MIT License, with no warranty.

## License

[MIT](LICENSE) © 2026 Anthony Buhnerkemper
