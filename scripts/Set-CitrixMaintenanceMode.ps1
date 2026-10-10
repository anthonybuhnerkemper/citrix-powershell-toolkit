<#
.SYNOPSIS
    Turns maintenance mode on or off for machines or a delivery group. Supports -WhatIf/-Confirm.
.DESCRIPTION
    Machine-level maintenance mode is set with Set-BrokerMachine -InMaintenanceMode; delivery-group-level with Set-BrokerDesktopGroup -InMaintenanceMode. Maintenance mode stops new brokered connections; existing sessions continue.
.PARAMETER AdminAddress
    Delivery Controller FQDN. Omit for Citrix DaaS.
.PARAMETER MachineName
    One or more machine names in DOMAIN\NAME form (as shown by Get-BrokerMachine).
.PARAMETER DesktopGroupName
    Delivery group name. With -Scope Machines, all machines in the group are changed; with -Scope Group, the group flag itself is changed.
.PARAMETER Scope
    Machines (default) or Group.
.PARAMETER Enable
    $true to enter maintenance mode, $false to exit.
.EXAMPLE
    .\Set-CitrixMaintenanceMode.ps1 -MachineName 'CONTOSO\VDA01','CONTOSO\VDA02' -Enable $true -WhatIf
.EXAMPLE
    .\Set-CitrixMaintenanceMode.ps1 -DesktopGroupName 'Finance Apps' -Scope Group -Enable $false
.NOTES
    Author : Anthony Buhnerkemper
    License: MIT
    Requires the Citrix Virtual Apps and Desktops PowerShell SDK (on-prem) or the
    Citrix DaaS Remote PowerShell SDK. Tested for syntax only - validate in a lab first.
#>
[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium', DefaultParameterSetName = 'ByMachine')]
param(
    [Parameter()] [string]$AdminAddress,
    [Parameter(Mandatory, ParameterSetName = 'ByMachine', ValueFromPipelineByPropertyName)] [string[]]$MachineName,
    [Parameter(Mandatory, ParameterSetName = 'ByGroup')] [string]$DesktopGroupName,
    [Parameter(ParameterSetName = 'ByGroup')] [ValidateSet('Machines', 'Group')] [string]$Scope = 'Machines',
    [Parameter(Mandatory)] [bool]$Enable
)
begin {
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
    $verb = if ($Enable) { 'Enable maintenance mode' } else { 'Disable maintenance mode' }
}
process {
    if ($PSCmdlet.ParameterSetName -eq 'ByGroup' -and $Scope -eq 'Group') {
        if ($PSCmdlet.ShouldProcess("Delivery group '$DesktopGroupName'", $verb)) {
            Set-BrokerDesktopGroup -Name $DesktopGroupName -InMaintenanceMode $Enable @ap
        }
        return
    }
    $machines = if ($PSCmdlet.ParameterSetName -eq 'ByGroup') {
        Get-BrokerMachine -DesktopGroupName $DesktopGroupName -MaxRecordCount 10000 @ap
    } else {
        foreach ($n in $MachineName) { Get-BrokerMachine -MachineName $n @ap }
    }
    foreach ($m in $machines) {
        if ($m.InMaintenanceMode -eq $Enable) { Write-Verbose "$($m.MachineName) already in desired state"; continue }
        if ($PSCmdlet.ShouldProcess($m.MachineName, $verb)) {
            Set-BrokerMachine -InputObject $m -InMaintenanceMode $Enable @ap
            [pscustomobject]@{ MachineName = $m.MachineName; InMaintenanceMode = $Enable }
        }
    }
}
