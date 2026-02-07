#Requires -Version 5.1
#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Installs and configures DHCP Server for the SCCM lab environment.

.DESCRIPTION
    This script installs the DHCP Server role, authorizes it in Active Directory,
    creates a scope for the lab network, and configures DHCP options.

    WHAT IS DHCP?
    -------------
    DHCP (Dynamic Host Configuration Protocol) automatically assigns IP addresses
    and network configuration to devices. Instead of manually configuring each
    device with an IP, subnet mask, gateway, and DNS servers, DHCP does it
    automatically when the device connects to the network.

    THE DORA PROCESS:
    -----------------
    DHCP uses a four-step process called DORA:

    1. DISCOVER: Client broadcasts "I need an IP address!"
       - Client has no IP yet, so it broadcasts to 255.255.255.255
       - All DHCP servers on the network hear this

    2. OFFER: Server responds "Here's an IP you can use"
       - Server offers an IP from its pool
       - Includes lease duration and configuration options

    3. REQUEST: Client says "I'll take that IP please"
       - Client broadcasts acceptance (in case multiple servers offered)
       - This confirms the selection

    4. ACKNOWLEDGE: Server confirms "It's yours for X hours"
       - Server marks the IP as leased
       - Client configures itself with the IP and options

    WHY DHCP IN THIS LAB:
    ---------------------
    - CLIENT01, CLIENT02, etc. get their IPs from DHCP
    - Lab can be rebuilt without manually configuring each client
    - Demonstrates enterprise DHCP management
    - Required for PXE boot (OS deployment)

    DHCP AND ACTIVE DIRECTORY:
    --------------------------
    In an AD environment, DHCP servers must be "authorized" before they can
    serve clients. This prevents rogue DHCP servers from hijacking the network.
    Only authorized servers can respond to DHCP requests.

.PARAMETER ScopeName
    Name for the DHCP scope. Defaults to "Lab Network".

.PARAMETER StartRange
    First IP in the DHCP range. Defaults to "192.168.56.100".

.PARAMETER EndRange
    Last IP in the DHCP range. Defaults to "192.168.56.200".

.PARAMETER SubnetMask
    Subnet mask for the scope. Defaults to "255.255.255.0".

.PARAMETER Router
    Default gateway for clients. Defaults to "192.168.56.1".

.PARAMETER DNSServer
    DNS server for clients. Defaults to DC01's IP "192.168.56.10".

.PARAMETER DomainName
    DNS domain name for clients. Defaults to "lab.local".

.PARAMETER LeaseDuration
    How long clients keep their IP. Defaults to 8 hours.

.PARAMETER Force
    Skip confirmation prompts.

.EXAMPLE
    .\Configure-DHCP.ps1

.EXAMPLE
    .\Configure-DHCP.ps1 -StartRange "192.168.56.150" -EndRange "192.168.56.250" -Force

.NOTES
    Author: SCCM Homelab Project
    Version: 1.0

    PREREQUISITES:
    - Server must be a domain controller (or domain member)
    - Domain must exist (run Promote-DC.ps1 first)

    NETWORK CONFIGURATION:
    - DC01: 192.168.56.10 (static)
    - SCCM01: 192.168.56.11 (static)
    - DHCP Range: 192.168.56.100-200
    - Gateway: 192.168.56.1 (VirtualBox host-only adapter)
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$ScopeName = "Lab Network",

    [Parameter(Mandatory = $false)]
    [string]$StartRange = "192.168.56.100",

    [Parameter(Mandatory = $false)]
    [string]$EndRange = "192.168.56.200",

    [Parameter(Mandatory = $false)]
    [string]$SubnetMask = "255.255.255.0",

    [Parameter(Mandatory = $false)]
    [string]$Router = "192.168.56.1",

    [Parameter(Mandatory = $false)]
    [string]$DNSServer = "192.168.56.10",

    [Parameter(Mandatory = $false)]
    [string]$DomainName = "lab.local",

    [Parameter(Mandatory = $false)]
    [TimeSpan]$LeaseDuration = (New-TimeSpan -Hours 8),

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

Initialize-Logging -ScriptName "Configure-DHCP"

# =============================================================================
# MAIN SCRIPT LOGIC
# =============================================================================

