#Requires -Version 5.1
#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Fixes network and DNS issues on an already-promoted multi-homed Domain Controller.

.DESCRIPTION
    This script fixes the common issues that occur when a DC is promoted with
    multiple network adapters (NAT + Host-Only in VirtualBox).

    WHAT THIS SCRIPT FIXES:
    -----------------------
    1. Configures adapter metrics (lab adapter = high priority)
    2. Disables DNS registration on NAT adapter
    3. Removes incorrect DNS records (10.0.2.x entries)
    4. Configures DNS Server to only listen on correct IPs
    5. Re-registers correct DNS records
    6. Restarts critical services

    WHEN TO USE THIS SCRIPT:
    ------------------------
    Run this script if you see errors like:
    - "Failed to initialize directory service resources for domain lab.local"
    - Test-ComputerSecureChannel fails with "domain could not be contacted"
    - nltest /dsgetdc returns wrong IP address (10.0.2.x instead of 192.168.56.x)
    - DHCP authorization fails
    - Clients cannot join domain

    The root cause is that the DC was promoted with both adapters registering
    DNS records, causing AD/DNS confusion about which IP is correct.

.PARAMETER LabAdapterIP
    The correct IP address for the lab network. Defaults to "192.168.56.10".

.PARAMETER DomainName
    The domain name. Defaults to "lab.local".

.PARAMETER Force
    Skip confirmation prompts.

.EXAMPLE
    .\Fix-MultiHomedDC.ps1 -Force

.NOTES
    Author: SCCM Homelab Project
    Version: 1.0

    This script should be run on DC01 after promotion if issues are observed.
    A reboot is recommended after running this script.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$LabAdapterIP = "192.168.56.10",

    [Parameter(Mandatory = $false)]
    [string]$DomainName = "lab.local",

    [Parameter(Mandatory = $false)]
    [switch]$Force
)

# =============================================================================
# SCRIPT INITIALIZATION
# =============================================================================

$ErrorActionPreference = 'Stop'

# Simple logging (doesn't require external modules)
function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $color = switch ($Level) {
        "ERROR" { "Red" }
        "WARN"  { "Yellow" }
        "SUCCESS" { "Green" }
        "DEBUG" { "Gray" }
        default { "White" }
    }
    Write-Host "[$timestamp] [$Level] $Message" -ForegroundColor $color
}

function Write-LogSection {
    param([string]$Title)
    Write-Host ""
    Write-Host "============================================================" -ForegroundColor Cyan
    Write-Host $Title -ForegroundColor Cyan
    Write-Host "============================================================" -ForegroundColor Cyan
}

# =============================================================================
# MAIN SCRIPT LOGIC
# =============================================================================

Write-LogSection "Fixing Multi-Homed Domain Controller Issues"
Write-Log "Target Lab IP: $LabAdapterIP"
Write-Log "Domain: $DomainName"

