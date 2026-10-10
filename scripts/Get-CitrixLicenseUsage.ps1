<#
.SYNOPSIS
    Reports license usage counters the Broker exposes through Get-BrokerSite.
.DESCRIPTION
    Get-BrokerSite returns the site's licensing configuration and usage counters
    (license server, edition, model, peak concurrent users, grace state). This script
    reads only those properties and reports any that are missing in your SDK version
    instead of guessing.

    What this is NOT: a full license-server inventory. For per-feature installed vs. in-use
    counts query the license server itself (Citrix.Licensing.Admin.V1: Get-LicCertificate /
    Get-LicInventory / Get-LicUsage) or the Licensing Manager console. In Citrix DaaS,
    license usage is reported in the Citrix Cloud console, and Get-BrokerSite licensing
    fields may be empty or not meaningful.
.PARAMETER AdminAddress
    Delivery Controller FQDN.
.EXAMPLE
    .\Get-CitrixLicenseUsage.ps1 -AdminAddress ddc01
.NOTES
    Author : Anthony Buhnerkemper
    License: MIT
    Requires the Citrix Virtual Apps and Desktops PowerShell SDK (on-prem) or the
    Citrix DaaS Remote PowerShell SDK. Tested for syntax only - validate in a lab first.
#>
[CmdletBinding()]
param(
    [Parameter()] [string]$AdminAddress
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
$site = Get-BrokerSite @ap

$wanted = 'Name', 'LicenseServerName', 'LicenseServerPort', 'LicenseEdition', 'LicenseModel',
          'LicensedSessionsActive', 'PeakConcurrentLicenseUsers', 'TotalUniqueLicenseUsers',
          'LicensingGracePeriodActive', 'LicensingOutOfBoxGracePeriodActive', 'LicensingGraceHoursLeft',
          'LicensingBurstOfUsageActive'
$out = [ordered]@{}
$available = $site.PSObject.Properties.Name
foreach ($p in $wanted) {
    if ($available -contains $p) { $out[$p] = $site.$p }
    else { Write-Verbose "Property '$p' not exposed by this SDK version" }
}
$missing = $wanted | Where-Object { $available -notcontains $_ }
if ($missing) { Write-Warning ("Not available in this SDK version: {0}" -f ($missing -join ', ')) }
[pscustomobject]$out
