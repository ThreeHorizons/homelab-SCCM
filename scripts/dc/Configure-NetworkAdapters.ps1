#Requires -Version 5.1
#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Configures network adapters for proper multi-homed Domain Controller operation.

.DESCRIPTION
    This script MUST run BEFORE DC promotion to prevent DNS and AD issues.

    THE PROBLEM WITH MULTI-HOMED DCs:
    ---------------------------------
    VirtualBox (and many virtualization platforms) create multiple network adapters:
    - NAT adapter: Provides internet access (e.g., 10.0.2.15)
    - Host-Only adapter: Lab network communication (e.g., 192.168.56.10)

    When a server with multiple adapters is promoted to a Domain Controller,
    Windows registers DNS records for ALL adapters by default. This causes:

    1. DC Locator (nltest) returning wrong IPs
    2. Kerberos authentication failures
    3. DHCP authorization failures ("Failed to initialize directory service resources")
    4. AD replication issues
    5. Client domain join failures

    THE SOLUTION:
    -------------
    Configure adapters BEFORE DC promotion:
    1. Disable DNS registration on the NAT adapter
    2. Set NAT adapter to higher metric (lower routing priority)
    3. Disable IPv6 on NAT adapter (prevents IPv6 address registration)
    4. Ensure the lab network adapter has a static IP and correct DNS settings

    This ensures the DC only advertises and uses the correct lab network IP.

    WHAT IS INTERFACE METRIC?
    -------------------------
    The interface metric determines routing priority. LOWER metric = HIGHER priority.
    When Windows has multiple routes to a destination, it uses the adapter with
    the lowest metric. Setting the NAT adapter to metric 100 and lab adapter to
    metric 10 ensures lab traffic uses the correct adapter.

    WHAT IS DNS REGISTRATION?
    -------------------------
    By default, Windows adapters register their IP addresses in DNS when:
    - The computer joins a domain
    - The DNS Client service starts
    - An IP address changes

    For a DC, this means BOTH IPs get registered, causing the problems above.
    Disabling registration on the NAT adapter prevents this.

.PARAMETER LabAdapterIP
    The static IP address for the lab network adapter. Defaults to "192.168.56.10".

.PARAMETER LabSubnetMask
    The subnet mask for the lab network. Defaults to 24 (255.255.255.0).

.PARAMETER LabGateway
    The default gateway for the lab network. Defaults to "192.168.56.1".

.PARAMETER DNSServer
    The DNS server to use. For the first DC, this should be 127.0.0.1 (itself).
    Defaults to "127.0.0.1".

.PARAMETER DisableIPv6
    Whether to disable IPv6 on all adapters. Defaults to $true.
    IPv6 can cause DCs to advertise wrong addresses.

.PARAMETER Force
    Skip confirmation prompts.

.EXAMPLE
    # Run before DC promotion
    .\Configure-NetworkAdapters.ps1 -Force

.EXAMPLE
    # Custom IP configuration
    .\Configure-NetworkAdapters.ps1 -LabAdapterIP "192.168.56.10" -DNSServer "127.0.0.1"

.NOTES
    Author: SCCM Homelab Project
    Version: 1.0

    CRITICAL: Run this script BEFORE Promote-DC.ps1!
    Running after promotion will not fully fix the issue (requires AD cleanup).

    VIRTUALBOX ADAPTER NAMING:
    - First adapter: "Ethernet" (usually NAT)
    - Second adapter: "Ethernet 2" (usually Host-Only)
    This may vary depending on VirtualBox version and VM configuration.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$LabAdapterIP = "192.168.56.10",

    [Parameter(Mandatory = $false)]
    [int]$LabSubnetMask = 24,

    [Parameter(Mandatory = $false)]
    [string]$LabGateway = "192.168.56.1",

    [Parameter(Mandatory = $false)]
    [string]$DNSServer = "127.0.0.1",

    [Parameter(Mandatory = $false)]
    [bool]$DisableIPv6 = $true,

    [Parameter(Mandatory = $false)]
    [switch]$Force
)

