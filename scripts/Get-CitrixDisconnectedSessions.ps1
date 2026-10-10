<#
.SYNOPSIS
    Lists disconnected sessions older than a threshold.
.DESCRIPTION
    Uses SessionStateChangeTime to compute how long each session has been disconnected.
.PARAMETER AdminAddress
    Delivery Controller FQDN. Omit for Citrix DaaS.
.PARAMETER MinimumMinutes
    Only return sessions disconnected at least this long (default 60).
.PARAMETER DesktopGroupName
    Optional delivery group filter.
.EXAMPLE
    .\Get-CitrixDisconnectedSessions.ps1 -MinimumMinutes 240
.NOTES
    Author : Anthony Buhnerkemper
    License: MIT
    Requires the Citrix Virtual Apps and Desktops PowerShell SDK (on-prem) or the
    Citrix DaaS Remote PowerShell SDK. Tested for syntax only - validate in a lab first.
#>
[CmdletBinding()]
param(
    [Parameter()] [string]$AdminAddress,
    [Parameter()] [ValidateRange(0, 100000)] [int]$MinimumMinutes = 60,
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
$bp = @{ MaxRecordCount = $MaxRecordCount; SessionState = 'Disconnected' }
if ($AdminAddress)     { $bp.AdminAddress = $AdminAddress }
if ($DesktopGroupName) { $bp.DesktopGroupName = $DesktopGroupName }

$now = Get-Date
$report = Get-BrokerSession @bp | ForEach-Object {
    $mins = if ($_.SessionStateChangeTime) { [math]::Round(($now - $_.SessionStateChangeTime).TotalMinutes) } else { $null }
    [pscustomobject]@{
        UserName             = $_.UserName
        MachineName          = $_.MachineName
        DesktopGroupName     = $_.DesktopGroupName
        DisconnectedSince    = $_.SessionStateChangeTime
        DisconnectedMinutes  = $mins
        StartTime            = $_.StartTime
    }
} | Where-Object { $_.DisconnectedMinutes -ge $MinimumMinutes } | Sort-Object DisconnectedMinutes -Descending
if ($OutputPath) { $report | Export-Csv -Path $OutputPath -NoTypeInformation; Write-Host "Saved $OutputPath" }
$report
