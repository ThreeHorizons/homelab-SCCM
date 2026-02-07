#Requires -Version 5.1
#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Configures the DNS client to use the lab domain controller for DNS resolution.

.DESCRIPTION
    This script configures the host-only network adapter to use DC01 (192.168.56.10)
    as its DNS server. This is required before joining the domain because:

    1. Domain join uses DNS to find domain controllers
    2. AD requires proper DNS resolution for SRV records
    3. Kerberos authentication requires DNS

    WHY THIS IS NECESSARY:
    ----------------------
    When VMs first boot, they get DNS settings from:
    - DHCP (if using DHCP)
    - Static configuration
    - VirtualBox's NAT adapter (which points to external DNS)

    For domain join to work, the machine MUST be able to resolve:
    - dc01.lab.local
    - _ldap._tcp.lab.local (SRV record for LDAP)
    - _kerberos._tcp.lab.local (SRV record for Kerberos)

    External DNS servers (like 8.8.8.8) don't know about our lab.local domain,
    so we must point DNS to our domain controller.

    NETWORK ADAPTERS IN VIRTUALBOX:
    -------------------------------
    Our VMs have two adapters:
    1. NAT Adapter (Ethernet): Internet access, gets DNS from VirtualBox
    2. Host-Only Adapter (Ethernet 2): Lab network, needs lab DNS

    This script modifies the host-only adapter's DNS settings.

.PARAMETER DNSServer
    The DNS server IP address. Defaults to DC01's IP (192.168.56.10).

.PARAMETER InterfaceAlias
    The name of the network adapter to configure. Auto-detected if not specified.
    Looks for adapters with IPs in the 192.168.56.x range.

.PARAMETER Force
    Skip confirmation prompts.

.EXAMPLE
    .\Set-LabDNS.ps1

.EXAMPLE
    .\Set-LabDNS.ps1 -DNSServer "192.168.56.10" -Force

.NOTES
    Author: SCCM Homelab Project
    Version: 1.0

    PREREQUISITES:
    - Network adapters must be configured
    - DC01 must be running and reachable

    RUN THIS ON:
    - SCCM01 (before domain join)
    - CLIENT01, CLIENT02, etc. (before domain join)
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$DNSServer = "192.168.56.10",

    [Parameter(Mandatory = $false)]
    [string]$InterfaceAlias = $null,

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
    # Fallback if modules not available
    function Write-Log {
        param([string]$Message, [string]$Level = "INFO")
        $colors = @{ DEBUG = 'Gray'; INFO = 'White'; SUCCESS = 'Green'; WARN = 'Yellow'; ERROR = 'Red' }
        Write-Host "[$(Get-Date -Format 'HH:mm:ss')] [$Level] $Message" -ForegroundColor $colors[$Level]
    }
    function Initialize-Logging { param([string]$ScriptName) }
    function Complete-Logging { param([bool]$Success) }
    function Write-LogSection { param([string]$Title) Write-Host "`n=== $Title ===`n" -ForegroundColor Cyan }
}

Initialize-Logging -ScriptName "Set-LabDNS"

# =============================================================================
# MAIN SCRIPT LOGIC
# =============================================================================

