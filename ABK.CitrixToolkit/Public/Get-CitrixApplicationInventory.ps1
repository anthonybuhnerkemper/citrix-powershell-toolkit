function Get-CitrixApplicationInventory {
    <#
    .SYNOPSIS
        Inventories published applications.
    .DESCRIPTION
        Lists published apps with executable, arguments, enabled/visible state, associated delivery groups and user/group assignments.
    .PARAMETER AdminAddress
        Delivery Controller FQDN. Omit for Citrix DaaS.
    .PARAMETER OutputPath
        Optional CSV path.
    .EXAMPLE
        Get-CitrixApplicationInventory -OutputPath .\apps.csv
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

    # Map desktop group Uid -> Name once, rather than querying per app.
    $dgMap = @{}
    Get-BrokerDesktopGroup @bp | ForEach-Object { $dgMap[$_.Uid] = $_.Name }

    $report = Get-BrokerApplication @bp | ForEach-Object {
        [pscustomobject]@{
            Name            = $_.Name
            PublishedName   = $_.PublishedName
            ApplicationType = $_.ApplicationType
            Enabled         = $_.Enabled
            Visible         = $_.Visible
            Executable      = $_.CommandLineExecutable
            Arguments       = $_.CommandLineArguments
            WorkingDir      = $_.WorkingDirectory
            AdminFolder     = $_.AdminFolderName
            DeliveryGroups  = (@($_.AssociatedDesktopGroupUids | ForEach-Object { $dgMap[$_] }) -join ';')
            UserFilter      = $_.UserFilterEnabled
            AssignedUsers   = ($_.AssociatedUserNames -join ';')
        }
    } | Sort-Object AdminFolder, Name
    if ($OutputPath) { $report | Export-Csv -Path $OutputPath -NoTypeInformation; Write-Host "Saved $OutputPath" }
    $report
}