try {
    Write-LogSection "Configuring DHCP Server"

    # -------------------------------------------------------------------------
    # STEP 1: Prerequisite Checks
    # -------------------------------------------------------------------------
    Write-Log "Performing prerequisite checks..." -Level INFO

    # Should be a domain controller or domain member
    if (-not (Test-DomainJoined)) {
        Write-Log "This server is not joined to a domain!" -Level ERROR
        Write-Log "DHCP in AD requires domain membership for authorization." -Level ERROR
        Complete-Logging -Success $false
        exit 1
    }
    Write-Log "  Server is domain joined" -Level SUCCESS

    # -------------------------------------------------------------------------
    # STEP 2: Install DHCP Server Role
    # -------------------------------------------------------------------------
    Write-LogSection "Installing DHCP Server Role"

    if (Test-DHCPServerInstalled) {
        Write-Log "DHCP Server role is already installed" -Level SUCCESS
    }
    else {
        Write-Log "Installing DHCP Server role..." -Level INFO

        <#
        INSTALL-WINDOWSFEATURE DHCP:
        ----------------------------
        Installs the DHCP Server role and management tools.
        Management tools include:
        - DHCP MMC snap-in (dhcpmgmt.msc)
        - DHCP PowerShell module
        - Command-line tools
        #>

        $result = Install-WindowsFeature -Name DHCP -IncludeManagementTools

        if ($result.Success) {
            Write-Log "  DHCP Server role installed successfully" -Level SUCCESS
        }
        else {
            Write-Log "  DHCP Server role installation failed!" -Level ERROR
            Complete-Logging -Success $false
            exit 1
        }
    }

    # -------------------------------------------------------------------------
    # STEP 3: Authorize DHCP Server in Active Directory
    # -------------------------------------------------------------------------
    Write-LogSection "Authorizing DHCP Server"

    <#
    DHCP AUTHORIZATION EXPLAINED:
    -----------------------------
    In an AD environment, DHCP servers must be explicitly authorized before
    they can respond to client requests. This is a security feature that:

    1. Prevents rogue DHCP servers from serving wrong addresses
    2. Ensures only IT-approved servers handle DHCP
    3. Provides a list of authorized servers in AD

    Authorization is stored in the Configuration partition of AD:
    CN=NetServices,CN=Services,CN=Configuration,DC=lab,DC=local

    Without authorization:
    - The DHCP Server service will start
    - But it won't respond to any DHCP requests
    - Event log will show "not authorized" warnings
    #>

    # Get this server's information for authorization
    $serverFQDN = "$env:COMPUTERNAME.$DomainName"
    $serverIP = (Get-NetIPAddress -AddressFamily IPv4 |
        Where-Object { $_.InterfaceAlias -like "*Ethernet*" -and $_.IPAddress -like "192.168.56.*" } |
        Select-Object -First 1).IPAddress

    Write-Log "Server FQDN: $serverFQDN" -Level DEBUG
    Write-Log "Server IP: $serverIP" -Level DEBUG

    <#
    WAITING FOR AD SERVICES:
    ------------------------
    After a domain controller is promoted or rebooted, AD services take time
    to fully initialize. The DHCP authorization commands query the Configuration
    naming context in AD (CN=NetServices,CN=Services,CN=Configuration,DC=lab,DC=local).

    If we try to query too soon, we get:
    "Failed to initialize directory service resources for domain lab.local."

    Solution: Retry the command with exponential backoff until AD is ready.
    This is a common pattern when scripting against newly promoted DCs.
    #>

    # Check if already authorized (with retry for AD readiness)
    $maxRetries = 5
    $retryCount = 0
    $retryDelaySeconds = 10
    $authorizedServers = $null
    $adReady = $false

    Write-Log "Checking DHCP authorization status (waiting for AD services if needed)..." -Level INFO

    while (-not $adReady -and $retryCount -lt $maxRetries) {
        try {
            $authorizedServers = Get-DhcpServerInDC -ErrorAction Stop
            $adReady = $true
            Write-Log "  AD services are ready" -Level DEBUG
        }
        catch {
            $retryCount++
            if ($retryCount -lt $maxRetries) {
                Write-Log "  AD services not ready yet (attempt $retryCount of $maxRetries). Waiting $retryDelaySeconds seconds..." -Level WARN
                Start-Sleep -Seconds $retryDelaySeconds
                # Exponential backoff: increase delay each retry
                $retryDelaySeconds = $retryDelaySeconds * 2
            }
            else {
                Write-Log "  AD services did not become ready after $maxRetries attempts" -Level ERROR
                Write-Log "  Error: $($_.Exception.Message)" -Level DEBUG
                throw $_
            }
        }
    }

    $isAuthorized = $false
    foreach ($server in $authorizedServers) {
        if ($server.DnsName -eq $serverFQDN -or $server.IPAddress -eq $serverIP) {
            $isAuthorized = $true
            break
        }
    }

    if ($isAuthorized) {
        Write-Log "DHCP Server is already authorized in Active Directory" -Level SUCCESS
    }
    else {
        Write-Log "Authorizing DHCP Server in Active Directory..." -Level INFO

        # Add-DhcpServerInDC authorizes this DHCP server (also with retry)
        $authRetryCount = 0
        $authSuccess = $false

        while (-not $authSuccess -and $authRetryCount -lt 3) {
            try {
                Add-DhcpServerInDC -DnsName $serverFQDN -IPAddress $serverIP -ErrorAction Stop
                $authSuccess = $true
            }
            catch {
                $authRetryCount++
                if ($authRetryCount -lt 3) {
                    Write-Log "  Authorization attempt $authRetryCount failed. Retrying in 10 seconds..." -Level WARN
                    Start-Sleep -Seconds 10
                }
                else {
                    throw $_
                }
            }
        }

        Write-Log "  DHCP Server authorized successfully" -Level SUCCESS
    }

    # Suppress the Server Manager notification about DHCP configuration
    # This sets a registry key that tells Server Manager we've configured DHCP
    Write-Log "Suppressing Server Manager post-install notification..." -Level DEBUG
    $regPath = "HKLM:\SOFTWARE\Microsoft\ServerManager\Roles\12"
    if (Test-Path $regPath) {
        Set-ItemProperty -Path $regPath -Name "ConfigurationState" -Value 2
    }

    # -------------------------------------------------------------------------
    # STEP 4: Create DHCP Scope
    # -------------------------------------------------------------------------
    Write-LogSection "Creating DHCP Scope"

    <#
    DHCP SCOPE EXPLAINED:
    ---------------------
    A DHCP scope defines a pool of IP addresses and their configuration.
    Key properties:

    - ScopeId: The network address (192.168.56.0)
    - StartRange/EndRange: The IP range to hand out
    - SubnetMask: Defines the network boundary
    - LeaseDuration: How long a client keeps its IP
    - State: Active (serving IPs) or Inactive (not serving)

    Our scope:
    - Network: 192.168.56.0/24
    - Range: 192.168.56.100 - 192.168.56.200 (101 addresses)
    - Reserved: .1-.99 (gateway, servers)
    - Reserved: .201-.254 (future use)
    #>

    # Calculate the scope ID (network address)
    # For 192.168.56.100-200 with /24, scope ID is 192.168.56.0
    $scopeID = "192.168.56.0"

    if (Test-DHCPScopeExists -ScopeID $scopeID) {
        Write-Log "DHCP Scope '$scopeID' already exists" -Level SUCCESS

        # Show existing configuration
        $existingScope = Get-DhcpServerv4Scope -ScopeId $scopeID
        Write-Log "  Name: $($existingScope.Name)" -Level DEBUG
        Write-Log "  Range: $($existingScope.StartRange) - $($existingScope.EndRange)" -Level DEBUG
        Write-Log "  State: $($existingScope.State)" -Level DEBUG
    }
    else {
        Write-Log "Creating DHCP Scope '$ScopeName'..." -Level INFO
        Write-Log "  Network: $scopeID" -Level INFO
        Write-Log "  Range: $StartRange - $EndRange" -Level INFO
        Write-Log "  Lease: $($LeaseDuration.Hours) hours" -Level INFO

        <#
        ADD-DHCPSERVERV4SCOPE PARAMETERS:
        ---------------------------------
        -Name: Friendly name for the scope
        -StartRange/-EndRange: IP range to assign
        -SubnetMask: Network mask
        -LeaseDuration: How long clients keep their IP
        -State: Active = serving, Inactive = not serving

        The scope starts as Active, meaning it will immediately begin
        responding to DHCP requests.
        #>

        Add-DhcpServerv4Scope `
            -Name $ScopeName `
            -StartRange $StartRange `
            -EndRange $EndRange `
            -SubnetMask $SubnetMask `
            -LeaseDuration $LeaseDuration `
            -State Active

        Write-Log "  DHCP Scope created successfully" -Level SUCCESS
    }

    # -------------------------------------------------------------------------
    # STEP 5: Configure Scope Options
    # -------------------------------------------------------------------------
    Write-LogSection "Configuring DHCP Options"

    <#
    DHCP OPTIONS EXPLAINED:
    -----------------------
    DHCP options provide additional configuration to clients beyond just the
    IP address. Each option has a number and a purpose:

    Option 003 - Router (Default Gateway):
        The gateway IP that clients use to reach other networks.
        Without this, clients can't reach the internet.

    Option 006 - DNS Servers:
        The DNS server IP(s) clients should use for name resolution.
        We point to DC01 (our DNS server).

    Option 015 - DNS Domain Name:
        The DNS suffix for the domain. When a client looks up "dc01",
        it becomes "dc01.lab.local".

    Options can be set at different levels:
    - Server level: Apply to all scopes
    - Scope level: Apply to one scope
    - Reservation level: Apply to one specific client

    We set at scope level since we only have one scope.
    #>

    Write-Log "Setting scope options..." -Level INFO

    # Set Router (Default Gateway) - Option 003
    Write-Log "  Option 003 (Router): $Router" -Level INFO
    Set-DhcpServerv4OptionValue -ScopeId $scopeID -Router $Router

    # Set DNS Server - Option 006
    Write-Log "  Option 006 (DNS Server): $DNSServer" -Level INFO
    Set-DhcpServerv4OptionValue -ScopeId $scopeID -DnsServer $DNSServer

    # Set DNS Domain Name - Option 015
    Write-Log "  Option 015 (DNS Domain): $DomainName" -Level INFO
    Set-DhcpServerv4OptionValue -ScopeId $scopeID -DnsDomain $DomainName

    Write-Log "  Scope options configured" -Level SUCCESS

    # -------------------------------------------------------------------------
    # STEP 6: Verify Scope is Active
    # -------------------------------------------------------------------------
    Write-Log "Verifying scope status..." -Level INFO

    if (Test-DHCPScopeActive -ScopeID $scopeID) {
        Write-Log "  Scope is active and ready to serve clients" -Level SUCCESS
    }
    else {
        Write-Log "  Scope is not active! Activating..." -Level WARN
        Set-DhcpServerv4Scope -ScopeId $scopeID -State Active
        Write-Log "  Scope activated" -Level SUCCESS
    }

    # -------------------------------------------------------------------------
    # STEP 7: Restart DHCP Server Service
    # -------------------------------------------------------------------------
    Write-Log "Restarting DHCP Server service..." -Level INFO

    Restart-Service -Name DHCPServer -Force
    Start-Sleep -Seconds 3

    $dhcpService = Get-Service -Name DHCPServer
    if ($dhcpService.Status -eq 'Running') {
        Write-Log "  DHCP Server service is running" -Level SUCCESS
    }
    else {
        Write-Log "  DHCP Server service failed to start!" -Level ERROR
    }

    # -------------------------------------------------------------------------
    # STEP 8: Display Configuration Summary
    # -------------------------------------------------------------------------
    Write-LogSection "DHCP Configuration Summary"

    $finalScope = Get-DhcpServerv4Scope -ScopeId $scopeID
    $finalOptions = Get-DhcpServerv4OptionValue -ScopeId $scopeID

    Write-Log "Scope Configuration:" -Level INFO
    Write-Log "  Name:        $($finalScope.Name)" -Level INFO
    Write-Log "  Scope ID:    $($finalScope.ScopeId)" -Level INFO
    Write-Log "  Start:       $($finalScope.StartRange)" -Level INFO
    Write-Log "  End:         $($finalScope.EndRange)" -Level INFO
    Write-Log "  Subnet:      $($finalScope.SubnetMask)" -Level INFO
    Write-Log "  Lease:       $($finalScope.LeaseDuration)" -Level INFO
    Write-Log "  State:       $($finalScope.State)" -Level INFO
    Write-Log "" -Level INFO

    Write-Log "Scope Options:" -Level INFO
    foreach ($opt in $finalOptions) {
        Write-Log "  Option $($opt.OptionId) ($($opt.Name)): $($opt.Value -join ', ')" -Level INFO
    }

    Write-Log "" -Level INFO
    Write-Log "Next Steps:" -Level INFO
    Write-Log "  1. Client VMs will now receive IPs from this DHCP scope" -Level INFO
    Write-Log "  2. Run Create-OUs.ps1 to create organizational units" -Level INFO
    Write-Log "  3. Run Create-ServiceAccounts.ps1 to create service accounts" -Level INFO

    # -------------------------------------------------------------------------
    # STEP 9: Optional - Show Statistics
    # -------------------------------------------------------------------------
    Write-Log "" -Level INFO
    Write-Log "DHCP Statistics:" -Level INFO

    $stats = Get-DhcpServerv4ScopeStatistics -ScopeId $scopeID
    Write-Log "  Available IPs: $($stats.Free)" -Level INFO
    Write-Log "  In Use:        $($stats.InUse)" -Level INFO
    Write-Log "  Reserved:      $($stats.Reserved)" -Level INFO

    Complete-Logging -Success $true
    exit 0
}
catch {
    Write-LogError -ErrorRecord $_ -Message "An error occurred during DHCP configuration"

    # Specific guidance for common errors
    $errorMessage = $_.Exception.Message.ToLower()

    if ($errorMessage -match "authorized") {
        Write-Log "" -Level INFO
        Write-Log "HINT: Make sure you're running this on a domain-joined server" -Level INFO
        Write-Log "and have Domain Admin or Enterprise Admin privileges." -Level INFO
    }
    elseif ($errorMessage -match "scope") {
        Write-Log "" -Level INFO
        Write-Log "HINT: The scope may already exist with different settings." -Level INFO
        Write-Log "Use Get-DhcpServerv4Scope to check existing scopes." -Level INFO
    }

    Complete-Logging -Success $false
    exit 1
}
