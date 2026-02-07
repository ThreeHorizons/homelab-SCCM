#Requires -Version 5.1
#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Configures DNS Server settings for the SCCM lab environment.

.DESCRIPTION
    This script configures DNS after the domain controller has been promoted.
    It creates reverse lookup zones, adds static records, and configures
    forwarders for internet resolution.

    WHY THIS SCRIPT IS NEEDED:
    --------------------------
    When you promote a DC with -InstallDNS:$true, Windows creates:
    - A forward lookup zone for the domain (lab.local)
    - AD-integrated zone records for domain services
    - SRV records for LDAP, Kerberos, GC, etc.

    But it does NOT automatically create:
    - Reverse lookup zones (for IP-to-name resolution)
    - Static records for servers (SCCM01, etc.)
    - DNS forwarders (for internet name resolution)

    This script completes the DNS configuration.

    DNS CONCEPTS FOR THIS SCRIPT:
    -----------------------------

    FORWARD LOOKUP ZONE: Maps names to IP addresses.
        lab.local -> A records for hosts
        dc01.lab.local -> 192.168.56.10

    REVERSE LOOKUP ZONE: Maps IP addresses to names (PTR records).
        192.168.56.10 -> dc01.lab.local
        Zone name: 56.168.192.in-addr.arpa

    A RECORD: Address record, maps hostname to IPv4 address.
        Name: sccm01, IP: 192.168.56.11

    PTR RECORD: Pointer record, maps IP to hostname (reverse DNS).
        10.56.168.192.in-addr.arpa -> dc01.lab.local

    FORWARDERS: External DNS servers to query when we can't resolve a name.
        We use Google (8.8.8.8) and Cloudflare (1.1.1.1) for internet resolution.

.PARAMETER DomainName
    The domain name. Defaults to "lab.local".

.PARAMETER NetworkID
    The network ID for the reverse lookup zone. Defaults to "192.168.56.0/24".

.PARAMETER Forwarders
    Array of forwarder IP addresses. Defaults to Google and Cloudflare DNS.

.PARAMETER Force
    Skip confirmation prompts.

.EXAMPLE
    .\Configure-DNS.ps1

.EXAMPLE
    .\Configure-DNS.ps1 -Forwarders "8.8.8.8","8.8.4.4" -Force

.NOTES
    Author: SCCM Homelab Project
    Version: 1.0

    PREREQUISITES:
    - Server must be a domain controller (run Promote-DC.ps1 first)
    - DNS Server role must be installed (happens during DC promotion)
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$DomainName = "lab.local",

    [Parameter(Mandatory = $false)]
    [string]$NetworkID = "192.168.56.0/24",

    [Parameter(Mandatory = $false)]
    [string[]]$Forwarders = @("8.8.8.8", "1.1.1.1"),

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
    exit 1
}

Initialize-Logging -ScriptName "Configure-DNS"

# =============================================================================
# CONFIGURATION
# =============================================================================

# Define the server records to create
# Each entry is: Name, IP Address, Description
$ServerRecords = @(
    @{ Name = "sccm01"; IP = "192.168.56.11"; Description = "SCCM Primary Site Server" }
    # Add more static records here if needed
)

# =============================================================================
# MAIN SCRIPT LOGIC
# =============================================================================