# =============================================================================
# SCRIPT INITIALIZATION
# =============================================================================

$ErrorActionPreference = 'Stop'

$ScriptDir = Split-Path -Parent $PSScriptRoot

try {
    Import-Module (Join-Path $ScriptDir "modules\Logger.psm1") -Force
    Import-Module (Join-Path $ScriptDir "modules\Validator.psm1") -Force
}
catch {
    Write-Host "[ERROR] Failed to import modules: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "[INFO] Running in standalone mode with basic logging" -ForegroundColor Yellow

    # Define minimal logging functions if modules aren't available
    function Write-Log { param($Message, $Level = "INFO") Write-Host "[$Level] $Message" }
    function Write-LogSection { param($Title) Write-Host "`n=== $Title ===" }
    function Write-LogError { param($ErrorRecord, $Message) Write-Host "[ERROR] $Message : $($ErrorRecord.Exception.Message)" -ForegroundColor Red }
    function Initialize-Logging { param($ScriptName) Write-Host "Starting $ScriptName" }
    function Complete-Logging { param($Success) Write-Host "Script completed (Success: $Success)" }
}

Initialize-Logging -ScriptName "Configure-NetworkAdapters"

# =============================================================================
# MAIN SCRIPT LOGIC
# =============================================================================

try {
    Write-LogSection "Configuring Network Adapters for Domain Controller"

    # -------------------------------------------------------------------------
    # STEP 1: Identify Network Adapters
    # -------------------------------------------------------------------------
    Write-Log "Identifying network adapters..." -Level INFO

    <#
    IDENTIFYING NAT vs HOST-ONLY ADAPTERS:
    --------------------------------------
    VirtualBox typically assigns:
    - NAT adapter: 10.0.2.x range (DHCP from VirtualBox)
    - Host-Only adapter: 192.168.56.x range (static or DHCP from host)

    We identify them by their current IP addresses, not by name,
    because adapter names can vary.
    #>

    # Get all active adapters
    $adapters = Get-NetAdapter | Where-Object { $_.Status -eq 'Up' }

    if ($adapters.Count -lt 2) {
        Write-Log "Warning: Expected 2 adapters but found $($adapters.Count)" -Level WARN
        Write-Log "This script is designed for VirtualBox VMs with NAT + Host-Only adapters" -Level WARN
    }

    # Identify adapters by IP range
    $natAdapter = $null
    $labAdapter = $null

    foreach ($adapter in $adapters) {
        $ipAddress = (Get-NetIPAddress -InterfaceIndex $adapter.ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue).IPAddress

        if ($ipAddress -like "10.0.2.*") {
            $natAdapter = $adapter
            Write-Log "  NAT Adapter: $($adapter.Name) ($ipAddress)" -Level INFO
        }
        elseif ($ipAddress -like "192.168.56.*" -or $ipAddress -eq $LabAdapterIP) {
            $labAdapter = $adapter
            Write-Log "  Lab Adapter: $($adapter.Name) ($ipAddress)" -Level INFO
        }
        else {
            Write-Log "  Unknown Adapter: $($adapter.Name) ($ipAddress)" -Level DEBUG
        }
    }

    # Fallback: If we couldn't identify by IP, use naming convention
    if (-not $natAdapter) {
        $natAdapter = Get-NetAdapter -Name "Ethernet" -ErrorAction SilentlyContinue
        if ($natAdapter) {
            Write-Log "  NAT Adapter (by name): $($natAdapter.Name)" -Level INFO
        }
    }

    if (-not $labAdapter) {
        $labAdapter = Get-NetAdapter -Name "Ethernet 2" -ErrorAction SilentlyContinue
        if ($labAdapter) {
            Write-Log "  Lab Adapter (by name): $($labAdapter.Name)" -Level INFO
        }
    }

    if (-not $labAdapter) {
        Write-Log "Could not identify lab adapter! Check network configuration." -Level ERROR
        Complete-Logging -Success $false
        exit 1
    }

    # -------------------------------------------------------------------------
    # STEP 2: Configure Lab Adapter (Host-Only)
    # -------------------------------------------------------------------------
    Write-LogSection "Configuring Lab Adapter"

    Write-Log "Setting static IP: $LabAdapterIP/$LabSubnetMask" -Level INFO

    # Remove existing IP configuration
    $existingIP = Get-NetIPAddress -InterfaceIndex $labAdapter.ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue
    if ($existingIP -and $existingIP.IPAddress -ne $LabAdapterIP) {
        Write-Log "  Removing existing IP: $($existingIP.IPAddress)" -Level DEBUG
        Remove-NetIPAddress -InterfaceIndex $labAdapter.ifIndex -AddressFamily IPv4 -Confirm:$false -ErrorAction SilentlyContinue
        Remove-NetRoute -InterfaceIndex $labAdapter.ifIndex -AddressFamily IPv4 -Confirm:$false -ErrorAction SilentlyContinue
    }

    # Set new static IP (only if not already set)
    $currentIP = (Get-NetIPAddress -InterfaceIndex $labAdapter.ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue).IPAddress
    if ($currentIP -ne $LabAdapterIP) {
        New-NetIPAddress -InterfaceIndex $labAdapter.ifIndex -IPAddress $LabAdapterIP -PrefixLength $LabSubnetMask -ErrorAction SilentlyContinue
        Write-Log "  Static IP configured: $LabAdapterIP" -Level SUCCESS
    }
    else {
        Write-Log "  Static IP already set: $LabAdapterIP" -Level SUCCESS
    }

    # Set DNS server
    Write-Log "Setting DNS server: $DNSServer" -Level INFO
    Set-DnsClientServerAddress -InterfaceIndex $labAdapter.ifIndex -ServerAddresses $DNSServer
    Write-Log "  DNS server configured" -Level SUCCESS

    # Enable DNS registration on lab adapter
    Write-Log "Enabling DNS registration on lab adapter" -Level INFO
    Set-DnsClient -InterfaceIndex $labAdapter.ifIndex -RegisterThisConnectionsAddress $true
    Write-Log "  DNS registration enabled" -Level SUCCESS

    # Set low metric (high priority)
    Write-Log "Setting interface metric to 10 (high priority)" -Level INFO
    Set-NetIPInterface -InterfaceIndex $labAdapter.ifIndex -InterfaceMetric 10
    Write-Log "  Metric set to 10" -Level SUCCESS

    # -------------------------------------------------------------------------
    # STEP 3: Configure NAT Adapter
    # -------------------------------------------------------------------------
    if ($natAdapter) {
        Write-LogSection "Configuring NAT Adapter"

        # Disable DNS registration
        Write-Log "Disabling DNS registration on NAT adapter" -Level INFO
        Set-DnsClient -InterfaceIndex $natAdapter.ifIndex -RegisterThisConnectionsAddress $false
        Write-Log "  DNS registration disabled" -Level SUCCESS

        # Clear any DNS suffix
        Write-Log "Clearing connection-specific DNS suffix" -Level INFO
        Set-DnsClient -InterfaceIndex $natAdapter.ifIndex -ConnectionSpecificSuffix ""
        Write-Log "  DNS suffix cleared" -Level SUCCESS

        # Set high metric (low priority)
        Write-Log "Setting interface metric to 100 (low priority)" -Level INFO
        Set-NetIPInterface -InterfaceIndex $natAdapter.ifIndex -InterfaceMetric 100
        Write-Log "  Metric set to 100" -Level SUCCESS

        # Point NAT adapter DNS to the lab adapter IP (not external)
        # This prevents external DNS queries from bypassing our DNS server
        Write-Log "Setting NAT adapter DNS to lab DNS ($LabAdapterIP)" -Level INFO
        Set-DnsClientServerAddress -InterfaceIndex $natAdapter.ifIndex -ServerAddresses $LabAdapterIP
        Write-Log "  NAT DNS pointing to lab" -Level SUCCESS

        # Disable IPv6 on NAT adapter if requested
        if ($DisableIPv6) {
            Write-Log "Disabling IPv6 on NAT adapter" -Level INFO
            Disable-NetAdapterBinding -Name $natAdapter.Name -ComponentID ms_tcpip6 -ErrorAction SilentlyContinue
            Write-Log "  IPv6 disabled on NAT adapter" -Level SUCCESS
        }
    }
    else {
        Write-Log "No NAT adapter found - skipping NAT configuration" -Level WARN
    }

    # -------------------------------------------------------------------------
    # STEP 4: Disable IPv6 on Lab Adapter (Optional but Recommended)
    # -------------------------------------------------------------------------
    if ($DisableIPv6 -and $labAdapter) {
        Write-Log "Disabling IPv6 on lab adapter" -Level INFO
        Disable-NetAdapterBinding -Name $labAdapter.Name -ComponentID ms_tcpip6 -ErrorAction SilentlyContinue
        Write-Log "  IPv6 disabled on lab adapter" -Level SUCCESS
    }

    # -------------------------------------------------------------------------
    # STEP 5: Flush DNS Cache
    # -------------------------------------------------------------------------
    Write-LogSection "Flushing DNS Cache"

    Write-Log "Clearing DNS client cache..." -Level INFO
    Clear-DnsClientCache
    Write-Log "  DNS cache cleared" -Level SUCCESS

    # -------------------------------------------------------------------------
    # STEP 6: Re-register DNS
    # -------------------------------------------------------------------------
    Write-Log "Re-registering DNS..." -Level INFO
    ipconfig /registerdns | Out-Null
    Write-Log "  DNS re-registration triggered" -Level SUCCESS

    # -------------------------------------------------------------------------
    # STEP 7: Verification
    # -------------------------------------------------------------------------
    Write-LogSection "Verification"

    Write-Log "Network Adapter Configuration:" -Level INFO

    # Show final configuration
    $adaptersInfo = Get-NetAdapter | Where-Object { $_.Status -eq 'Up' } | ForEach-Object {
        $adapter = $_
        $ipInfo = Get-NetIPAddress -InterfaceIndex $adapter.ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue
        $dnsClient = Get-DnsClient -InterfaceIndex $adapter.ifIndex -ErrorAction SilentlyContinue
        $metric = (Get-NetIPInterface -InterfaceIndex $adapter.ifIndex -AddressFamily IPv4).InterfaceMetric
        $dnsServers = (Get-DnsClientServerAddress -InterfaceIndex $adapter.ifIndex -AddressFamily IPv4).ServerAddresses

        [PSCustomObject]@{
            Name            = $adapter.Name
            IP              = $ipInfo.IPAddress
            Metric          = $metric
            DNSRegistration = $dnsClient.RegisterThisConnectionsAddress
            DNSServers      = $dnsServers -join ", "
        }
    }

    foreach ($info in $adaptersInfo) {
        Write-Log "  $($info.Name):" -Level INFO
        Write-Log "    IP:               $($info.IP)" -Level INFO
        Write-Log "    Metric:           $($info.Metric)" -Level INFO
        Write-Log "    DNS Registration: $($info.DNSRegistration)" -Level INFO
        Write-Log "    DNS Servers:      $($info.DNSServers)" -Level INFO
    }

    Write-Log "" -Level INFO
    Write-Log "Network adapter configuration complete!" -Level SUCCESS
    Write-Log "" -Level INFO
    Write-Log "IMPORTANT: Run this script BEFORE DC promotion (Promote-DC.ps1)" -Level WARN
    Write-Log "If DC is already promoted, you may need to clean up DNS records manually." -Level WARN

    Complete-Logging -Success $true
    exit 0
}
catch {
    Write-LogError -ErrorRecord $_ -Message "An error occurred during network configuration"
    Complete-Logging -Success $false
    exit 1
}
