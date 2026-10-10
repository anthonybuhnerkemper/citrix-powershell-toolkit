<#
.SYNOPSIS
    Restarts machines that carry a given tag, in staggered batches. Supports -WhatIf/-Confirm.
.DESCRIPTION
    Selects machines with Get-BrokerMachine -Tag and queues restart power actions with New-BrokerHostingPowerAction in batches, waiting between batches. By default machines with active sessions are skipped. Power actions are queued and executed by the Broker's hosting connection throttling; this script only controls queuing pace. Maintenance mode is not changed; use Set-CitrixMaintenanceMode.ps1 separately if you need to drain first.
.PARAMETER AdminAddress
    Delivery Controller FQDN. Omit for Citrix DaaS.
.PARAMETER Tag
    Broker tag name (Get-BrokerTag).
.PARAMETER BatchSize
    Machines per batch (default 5).
.PARAMETER DelaySeconds
    Wait between batches (default 300).
.PARAMETER IncludeMachinesWithSessions
    Also restart machines that have sessions (users will be disconnected - use with care).
.PARAMETER Action
    Restart (graceful, default) or Reset (hard).
.EXAMPLE
    .\Restart-CitrixMachinesByTag.ps1 -AdminAddress ddc01 -Tag 'Reboot-Sunday' -BatchSize 10 -WhatIf
.NOTES
    Author : Anthony Buhnerkemper
    License: MIT
    Requires the Citrix Virtual Apps and Desktops PowerShell SDK (on-prem) or the
    Citrix DaaS Remote PowerShell SDK. Tested for syntax only - validate in a lab first.
#>
[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
param(
    [Parameter()] [string]$AdminAddress,
    [Parameter(Mandatory)] [string]$Tag,
    [Parameter()] [ValidateRange(1, 500)] [int]$BatchSize = 5,
    [Parameter()] [ValidateRange(0, 86400)] [int]$DelaySeconds = 300,
    [Parameter()] [switch]$IncludeMachinesWithSessions,
    [Parameter()] [ValidateSet('Restart', 'Reset')] [string]$Action = 'Restart'
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

$machines = @(Get-BrokerMachine -Tag $Tag -MaxRecordCount 10000 @ap | Where-Object {
    $_.HypervisorConnectionUid -and $_.PowerState -eq 'On'
})
if (-not $IncludeMachinesWithSessions) {
    $skipped = $machines | Where-Object { $_.SessionCount -gt 0 }
    foreach ($s in $skipped) { Write-Warning "Skipping $($s.MachineName): $($s.SessionCount) session(s)" }
    $machines = @($machines | Where-Object { $_.SessionCount -eq 0 })
}
if ($machines.Count -eq 0) { Write-Host "No eligible power-managed machines tagged '$Tag'."; return }
Write-Host ("{0} machine(s) eligible, batch size {1}, delay {2}s" -f $machines.Count, $BatchSize, $DelaySeconds)

for ($i = 0; $i -lt $machines.Count; $i += $BatchSize) {
    $batch = $machines[$i..([math]::Min($i + $BatchSize, $machines.Count) - 1)]
    foreach ($m in $batch) {
        if ($PSCmdlet.ShouldProcess($m.MachineName, "$Action (power action)")) {
            try {
                $pa = New-BrokerHostingPowerAction -MachineName $m.MachineName -Action $Action @ap -ErrorAction Stop
                [pscustomobject]@{ MachineName = $m.MachineName; Action = $Action; PowerActionUid = $pa.Uid; State = $pa.State }
            } catch {
                Write-Warning "Failed to queue $Action for $($m.MachineName): $($_.Exception.Message)"
            }
        }
    }
    $more = ($i + $BatchSize) -lt $machines.Count
    if ($more -and $DelaySeconds -gt 0 -and -not $WhatIfPreference) {
        Write-Verbose "Waiting $DelaySeconds seconds before next batch"
        Start-Sleep -Seconds $DelaySeconds
    }
}
Write-Host "Track progress with: Get-BrokerHostingPowerAction -State Pending,Started"
