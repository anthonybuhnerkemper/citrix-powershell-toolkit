<#
.SYNOPSIS
    Reports current Citrix sessions.
.DESCRIPTION
    Lists brokered sessions with user, machine, state, protocol, client and duration. Optional CSV export.
.PARAMETER AdminAddress
    Delivery Controller FQDN (on-prem). Omit for Citrix DaaS (uses Get-XDAuthentication context).
.PARAMETER DesktopGroupName
    Optional delivery group filter.
.PARAMETER MaxRecordCount
    Broker SDK returns 250 records by default; raised here.
.PARAMETER OutputPath
    Optional CSV path.
.EXAMPLE
    .\Get-CitrixSessionReport.ps1 -AdminAddress ddc01.contoso.local -OutputPath .\sessions.csv
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

$now = Get-Date
$report = Get-BrokerSession @bp | ForEach-Object {
    [pscustomobject]@{
        UserName         = $_.UserName
        MachineName      = $_.MachineName
        DesktopGroupName = $_.DesktopGroupName
        SessionState     = $_.SessionState
        Protocol         = $_.Protocol
        ClientName       = $_.ClientName
        ClientAddress    = $_.ClientAddress
        StartTime        = $_.StartTime
        StateChangeTime  = $_.SessionStateChangeTime
        DurationHours    = if ($_.StartTime) { [math]::Round(($now - $_.StartTime).TotalHours, 2) } else { $null }
    }
} | Sort-Object DesktopGroupName, UserName

Write-Verbose ("{0} sessions returned" -f @($report).Count)
if ($OutputPath) { $report | Export-Csv -Path $OutputPath -NoTypeInformation; Write-Host "Saved $OutputPath" }
$report
