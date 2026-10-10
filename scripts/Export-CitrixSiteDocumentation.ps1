<#
.SYNOPSIS
    Exports a point-in-time documentation snapshot of a Citrix site to HTML and CSV.
.DESCRIPTION
    Collects site, controllers, hypervisor connections, catalogs, delivery groups,
    applications, machines, tags and administrators, then writes one CSV per section plus
    a single HTML file. Read-only. Useful for change records, audits and DR documentation.
.PARAMETER AdminAddress
    Delivery Controller FQDN. Omit for Citrix DaaS.
.PARAMETER OutputFolder
    Folder for the output (created if missing). Default: .\CitrixSiteDoc_<yyyyMMdd-HHmm>
.PARAMETER SkipMachines
    Skip the per-machine table (large sites).
.EXAMPLE
    .\Export-CitrixSiteDocumentation.ps1 -AdminAddress ddc01 -OutputFolder C:\Reports\Citrix
.NOTES
    Author : Anthony Buhnerkemper
    License: MIT
    Requires the Citrix Virtual Apps and Desktops PowerShell SDK (on-prem) or the
    Citrix DaaS Remote PowerShell SDK. Tested for syntax only - validate in a lab first.
#>
[CmdletBinding()]
param(
    [Parameter()] [string]$AdminAddress,
    [Parameter()] [string]$OutputFolder = (Join-Path -Path (Get-Location) -ChildPath ("CitrixSiteDoc_{0:yyyyMMdd-HHmm}" -f (Get-Date))),
    [Parameter()] [switch]$SkipMachines,
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
$ap = @{}
if ($AdminAddress) { $ap.AdminAddress = $AdminAddress }
$bp = @{ MaxRecordCount = $MaxRecordCount } + $ap
New-Item -ItemType Directory -Path $OutputFolder -Force | Out-Null

# Each section: name -> scriptblock returning selected objects. Failures are caught per section.
$sections = [ordered]@{
    'Site'                  = { Get-BrokerSite @ap | Select-Object Name, LicenseServerName, LicenseServerPort, LicenseEdition, LicenseModel, ConnectionLeasingEnabled, LocalHostCacheEnabled }
    'Controllers'           = { Get-BrokerController @bp | Select-Object DNSName, State, ControllerVersion, OSType, LastActivityTime }
    'HypervisorConnections' = { Get-BrokerHypervisorConnection @bp | Select-Object Name, State, IsReady, PreferredController, MachineCount }
    'Catalogs'              = { Get-BrokerCatalog @bp | Select-Object Name, AllocationType, ProvisioningType, SessionSupport, PersistUserChanges, MinimumFunctionalLevel, UsedCount, AvailableCount }
    'DeliveryGroups'        = { Get-BrokerDesktopGroup @bp | Select-Object Name, Enabled, InMaintenanceMode, DeliveryType, DesktopKind, SessionSupport, TotalDesktops, DesktopsAvailable, DesktopsInUse, DesktopsUnregistered }
    'Applications'          = { Get-BrokerApplication @bp | Select-Object Name, PublishedName, Enabled, Visible, CommandLineExecutable, CommandLineArguments, AdminFolderName }
    'Tags'                  = { Get-BrokerTag @bp | Select-Object Name, Description }
    'Administrators'        = {
        if (Get-Command Get-AdminAdministrator -ErrorAction SilentlyContinue) {
            Get-AdminAdministrator @ap | Select-Object Name, Enabled, @{ n = 'RolesAndScopes'; e = { ($_.Rights | ForEach-Object { "$($_.RoleName) @ $($_.ScopeName)" }) -join '; ' } }
        }
    }
}
if (-not $SkipMachines) {
    $sections['Machines'] = { Get-BrokerMachine @bp | Select-Object MachineName, DesktopGroupName, CatalogName, RegistrationState, PowerState, InMaintenanceMode, AgentVersion, OSType, @{ n = 'Tags'; e = { $_.Tags -join ';' } } }
}

$html = New-Object System.Collections.Generic.List[string]
foreach ($name in $sections.Keys) {
    Write-Verbose "Collecting $name"
    try {
        $data = @(& $sections[$name])
    } catch {
        Write-Warning "Section $name failed: $($_.Exception.Message)"
        $data = @()
    }
    if ($data.Count -gt 0) {
        $data | Export-Csv -Path (Join-Path $OutputFolder "$name.csv") -NoTypeInformation
        $html.Add(($data | ConvertTo-Html -Fragment -PreContent "<h2>$name ($($data.Count))</h2>"))
    } else {
        $html.Add("<h2>$name</h2><p><em>No data or not available.</em></p>")
    }
}

$style = '<style>body{font-family:Segoe UI,Arial,sans-serif;font-size:12px}table{border-collapse:collapse;margin-bottom:20px}th,td{border:1px solid #ccc;padding:4px 8px}th{background:#eee}</style>'
$title = "Citrix Site Documentation - $(Get-Date -Format 'yyyy-MM-dd HH:mm')"
$htmlPath = Join-Path $OutputFolder 'CitrixSiteDocumentation.html'
ConvertTo-Html -Title $title -Head $style -Body ("<h1>$title</h1>" + ($html -join "`n")) | Set-Content -Path $htmlPath -Encoding UTF8
Write-Host "Documentation written to $OutputFolder"
Get-Item $htmlPath