try {
    Write-LogSection "Configuring Lab DNS Settings"

    # -------------------------------------------------------------------------
    # STEP 1: Find the Host-Only Network Adapter
    # -------------------------------------------------------------------------
    Write-Log "Identifying network adapters..." -Level INFO

    <#
    FINDING THE RIGHT ADAPTER:
    --------------------------
    We need to find the host-only adapter (the one connected to 192.168.56.x).
    VirtualBox names adapters "Ethernet", "Ethernet 2", etc.

    Strategy:
    1. If InterfaceAlias provided, use that
    2. Otherwise, look for an adapter with an IP in the 192.168.56.x range
    3. Or look for adapter description containing "Host-Only"
    #>

    if ([string]::IsNullOrEmpty($InterfaceAlias)) {
        # Auto-detect the host-only adapter
        Write-Log "Auto-detecting host-only adapter..." -Level INFO

        # Get all adapters that are up
        $adapters = Get-NetAdapter | Where-Object { $_.Status -eq 'Up' }

        foreach ($adapter in $adapters) {
            # Check if this adapter has a 192.168.56.x IP
            $ip = Get-NetIPAddress -InterfaceIndex $adapter.InterfaceIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue

            if ($ip -and $ip.IPAddress -like "192.168.56.*") {
                $InterfaceAlias = $adapter.Name
                Write-Log "  Found host-only adapter: $InterfaceAlias (IP: $($ip.IPAddress))" -Level SUCCESS
                break
            }
        }

        # If still not found, look for "Host-Only" in description
        if ([string]::IsNullOrEmpty($InterfaceAlias)) {
            $hostOnlyAdapter = $adapters | Where-Object { $_.InterfaceDescription -like "*Host-Only*" } | Select-Object -First 1

            if ($hostOnlyAdapter) {
                $InterfaceAlias = $hostOnlyAdapter.Name
                Write-Log "  Found adapter by description: $InterfaceAlias" -Level SUCCESS
            }
        }

        # If still not found, try common names
        if ([string]::IsNullOrEmpty($InterfaceAlias)) {
            $commonNames = @("Ethernet 2", "Ethernet 3", "vEthernet (HostOnly)")
            foreach ($name in $commonNames) {
                $adapter = Get-NetAdapter -Name $name -ErrorAction SilentlyContinue
                if ($adapter -and $adapter.Status -eq 'Up') {
                    $InterfaceAlias = $name
                    Write-Log "  Using adapter: $InterfaceAlias" -Level SUCCESS
                    break
                }
            }
        }

        if ([string]::IsNullOrEmpty($InterfaceAlias)) {
            Write-Log "Could not find a suitable network adapter!" -Level ERROR
            Write-Log "Available adapters:" -Level INFO
            Get-NetAdapter | ForEach-Object { Write-Log "  $($_.Name) - $($_.Status) - $($_.InterfaceDescription)" -Level INFO }
            exit 1
        }
    }

    # -------------------------------------------------------------------------
    # STEP 2: Display Current Configuration
    # -------------------------------------------------------------------------
    Write-LogSection "Current DNS Configuration"

    $currentDNS = Get-DnsClientServerAddress -InterfaceAlias $InterfaceAlias -AddressFamily IPv4

    Write-Log "Interface: $InterfaceAlias" -Level INFO
    Write-Log "Current DNS Servers: $($currentDNS.ServerAddresses -join ', ')" -Level INFO

    if ($currentDNS.ServerAddresses -contains $DNSServer) {
        Write-Log "DNS is already configured to use $DNSServer" -Level SUCCESS
        Complete-Logging -Success $true
        exit 0
    }

    # -------------------------------------------------------------------------
    # STEP 3: Test Connectivity to DNS Server
    # -------------------------------------------------------------------------
    Write-Log "Testing connectivity to DNS server ($DNSServer)..." -Level INFO

    $pingResult = Test-Connection -ComputerName $DNSServer -Count 2 -Quiet

    if ($pingResult) {
        Write-Log "  DNS server is reachable" -Level SUCCESS
    }
    else {
        Write-Log "  WARNING: DNS server is not responding to ping!" -Level WARN
        Write-Log "  This might be OK if ICMP is blocked, but DNS might not work." -Level WARN

        if (-not $Force) {
            $continue = Read-Host "Continue anyway? (Y/N)"
            if ($continue -notmatch "^[Yy]") {
                Write-Log "Operation cancelled." -Level WARN
                exit 1
            }
        }
    }

    # -------------------------------------------------------------------------
    # STEP 4: Configure DNS
    # -------------------------------------------------------------------------
    Write-LogSection "Applying DNS Configuration"

    Write-Log "Setting DNS server to $DNSServer on $InterfaceAlias..." -Level INFO

    <#
    SET-DNSCLIENTSERVERADDRESS:
    ---------------------------
    This cmdlet configures the DNS server addresses for a network adapter.

    -InterfaceAlias: The adapter name (e.g., "Ethernet 2")
    -ServerAddresses: Array of DNS server IPs to use

    The change takes effect immediately, no restart required.
    #>

    Set-DnsClientServerAddress -InterfaceAlias $InterfaceAlias -ServerAddresses $DNSServer

    Write-Log "  DNS server configured" -Level SUCCESS

    # -------------------------------------------------------------------------
    # STEP 5: Clear DNS Cache
    # -------------------------------------------------------------------------
    Write-Log "Clearing DNS cache..." -Level INFO

    <#
    WHY CLEAR THE CACHE:
    --------------------
    Windows caches DNS lookups for performance. If you previously tried to
    resolve lab.local and got "not found", that negative result is cached.
    Clearing the cache ensures fresh lookups with the new DNS server.
    #>

    Clear-DnsClientCache

    Write-Log "  DNS cache cleared" -Level SUCCESS

    # -------------------------------------------------------------------------
    # STEP 6: Verify New Configuration
    # -------------------------------------------------------------------------
    Write-LogSection "Verifying Configuration"

    $newDNS = Get-DnsClientServerAddress -InterfaceAlias $InterfaceAlias -AddressFamily IPv4

    Write-Log "Interface: $InterfaceAlias" -Level INFO
    Write-Log "New DNS Servers: $($newDNS.ServerAddresses -join ', ')" -Level INFO

    # -------------------------------------------------------------------------
    # STEP 7: Test DNS Resolution
    # -------------------------------------------------------------------------
    Write-Log "Testing DNS resolution..." -Level INFO

    # Give DNS a moment to be ready
    Start-Sleep -Seconds 2

    # Test resolving the domain
    $tests = @(
        @{ Name = "dc01.lab.local"; Description = "Domain Controller" },
        @{ Name = "lab.local"; Description = "Domain" }
    )

    $allTestsPassed = $true

    foreach ($test in $tests) {
        try {
            $result = Resolve-DnsName -Name $test.Name -Type A -DnsOnly -ErrorAction Stop
            Write-Log "  $($test.Name) -> $($result.IPAddress -join ', ')" -Level SUCCESS
        }
        catch {
            Write-Log "  $($test.Name) -> FAILED ($($_.Exception.Message))" -Level WARN
            $allTestsPassed = $false
        }
    }

    if ($allTestsPassed) {
        Write-Log "" -Level INFO
        Write-Log "DNS configuration successful!" -Level SUCCESS
        Write-Log "This machine can now resolve lab.local domain names." -Level INFO
    }
    else {
        Write-Log "" -Level INFO
        Write-Log "DNS configured but some lookups failed." -Level WARN
        Write-Log "This is normal if DC01 is not fully configured yet." -Level INFO
        Write-Log "Domain join may still work if _ldap._tcp.lab.local resolves." -Level INFO
    }

    Write-Log "" -Level INFO
    Write-Log "Next Steps:" -Level INFO
    Write-Log "  Run Join-LabDomain.ps1 to join this computer to the domain." -Level INFO

    Complete-Logging -Success $true
    exit 0
}
catch {
    Write-Log "An error occurred: $($_.Exception.Message)" -Level ERROR
    Write-Log "Stack: $($_.ScriptStackTrace)" -Level DEBUG
    Complete-Logging -Success $false
    exit 1
}
