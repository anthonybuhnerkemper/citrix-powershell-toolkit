<#
.SYNOPSIS
    Summarizes delivery groups.
.DESCRIPTION
    Capacity and state summary for each delivery group using the counters exposed by Get-BrokerDesktopGroup.
.PARAMETER AdminAddress
    Delivery Controller FQDN. Omit for Citrix DaaS.
.PARAMETER OutputPath
    Optional CSV path.
.EXAMPLE
    .\Get-CitrixDeliveryGroupSummary.ps1 -AdminAddress ddc01 | Format-Table
.NOTES
    Author : Anthony Buhnerkemper
    License: MIT
    Requires the Citrix Virtual Apps and Desktops PowerShell SDK (on-prem) or the
    Citrix DaaS Remote PowerShell SDK. Tested for syntax only - validate in a lab first.
#>
[CmdletBinding()]
param(
    [Parameter()] [string]$AdminAddress,
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
if ($AdminAddress) { $bp.AdminAddress = $AdminAddress }

$report = Get-BrokerDesktopGroup @bp | ForEach-Object {
    [pscustomobject]@{
        Name                 = $_.Name
        Enabled              = $_.Enabled
        InMaintenanceMode    = $_.InMaintenanceMode
        DeliveryType         = $_.DeliveryType
        DesktopKind          = $_.DesktopKind
        SessionSupport       = $_.SessionSupport
        TotalDesktops        = $_.TotalDesktops
        DesktopsAvailable    = $_.DesktopsAvailable
        DesktopsInUse        = $_.DesktopsInUse
        DesktopsDisconnected = $_.DesktopsDisconnected
        DesktopsUnregistered = $_.DesktopsUnregistered
        DesktopsFaulted      = $_.DesktopsFaulted
        Sessions             = $_.Sessions
        TotalApplications    = $_.TotalApplications
    }
} | Sort-Object Name
if ($OutputPath) { $report | Export-Csv -Path $OutputPath -NoTypeInformation; Write-Host "Saved $OutputPath" }
$report
