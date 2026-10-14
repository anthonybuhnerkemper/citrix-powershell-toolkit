function Invoke-CitrixLogoffIdleSessions {
    <#
    .SYNOPSIS
        Logs off long-disconnected (idle) sessions. Supports -WhatIf/-Confirm.
    .DESCRIPTION
        Finds sessions that have been Disconnected for at least -DisconnectedMinutes and logs them off with Stop-BrokerSession. ConfirmImpact is High, so you are prompted per session unless -Confirm:$false is supplied. Always run with -WhatIf first. Policy-based disconnect/logoff timers (Citrix policies or RDS session limits) are usually the better long-term control; this is for cleanup.
    .PARAMETER AdminAddress
        Delivery Controller FQDN. Omit for Citrix DaaS.
    .PARAMETER DisconnectedMinutes
        Minimum minutes disconnected before logoff (default 480).
    .PARAMETER DesktopGroupName
        Optional delivery group filter (recommended).
    .PARAMETER ExcludeUser
        Usernames (DOMAIN\user) never to log off.
    .EXAMPLE
        Invoke-CitrixLogoffIdleSessions -AdminAddress ddc01 -DesktopGroupName 'Shared Desktops' -WhatIf
    .NOTES
        Author : Anthony Buhnerkemper
        License: MIT
        Requires the Citrix Virtual Apps and Desktops PowerShell SDK (on-prem) or the
        Citrix DaaS Remote PowerShell SDK. Tested for syntax only - validate in a lab first.
    #>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
    param(
        [Parameter()] [string]$AdminAddress,
        [Parameter()] [ValidateRange(15, 100000)] [int]$DisconnectedMinutes = 480,
        [Parameter()] [string]$DesktopGroupName,
        [Parameter()] [string[]]$ExcludeUser = @(),
        [Parameter()] [int]$MaxRecordCount = 10000
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
    $ap = @{}
    if ($AdminAddress) { $ap.AdminAddress = $AdminAddress }

    $cutoff = (Get-Date).AddMinutes(-$DisconnectedMinutes)
    $targets = Get-BrokerSession @bp | Where-Object {
        $_.SessionStateChangeTime -and $_.SessionStateChangeTime -lt $cutoff -and $_.UserName -notin $ExcludeUser
    }
    Write-Verbose ("{0} session(s) disconnected before {1}" -f @($targets).Count, $cutoff)

    foreach ($s in $targets) {
        $label = "$($s.UserName) on $($s.MachineName) (disconnected since $($s.SessionStateChangeTime))"
        if ($PSCmdlet.ShouldProcess($label, 'Log off session')) {
            try {
                Stop-BrokerSession -InputObject $s @ap -ErrorAction Stop
                [pscustomobject]@{ UserName = $s.UserName; MachineName = $s.MachineName; Result = 'LogoffRequested' }
            } catch {
                Write-Warning "Failed: $label - $($_.Exception.Message)"
                [pscustomobject]@{ UserName = $s.UserName; MachineName = $s.MachineName; Result = "Error: $($_.Exception.Message)" }
            }
        }
    }
}

