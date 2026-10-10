<#
.SYNOPSIS
    Reports machine health: registration, maintenance mode and power state.
.DESCRIPTION
    Flags machines that are unregistered, in maintenance mode, powered off/unknown, or have a fault state. Use -ProblemsOnly to show only flagged machines.
.PARAMETER AdminAddress
    Delivery Controller FQDN. Omit for Citrix DaaS.
.PARAMETER DesktopGroupName
    Optional delivery group filter.
.PARAMETER ProblemsOnly
    Return only machines with at least one issue.
.PARAMETER MaxRecordCount
    Max records from the Broker SDK (default 250 in SDK).
.PARAMETER OutputPath
    Optional CSV path.
.EXAMPLE
    .\Get-CitrixMachineHealth.ps1 -AdminAddress ddc01 -ProblemsOnly
.NOTES
    Author : Anthony Buhnerkemper
    License: MIT
    Requires the Citrix Virtual Apps and Desktops PowerShell SDK (on-prem) or the
    Citrix DaaS Remote PowerShell SDK. Tested for syntax only - validate in a lab first.
#>
[CmdletBinding()]
param(
    [Parameter()] [string]$AdminAddress,
    [Parameter()] [string]$DesktopGroupName,
    [Parameter()] [switch]$ProblemsOnly,
    [Parameter()] [int]$MaxRecordCount = 10000,
    [Parameter()] [string]$OutputPath
)
function Import-CitrixSdk {
    <# Loads the Citrix SDK: modules (CVAD 2203+ / Remote PowerShell SDK) first, snap-ins as fallback. #>
    if (Get-Command -Name Get-BrokerSite -ErrorAction SilentlyContinue) { return }
    $mod = Get-Module -ListAvailable -Name Citrix.Broker.Admin.V2 | Select-Object -First 1
    if ($mod) { Import-Module $mod -ErrorAction Stop; return }
    if (Get-Command -Name Add-PSSnapin -ErrorAction SilentlyContinue) {
        Add-PSSnapin -Name Citrix* -ErrorAction SilentlyContinue
    }
    if (-not (Get-Command -Name Get-BrokerSite -ErrorAction SilentlyContinue)) {
        throw "Citrix Broker SDK not found. Run on a Delivery Controller, a machine with Studio/the SDK installed, or with the DaaS Remote PowerShell SDK."
    }
}
Import-CitrixSdk
$bp = @{ MaxRecordCount = $MaxRecordCount }
if ($AdminAddress)     { $bp.AdminAddress = $AdminAddress }
if ($DesktopGroupName) { $bp.DesktopGroupName = $DesktopGroupName }

$report = foreach ($m in Get-BrokerMachine @bp) {
    $issues = @()
    if ($m.RegistrationState -ne 'Registered') { $issues += "Registration=$($m.RegistrationState)" }
    if ($m.InMaintenanceMode)                  { $issues += 'MaintenanceMode' }
    if ($m.PowerState -in 'Off','Unknown','Unmanaged' -and $m.ProvisioningType -ne 'Manual') { $issues += "Power=$($m.PowerState)" }
    if ($m.FaultState -and $m.FaultState -ne 'None') { $issues += "Fault=$($m.FaultState)" }
    [pscustomobject]@{
        MachineName           = $m.MachineName
        DesktopGroupName      = $m.DesktopGroupName
        CatalogName           = $m.CatalogName
        RegistrationState     = $m.RegistrationState
        InMaintenanceMode     = $m.InMaintenanceMode
        PowerState            = $m.PowerState
        FaultState            = $m.FaultState
        SessionCount          = $m.SessionCount
        AgentVersion          = $m.AgentVersion
        LastDeregReason       = $m.LastDeregistrationReason
        LastDeregTime         = $m.LastDeregistrationTime
        Tags                  = ($m.Tags -join ';')
        Issues                = ($issues -join '; ')
    }
}
if ($ProblemsOnly) { $report = $report | Where-Object Issues }
$report = $report | Sort-Object DesktopGroupName, MachineName
if ($OutputPath) { $report | Export-Csv -Path $OutputPath -NoTypeInformation; Write-Host "Saved $OutputPath" }
$report