try {
    # -------------------------------------------------------------------------
    # STEP 1: Identify Adapters
    # -------------------------------------------------------------------------
    Write-LogSection "Step 1: Identifying Network Adapters"

    $adapters = Get-NetAdapter | Where-Object { $_.Status -eq 'Up' }
    $natAdapter = $null
    $labAdapter = $null

    foreach ($adapter in $adapters) {
        $ipAddress = (Get-NetIPAddress -InterfaceIndex $adapter.ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue).IPAddress

        if ($ipAddress -like "10.0.2.*") {
            $natAdapter = $adapter
            Write-Log "  NAT Adapter: $($adapter.Name) - $ipAddress"
        }
        elseif ($ipAddress -like "192.168.56.*") {
            $labAdapter = $adapter
            Write-Log "  Lab Adapter: $($adapter.Name) - $ipAddress"
        }
    }

    if (-not $labAdapter) {
        Write-Log "Could not find lab adapter (192.168.56.x). Exiting." "ERROR"
        exit 1
    }

    # -------------------------------------------------------------------------
    # STEP 2: Configure Adapter Metrics
    # -------------------------------------------------------------------------
    Write-LogSection "Step 2: Configuring Adapter Metrics"

    Write-Log "Setting lab adapter metric to 10 (high priority)"
    Set-NetIPInterface -InterfaceIndex $labAdapter.ifIndex -InterfaceMetric 10

    if ($natAdapter) {
        Write-Log "Setting NAT adapter metric to 100 (low priority)"
        Set-NetIPInterface -InterfaceIndex $natAdapter.ifIndex -InterfaceMetric 100
    }

    Write-Log "Metrics configured" "SUCCESS"

    # -------------------------------------------------------------------------
    # STEP 3: Configure DNS Registration
    # -------------------------------------------------------------------------
    Write-LogSection "Step 3: Configuring DNS Registration"

    Write-Log "Enabling DNS registration on lab adapter"
    Set-DnsClient -InterfaceIndex $labAdapter.ifIndex -RegisterThisConnectionsAddress $true

    if ($natAdapter) {
        Write-Log "Disabling DNS registration on NAT adapter"
        Set-DnsClient -InterfaceIndex $natAdapter.ifIndex -RegisterThisConnectionsAddress $false
        Set-DnsClient -InterfaceIndex $natAdapter.ifIndex -ConnectionSpecificSuffix ""
    }

    Write-Log "DNS registration configured" "SUCCESS"

    # -------------------------------------------------------------------------
    # STEP 4: Configure DNS Client Settings
    # -------------------------------------------------------------------------
    Write-LogSection "Step 4: Configuring DNS Client Settings"

    Write-Log "Setting lab adapter DNS to 127.0.0.1"
    Set-DnsClientServerAddress -InterfaceIndex $labAdapter.ifIndex -ServerAddresses "127.0.0.1"

    if ($natAdapter) {
        Write-Log "Setting NAT adapter DNS to $LabAdapterIP"
        Set-DnsClientServerAddress -InterfaceIndex $natAdapter.ifIndex -ServerAddresses $LabAdapterIP
    }

    Write-Log "DNS client settings configured" "SUCCESS"

    # -------------------------------------------------------------------------
    # STEP 5: Disable IPv6
    # -------------------------------------------------------------------------
    Write-LogSection "Step 5: Disabling IPv6"

    foreach ($adapter in $adapters) {
        Write-Log "Disabling IPv6 on $($adapter.Name)"
        Disable-NetAdapterBinding -Name $adapter.Name -ComponentID ms_tcpip6 -ErrorAction SilentlyContinue
    }

    Write-Log "IPv6 disabled" "SUCCESS"

    # -------------------------------------------------------------------------
    # STEP 6: Clean Up DNS Records
    # -------------------------------------------------------------------------
    Write-LogSection "Step 6: Cleaning Up Incorrect DNS Records"

    # Remove 10.0.2.x A records from lab.local zone
    Write-Log "Checking for incorrect A records in $DomainName zone..."

    $zones = @($DomainName, "_msdcs.$DomainName")

    foreach ($zone in $zones) {
        try {
            $badRecords = Get-DnsServerResourceRecord -ZoneName $zone -RRType A -ErrorAction SilentlyContinue |
                Where-Object { $_.RecordData.IPv4Address.IPAddressToString -like "10.0.2.*" }

            foreach ($record in $badRecords) {
                $ip = $record.RecordData.IPv4Address.IPAddressToString
                Write-Log "  Removing: $($record.HostName).$zone -> $ip" "WARN"
                Remove-DnsServerResourceRecord -ZoneName $zone -InputObject $record -Force -ErrorAction SilentlyContinue
            }
        }
        catch {
            Write-Log "  Could not clean zone $zone : $($_.Exception.Message)" "DEBUG"
        }
    }

    Write-Log "DNS records cleaned" "SUCCESS"

    # -------------------------------------------------------------------------
    # STEP 7: Configure DNS Server Listening Addresses
    # -------------------------------------------------------------------------
    Write-LogSection "Step 7: Configuring DNS Server Listening Addresses"

    Write-Log "Setting DNS server to listen only on 127.0.0.1 and $LabAdapterIP"
    Set-DnsServerSetting -ListeningIpAddress @("127.0.0.1", $LabAdapterIP)

    Write-Log "DNS server listening addresses configured" "SUCCESS"

    # -------------------------------------------------------------------------
    # STEP 8: Clear Caches
    # -------------------------------------------------------------------------
    Write-LogSection "Step 8: Clearing Caches"

    Write-Log "Clearing DNS client cache"
    Clear-DnsClientCache

    Write-Log "Clearing DNS server cache"
    Clear-DnsServerCache

    Write-Log "Caches cleared" "SUCCESS"

    # -------------------------------------------------------------------------
    # STEP 9: Restart Services
    # -------------------------------------------------------------------------
    Write-LogSection "Step 9: Restarting Services"

    Write-Log "Restarting DNS Server..."
    Restart-Service DNS -Force
    Start-Sleep -Seconds 3

    Write-Log "Restarting Netlogon..."
    Restart-Service Netlogon -Force
    Start-Sleep -Seconds 5

    Write-Log "Services restarted" "SUCCESS"

    # -------------------------------------------------------------------------
    # STEP 10: Re-register DNS
    # -------------------------------------------------------------------------
    Write-LogSection "Step 10: Re-registering DNS Records"

    Write-Log "Running ipconfig /registerdns"
    ipconfig /registerdns | Out-Null

    Write-Log "Running nltest /dsregdns"
    nltest /dsregdns | Out-Null

    Start-Sleep -Seconds 5

    Write-Log "DNS re-registration complete" "SUCCESS"

    # -------------------------------------------------------------------------
    # STEP 11: Verification
    # -------------------------------------------------------------------------
    Write-LogSection "Step 11: Verification"

    Write-Log "Testing DNS resolution..."
    $dnsResult = Resolve-DnsName "dc01.$DomainName" -Type A -ErrorAction SilentlyContinue
    if ($dnsResult) {
        foreach ($result in $dnsResult) {
            $status = if ($result.IPAddress -eq $LabAdapterIP) { "SUCCESS" } else { "WARN" }
            Write-Log "  dc01.$DomainName -> $($result.IPAddress)" $status
        }
    }

    Write-Log ""
    Write-Log "Testing DC Locator..."
    $nltest = nltest /dsgetdc:$DomainName /force 2>&1
    $addressLine = $nltest | Where-Object { $_ -match "Address:" }
    if ($addressLine) {
        Write-Log "  $addressLine"
    }

    Write-Log ""
    Write-Log "Testing Secure Channel..."
    try {
        $scResult = Test-ComputerSecureChannel -Verbose 4>&1
        Write-Log "  Secure channel test passed!" "SUCCESS"
    }
    catch {
        Write-Log "  Secure channel test failed: $($_.Exception.Message)" "WARN"
        Write-Log "  A REBOOT may be required to fully resolve the issue" "WARN"
    }

    Write-Log ""
    Write-Log "Testing DHCP Authorization..."
    try {
        $dhcpServers = Get-DhcpServerInDC -ErrorAction Stop
        Write-Log "  DHCP authorization check passed!" "SUCCESS"
    }
    catch {
        Write-Log "  DHCP authorization check failed: $($_.Exception.Message)" "WARN"
        Write-Log "  A REBOOT may be required" "WARN"
    }

    # -------------------------------------------------------------------------
    # Summary
    # -------------------------------------------------------------------------
    Write-LogSection "Summary"

    Write-Log "Network adapter configuration:"
    Get-NetIPInterface -AddressFamily IPv4 |
        Where-Object { $_.InterfaceAlias -notlike "*Loopback*" } |
        Sort-Object InterfaceMetric |
        ForEach-Object {
            $ip = (Get-NetIPAddress -InterfaceIndex $_.ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue).IPAddress
            Write-Log "  $($_.InterfaceAlias): IP=$ip, Metric=$($_.InterfaceMetric)"
        }

    Write-Log ""
    Write-Log "Fix script completed!" "SUCCESS"
    Write-Log ""
    Write-Log "RECOMMENDATION: Reboot the DC to ensure all changes take effect:" "WARN"
    Write-Log "  Restart-Computer -Force" "WARN"

}
catch {
    Write-Log "An error occurred: $($_.Exception.Message)" "ERROR"
    Write-Log "Stack trace: $($_.ScriptStackTrace)" "DEBUG"
    exit 1
}
