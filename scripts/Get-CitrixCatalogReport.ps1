<#
.SYNOPSIS
    Reports machine catalogs, including MCS provisioning scheme details.
.DESCRIPTION
    Lists catalogs with allocation/provisioning type and machine counts. For MCS catalogs,
    joins Get-ProvScheme (master image, hosting unit, CPU/memory) and the most recent
    Get-ProvTask entry so you can see the last image update/provisioning operation.
.PARAMETER AdminAddress
    Delivery Controller FQDN. Omit for Citrix DaaS.
.PARAMETER OutputPath
    Optional CSV path.
.EXAMPLE
    .\Get-CitrixCatalogReport.ps1 -AdminAddress ddc01 | Format-Table Name,ProvisioningType,MasterImageVM
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
$ap = @{}
if ($AdminAddress) { $ap.AdminAddress = $AdminAddress }
$haveProv = [bool](Get-Command -Name Get-ProvScheme -ErrorAction SilentlyContinue)

$schemes = @{}
$lastTask = @{}
if ($haveProv) {
    Get-ProvScheme -MaxRecordCount $MaxRecordCount @ap | ForEach-Object { $schemes[[string]$_.ProvisioningSchemeUid] = $_ }
    Get-ProvTask -MaxRecordCount $MaxRecordCount @ap | Sort-Object DateStarted | ForEach-Object {
        if ($_.ProvisioningSchemeUid) { $lastTask[[string]$_.ProvisioningSchemeUid] = $_ }
    }
} else {
    Write-Warning 'Machine Creation (Prov) SDK not loaded; MCS details omitted.'
}

$report = Get-BrokerCatalog -MaxRecordCount $MaxRecordCount @ap | ForEach-Object {
    $key = [string]$_.ProvisioningSchemeId
    $ps  = if ($key) { $schemes[$key] } else { $null }
    $t   = if ($key) { $lastTask[$key] } else { $null }
    [pscustomobject]@{
        Name                 = $_.Name
        AllocationType       = $_.AllocationType
        ProvisioningType     = $_.ProvisioningType
        SessionSupport       = $_.SessionSupport
        PersistUserChanges   = $_.PersistUserChanges
        MinimumFunctionalLvl = $_.MinimumFunctionalLevel
        UsedCount            = $_.UsedCount
        AvailableCount       = $_.AvailableCount
        UnassignedCount      = $_.UnassignedCount
        MasterImageVM        = $ps.MasterImageVM
        HostingUnitName      = $ps.HostingUnitName
        CpuCount             = $ps.CpuCount
        MemoryMB             = $ps.MemoryMB
        LastProvTaskType     = $t.Type
        LastProvTaskState    = $t.TaskState
        LastProvTaskStarted  = $t.DateStarted
    }
} | Sort-Object Name
if ($OutputPath) { $report | Export-Csv -Path $OutputPath -NoTypeInformation; Write-Host "Saved $OutputPath" }
$report