try {
    Write-LogSection "Configuring DNS Server"

    # -------------------------------------------------------------------------
    # STEP 1: Prerequisite Checks
    # -------------------------------------------------------------------------
    Write-Log "Performing prerequisite checks..." -Level INFO

    # Must be a domain controller
    if (-not (Test-IsDomainController)) {
        Write-Log "This server is not a domain controller!" -Level ERROR
        Write-Log "Run Promote-DC.ps1 first to promote to DC." -Level ERROR
        Complete-Logging -Success $false
        exit 1
    }
    Write-Log "  Server is a domain controller" -Level SUCCESS

    # DNS Server role must be installed
    if (-not (Test-DNSServerInstalled)) {
        Write-Log "DNS Server role is not installed!" -Level ERROR
        Write-Log "This should have been installed during DC promotion." -Level ERROR
        Complete-Logging -Success $false
        exit 1
    }
    Write-Log "  DNS Server role is installed" -Level SUCCESS

    # Check that forward zone exists
    if (-not (Test-DNSZoneExists -ZoneName $DomainName)) {
        Write-Log "Forward lookup zone '$DomainName' does not exist!" -Level ERROR
        Write-Log "This should have been created during DC promotion." -Level ERROR
        Complete-Logging -Success $false
        exit 1
    }
    Write-Log "  Forward lookup zone '$DomainName' exists" -Level SUCCESS

    # -------------------------------------------------------------------------
    # STEP 2: Display Current Configuration
    # -------------------------------------------------------------------------
    Write-LogSection "Current DNS Configuration"

    # Show existing zones
    $zones = Get-DnsServerZone
    Write-Log "Existing DNS Zones:" -Level INFO
    foreach ($zone in $zones) {
        Write-Log "  $($zone.ZoneName) - $($zone.ZoneType)" -Level DEBUG
    }

    # Show existing forwarders
    $existingForwarders = Get-DnsServerForwarder
    if ($existingForwarders.IPAddress) {
        Write-Log "Current Forwarders: $($existingForwarders.IPAddress -join ', ')" -Level INFO
    }
    else {
        Write-Log "Current Forwarders: None configured" -Level INFO
    }

    # -------------------------------------------------------------------------
    # STEP 3: Create Reverse Lookup Zone
    # -------------------------------------------------------------------------
    Write-LogSection "Configuring Reverse Lookup Zone"

    <#
    REVERSE LOOKUP ZONES EXPLAINED:
    -------------------------------
    Reverse DNS maps IP addresses to hostnames. This is used by:
    - Security software checking who's connecting
    - Email servers validating senders (anti-spam)
    - Logging and auditing to show friendly names
    - Various Windows features that do reverse lookups

    Zone naming follows the in-addr.arpa format:
    - Network 192.168.56.0/24 becomes 56.168.192.in-addr.arpa
    - The octets are reversed!

    The zone is "AD-integrated" meaning:
    - Zone data is stored in Active Directory (not a file)
    - Zone replicates automatically to all DCs
    - Secure dynamic updates are supported
    #>

    if (Test-ReverseDNSZoneExists -NetworkID "192.168.56") {
        Write-Log "Reverse lookup zone already exists" -Level SUCCESS
    }
    else {
        Write-Log "Creating reverse lookup zone for $NetworkID..." -Level INFO

        # Add-DnsServerPrimaryZone creates a new zone
        # -NetworkId: The network in CIDR notation
        # -ReplicationScope: "Forest" means replicate to all DNS servers in forest
        # -DynamicUpdate: "Secure" means only authenticated clients can update
        Add-DnsServerPrimaryZone `
            -NetworkId $NetworkID `
            -ReplicationScope "Forest" `
            -DynamicUpdate "Secure"

        Write-Log "  Reverse lookup zone created" -Level SUCCESS
    }

    # Verify the zone
    $reverseZones = Get-DnsServerZone | Where-Object { $_.IsReverseLookupZone }
    foreach ($zone in $reverseZones) {
        Write-Log "  Reverse Zone: $($zone.ZoneName)" -Level DEBUG
    }

    # -------------------------------------------------------------------------
    # STEP 4: Create PTR Record for DC01
    # -------------------------------------------------------------------------
    Write-Log "Creating PTR record for DC01..." -Level INFO

    <#
    PTR RECORD FOR DC:
    ------------------
    The DC's A record was created automatically during AD promotion, but we
    should ensure a PTR record exists too. This can be done by:
    1. Using Add-DnsServerResourceRecordPtr directly
    2. Using Add-DnsServerResourceRecordA with -CreatePtr

    We'll check if it exists first to be idempotent.
    #>

    $dc01IP = "192.168.56.10"
    $dc01Name = "dc01.$DomainName"

    # Check if PTR already exists
    try {
        $existingPTR = Resolve-DnsName -Name $dc01IP -Type PTR -ErrorAction Stop
        Write-Log "  PTR record for DC01 already exists: $($existingPTR.NameHost)" -Level SUCCESS
    }
    catch {
        # Need to create PTR record
        Write-Log "  Creating PTR record for DC01 ($dc01IP -> $dc01Name)..." -Level INFO

        # Extract the last octet for the PTR record name
        # 192.168.56.10 -> record name is "10" in the 56.168.192.in-addr.arpa zone
        $lastOctet = $dc01IP.Split('.')[-1]
        $reverseZoneName = "56.168.192.in-addr.arpa"

        Add-DnsServerResourceRecordPtr `
            -ZoneName $reverseZoneName `
            -Name $lastOctet `
            -PtrDomainName $dc01Name

        Write-Log "  PTR record created for DC01" -Level SUCCESS
    }

    # -------------------------------------------------------------------------
    # STEP 5: Create Static A Records for Servers
    # -------------------------------------------------------------------------
    Write-LogSection "Creating Static Server Records"

    <#
    STATIC VS DYNAMIC RECORDS:
    --------------------------
    In AD-integrated DNS, domain members can register themselves dynamically.
    However, we create static records for servers because:
    1. Servers should have predictable DNS names before they join the domain
    2. Static records ensure DNS works even if dynamic update fails
    3. For SCCM, DNS must work before the server joins the domain
    #>

    foreach ($server in $ServerRecords) {
        Write-Log "Processing $($server.Name)..." -Level INFO

        # Check if A record already exists
        try {
            $existing = Get-DnsServerResourceRecord -ZoneName $DomainName -Name $server.Name -RRType A -ErrorAction Stop
            Write-Log "  A record already exists: $($server.Name) -> $($existing.RecordData.IPv4Address)" -Level SUCCESS
        }
        catch {
            # Create the A record
            Write-Log "  Creating A record: $($server.Name) -> $($server.IP)" -Level INFO

            # Add-DnsServerResourceRecordA creates an A (Address) record
            # -CreatePtr also creates the corresponding PTR record
            Add-DnsServerResourceRecordA `
                -ZoneName $DomainName `
                -Name $server.Name `
                -IPv4Address $server.IP `
                -CreatePtr  # This automatically creates the PTR record too!

            Write-Log "  A record and PTR record created" -Level SUCCESS
        }
    }

    # -------------------------------------------------------------------------
    # STEP 6: Configure DNS Forwarders
    # -------------------------------------------------------------------------
    Write-LogSection "Configuring DNS Forwarders"

    <#
    DNS FORWARDERS EXPLAINED:
    -------------------------
    When your DNS server receives a query it can't answer (like www.google.com),
    it needs to know where to ask. Options are:

    1. ROOT HINTS: Query the root DNS servers directly and follow referrals.
       This is the "pure" way but adds latency.

    2. FORWARDERS: Send queries to specific DNS servers that will resolve them.
       Faster because those servers likely have cached results.

    We use forwarders to Google and Cloudflare for internet resolution:
    - 8.8.8.8 / 8.8.4.4 - Google Public DNS
    - 1.1.1.1 / 1.0.0.1 - Cloudflare DNS

    This allows lab machines to resolve both:
    - Internal names: dc01.lab.local (resolved locally)
    - External names: www.google.com (forwarded to public DNS)
    #>

    Write-Log "Setting forwarders: $($Forwarders -join ', ')" -Level INFO

    # Set-DnsServerForwarder replaces all existing forwarders
    Set-DnsServerForwarder -IPAddress $Forwarders

    # Verify forwarders were set
    $currentForwarders = Get-DnsServerForwarder
    if ($currentForwarders.IPAddress) {
        Write-Log "  Forwarders configured: $($currentForwarders.IPAddress -join ', ')" -Level SUCCESS
    }

    # -------------------------------------------------------------------------
    # STEP 7: Configure Secure Dynamic Updates
    # -------------------------------------------------------------------------
    Write-Log "Configuring zone settings..." -Level INFO

    <#
    DYNAMIC UPDATE SETTINGS:
    ------------------------
    DNS zones can accept dynamic updates (clients registering their own records).
    Options are:
    - None: No dynamic updates allowed
    - NonsecureAndSecure: Any client can update (INSECURE!)
    - Secure: Only authenticated domain members can update (RECOMMENDED)

    For a lab, "Secure" is the right choice - only domain-joined machines
    can register their DNS records.
    #>

    # Ensure the forward zone allows secure dynamic updates
    Set-DnsServerPrimaryZone -Name $DomainName -DynamicUpdate Secure

    Write-Log "  Forward zone dynamic updates: Secure" -Level SUCCESS

    # -------------------------------------------------------------------------
    # STEP 8: Test DNS Resolution
    # -------------------------------------------------------------------------
    Write-LogSection "Testing DNS Resolution"

    # Test forward resolution
    Write-Log "Testing forward resolution..." -Level INFO
    $tests = @(
        @{ Name = "dc01.$DomainName"; Expected = $dc01IP },
        @{ Name = "sccm01.$DomainName"; Expected = "192.168.56.11" }
    )

    foreach ($test in $tests) {
        if (Test-DNSResolution -Hostname $test.Name -ExpectedIP $test.Expected) {
            Write-Log "  $($test.Name) -> $($test.Expected)" -Level SUCCESS
        }
        else {
            Write-Log "  $($test.Name) - Resolution failed or wrong IP!" -Level WARN
        }
    }

    # Test reverse resolution
    Write-Log "Testing reverse resolution..." -Level INFO
    try {
        $reverseResult = Resolve-DnsName -Name $dc01IP -Type PTR -ErrorAction Stop
        Write-Log "  $dc01IP -> $($reverseResult.NameHost)" -Level SUCCESS
    }
    catch {
        Write-Log "  $dc01IP - Reverse resolution failed!" -Level WARN
    }

    # Test external resolution (forwarders)
    Write-Log "Testing external resolution (forwarders)..." -Level INFO
    try {
        $externalResult = Resolve-DnsName -Name "www.google.com" -Type A -ErrorAction Stop
        Write-Log "  www.google.com -> $($externalResult.IPAddress | Select-Object -First 1)" -Level SUCCESS
    }
    catch {
        Write-Log "  External resolution failed - check forwarders!" -Level WARN
    }

    # -------------------------------------------------------------------------
    # STEP 9: Summary
    # -------------------------------------------------------------------------
    Write-LogSection "DNS Configuration Complete"

    Write-Log "Summary of DNS configuration:" -Level INFO
    Write-Log "  Forward Zone:  $DomainName" -Level INFO
    Write-Log "  Reverse Zone:  56.168.192.in-addr.arpa" -Level INFO
    Write-Log "  Forwarders:    $($Forwarders -join ', ')" -Level INFO
    Write-Log "  Server Records Created:" -Level INFO
    foreach ($server in $ServerRecords) {
        Write-Log "    - $($server.Name).$DomainName -> $($server.IP)" -Level INFO
    }
    Write-Log "" -Level INFO
    Write-Log "Next Steps:" -Level INFO
    Write-Log "  1. Run Configure-DHCP.ps1 to set up DHCP" -Level INFO
    Write-Log "  2. Run Create-OUs.ps1 to create organizational units" -Level INFO

    Complete-Logging -Success $true
    exit 0
}
catch {
    Write-LogError -ErrorRecord $_ -Message "An error occurred during DNS configuration"
    Complete-Logging -Success $false
    exit 1
}
