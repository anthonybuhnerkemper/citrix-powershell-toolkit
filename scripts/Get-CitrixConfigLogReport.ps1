<#
.SYNOPSIS
    Reports Configuration Logging entries (who changed what, when).
.DESCRIPTION
    Uses Get-LogHighLevelOperation filtered by start time, optionally expanding each
    operation into its low-level operations (Get-LogLowLevelOperation -HighLevelOperationId).
    Configuration Logging must be enabled for the site (Get-LogSite shows its state).
.PARAMETER AdminAddress
    Delivery Controller FQDN. Omit for Citrix DaaS.
.PARAMETER Days
    How many days back to report (default 7).
.PARAMETER User
    Optional filter on the administrator name (wildcards allowed).
.PARAMETER IncludeLowLevel
    Include low-level operation detail (slower).
.PARAMETER OutputPath
    Optional CSV path.
.EXAMPLE
    .\Get-CitrixConfigLogReport.ps1 -Days 1 -IncludeLowLevel | Out-GridView
.NOTES
    Author : Anthony Buhnerkemper
    License: MIT
    Requires the Citrix Virtual Apps and Desktops PowerShell SDK (on-prem) or the
    Citrix DaaS Remote PowerShell SDK. Tested for syntax only - validate in a lab first.
#>
[CmdletBinding()]
param(
    [Parameter()] [string]$AdminAddress,
    [Parameter()] [ValidateRange(1, 3650)] [int]$Days = 7,
    [Parameter()] [string]$User = '*',
    [Parameter()] [switch]$IncludeLowLevel,
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
$ap = @{}
if ($AdminAddress) { $ap.AdminAddress = $AdminAddress }
$since = (Get-Date).AddDays(-$Days)

$ops = Get-LogHighLevelOperation -Filter ("StartTime -ge '{0}'" -f $since.ToString('yyyy-MM-ddTHH:mm:ss')) -MaxRecordCount $MaxRecordCount @ap |
    Where-Object { $_.User -like $User } | Sort-Object StartTime -Descending

$report = foreach ($op in $ops) {
    $base = [ordered]@{
        StartTime     = $op.StartTime
        EndTime       = $op.EndTime
        User          = $op.User
        Source        = $op.Source
        OperationType = $op.OperationType
        Text          = $op.Text
        IsSuccessful  = $op.IsSuccessful
        TargetTypes   = ($op.TargetTypes -join ';')
        AdminMachine  = $op.AdminMachineIP
    }
    if ($IncludeLowLevel) {
        $low = Get-LogLowLevelOperation -HighLevelOperationId $op.Id @ap
        if (-not $low) { [pscustomobject]$base; continue }
        foreach ($l in $low) {
            $row = [ordered]@{} + $base
            $row.LowLevelText    = $l.Text
            $row.LowLevelSuccess = $l.IsSuccessful
            [pscustomobject]$row
        }
    } else {
        [pscustomobject]$base
    }
}
if ($OutputPath) { $report | Export-Csv -Path $OutputPath -NoTypeInformation; Write-Host "Saved $OutputPath" }
$report
