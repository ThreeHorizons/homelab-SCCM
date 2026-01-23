#Requires -Version 5.1
<#
.SYNOPSIS
    Configures Windows Remote Management (WinRM) for Vagrant provisioning.

.DESCRIPTION
    WinRM (Windows Remote Management) is Microsoft's implementation of the
    WS-Management protocol. It enables remote PowerShell execution, which
    Vagrant uses to provision Windows VMs.

    This script configures WinRM with settings optimized for lab/development:
    - HTTP listener on port 5985 (unencrypted, lab only!)
    - Basic authentication enabled
    - Unencrypted traffic allowed
    - Appropriate firewall rules

    SECURITY WARNING:
    These settings are INSECURE and only appropriate for isolated lab networks!
    In production, you would use:
    - HTTPS listeners with valid certificates
    - Kerberos or CredSSP authentication
    - Network segmentation
    - Encryption required

    WINRM ARCHITECTURE:

    ┌──────────────────┐     WinRM Protocol     ┌──────────────────┐
    │   Host Machine   │  ←─────────────────→   │   Windows VM     │
    │   (Linux/Mac)    │      Port 5985         │   (Guest)        │
    │                  │                        │                  │
    │  ┌────────────┐  │                        │  ┌────────────┐  │
    │  │  Vagrant   │  │   HTTP/SOAP Request    │  │   WinRM    │  │
    │  │            │──┼──────────────────────→ │  │  Service   │  │
    │  │            │  │                        │  │            │  │
    │  │            │  │   PowerShell Output    │  │            │  │
    │  │            │←─┼────────────────────────┼──│            │  │
    │  └────────────┘  │                        │  └────────────┘  │
    └──────────────────┘                        └──────────────────┘

    WINRM COMPONENTS:

    1. Listeners: Define how WinRM accepts connections
       - HTTP listener (port 5985) - unencrypted
       - HTTPS listener (port 5986) - TLS encrypted

    2. Authentication: How clients prove their identity
       - Basic: Username/password (requires AllowUnencrypted for HTTP)
       - Negotiate: Kerberos or NTLM (preferred for domains)
       - CredSSP: Allows credential delegation (for multi-hop)

    3. Authorization: What authenticated users can do
       - LocalAccountTokenFilterPolicy: Allows local admin accounts
       - WinRS settings: Control shell behavior

.EXAMPLE
    .\enable-winrm.ps1

.NOTES
    Author: SCCM Homelab Project
    Version: 1.0

    References:
    - https://docs.microsoft.com/en-us/windows/win32/winrm/installation-and-configuration-for-windows-remote-management
    - https://developer.hashicorp.com/vagrant/docs/boxes/base#windows-boxes
#>

[CmdletBinding()]
param()

# -----------------------------------------------------------------------------
# SCRIPT CONFIGURATION
# -----------------------------------------------------------------------------

$ErrorActionPreference = 'Stop'

# Logging
$LogPath = "C:\Logs"
if (-not (Test-Path $LogPath)) {
    New-Item -ItemType Directory -Path $LogPath -Force | Out-Null
}
Start-Transcript -Path "$LogPath\enable-winrm-$(Get-Date -Format 'yyyyMMdd-HHmmss').log"

function Write-LogMessage {
    param(
        [string]$Message,
        [ValidateSet('INFO', 'WARN', 'ERROR')]
        [string]$Level = 'INFO'
    )
    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    Write-Host "[$timestamp] [$($Level.PadRight(5))] $Message"
}

# -----------------------------------------------------------------------------
# MAIN CONFIGURATION
# -----------------------------------------------------------------------------

Write-LogMessage "Starting WinRM configuration"
Write-LogMessage "Current user: $env:USERNAME"
Write-LogMessage "Computer name: $env:COMPUTERNAME"

# -------------------------------------------------------------------------
# STEP 1: CONFIGURE WINRM SERVICE
# -------------------------------------------------------------------------
# The WinRM service must be running and configured before we can use it.
# WinRM service name: "WinRM" (display name: "Windows Remote Management (WS-Management)")

Write-LogMessage "Step 1: Configuring WinRM service..."

# Ensure the WinRM service exists and is configured
# winrm quickconfig performs basic setup:
# - Starts the WinRM service
# - Sets the service to auto-start
# - Creates an HTTP listener on port 5985
# - Configures firewall rules
#
# The -q flag suppresses prompts (quiet mode)
# The -force flag skips the network profile check

Write-LogMessage "Running 'winrm quickconfig'..."
try {
    # Run winrm quickconfig silently
    # cmd /c runs a command through cmd.exe (needed for winrm.cmd)
    $result = cmd /c "winrm quickconfig -q -force" 2>&1
    Write-LogMessage "winrm quickconfig output: $result"
} catch {
    Write-LogMessage "winrm quickconfig error (may be OK): $($_.Exception.Message)" -Level WARN
}

# Set the WinRM service to start automatically
Write-LogMessage "Setting WinRM service to Automatic startup..."
Set-Service -Name "WinRM" -StartupType Automatic

# Start the WinRM service if not running
$winrmService = Get-Service -Name "WinRM"
if ($winrmService.Status -ne 'Running') {
    Write-LogMessage "Starting WinRM service..."
    Start-Service -Name "WinRM"
} else {
    Write-LogMessage "WinRM service is already running"
}

# -------------------------------------------------------------------------
# STEP 2: CONFIGURE WINRM LISTENERS
# -------------------------------------------------------------------------
# WinRM listeners define endpoints where WinRM accepts connections.
# Each listener has:
# - Transport: HTTP (5985) or HTTPS (5986)
# - Address: IP address to listen on (* = all addresses)
# - Port: TCP port number

Write-LogMessage "Step 2: Configuring WinRM listeners..."

# Check for existing HTTP listener
# winrm enumerate lists WinRM configuration objects
$httpListener = winrm enumerate winrm/config/listener 2>&1 | Select-String "Transport = HTTP"

if (-not $httpListener) {
    Write-LogMessage "Creating HTTP listener..."

    # winrm create creates a new WinRM configuration object
    # URI format: winrm/config/Listener?Address=*+Transport=HTTP
    # Address=* means listen on all IP addresses
    try {
        winrm create winrm/config/Listener?Address=*+Transport=HTTP 2>&1 | Out-Null
        Write-LogMessage "HTTP listener created"
    } catch {
        Write-LogMessage "HTTP listener may already exist: $($_.Exception.Message)" -Level WARN
    }
} else {
    Write-LogMessage "HTTP listener already exists"
}

# Delete any HTTPS listener (simplifies lab setup)
# In production, you would keep HTTPS and remove HTTP
$httpsListener = winrm enumerate winrm/config/listener 2>&1 | Select-String "Transport = HTTPS"
if ($httpsListener) {
    Write-LogMessage "Removing HTTPS listener for lab simplicity..." -Level WARN
    try {
        winrm delete winrm/config/Listener?Address=*+Transport=HTTPS 2>&1 | Out-Null
    } catch {
        # Ignore if it doesn't exist
    }
}

# -------------------------------------------------------------------------
# STEP 3: CONFIGURE WINRM SETTINGS
# -------------------------------------------------------------------------
# WinRM has many configurable settings that affect security and functionality.
# We configure settings appropriate for a lab environment.
#
# The winrm set command modifies WinRM configuration
# Format: winrm set <resource_uri> @{<setting>=<value>}

Write-LogMessage "Step 3: Configuring WinRM settings..."

# --- WinRM Service Settings ---

# Allow unencrypted traffic (HTTP)
# SECURITY WARNING: Never enable this in production!
# This is required for Vagrant to connect over HTTP without HTTPS
Write-LogMessage "Enabling unencrypted traffic (HTTP) - LAB ONLY!"
winrm set winrm/config/service '@{AllowUnencrypted="true"}' | Out-Null

# Enable Basic authentication
# Basic auth sends username:password in Base64 (not encrypted!)
# Combined with AllowUnencrypted, this is very insecure
# Required for Vagrant's default WinRM configuration
Write-LogMessage "Enabling Basic authentication - LAB ONLY!"
winrm set winrm/config/service/auth '@{Basic="true"}' | Out-Null

# Enable CredSSP authentication (for future use)
# CredSSP allows credential delegation for "double-hop" scenarios
# Example: Connect to VM, then from VM connect to another machine
Write-LogMessage "Enabling CredSSP authentication..."
Enable-WSManCredSSP -Role Server -Force -ErrorAction SilentlyContinue | Out-Null
winrm set winrm/config/service/auth '@{CredSSP="true"}' | Out-Null

# --- WinRM Client Settings ---
# These affect outgoing WinRM connections from this machine

# Allow unencrypted client connections
Write-LogMessage "Configuring WinRM client settings..."
winrm set winrm/config/client '@{AllowUnencrypted="true"}' | Out-Null

# Enable Basic auth for client
winrm set winrm/config/client/auth '@{Basic="true"}' | Out-Null

# Set TrustedHosts to allow connections from any machine
# This is needed for workgroup (non-domain) scenarios
# The * wildcard trusts all hosts - VERY insecure for production!
Write-LogMessage "Setting TrustedHosts to '*' (all hosts trusted)"
winrm set winrm/config/client '@{TrustedHosts="*"}' | Out-Null

# --- WinRS (Windows Remote Shell) Settings ---
# WinRS controls the behavior of remote shell sessions

Write-LogMessage "Configuring WinRS settings..."

# Increase max memory per shell (for large script output)
# Default is 150MB, we increase to 1GB for complex scripts
winrm set winrm/config/winrs '@{MaxMemoryPerShellMB="1024"}' | Out-Null

# Increase max processes per shell
# Allows more concurrent operations within a shell session
winrm set winrm/config/winrs '@{MaxProcessesPerShell="25"}' | Out-Null

# Increase max shells per user
# Allows more concurrent shell sessions
winrm set winrm/config/winrs '@{MaxShellsPerUser="25"}' | Out-Null

# --- Global WinRM Timeouts ---

Write-LogMessage "Configuring WinRM timeouts..."

# Max timeout for operations (30 minutes in milliseconds)
# Long timeout allows for slow operations like software installation
winrm set winrm/config '@{MaxTimeoutms="1800000"}' | Out-Null

# -------------------------------------------------------------------------
# STEP 4: CONFIGURE LOCAL ACCOUNT TOKEN POLICY
# -------------------------------------------------------------------------
# By default, Windows filters admin tokens for remote connections.
# This prevents local admin accounts from having full admin rights remotely.
# We disable this filter for the lab so the "vagrant" account works properly.
#
# Registry key: LocalAccountTokenFilterPolicy
# 0 = Filter admin tokens (default, more secure)
# 1 = Don't filter admin tokens (required for remote admin)

Write-LogMessage "Step 4: Configuring LocalAccountTokenFilterPolicy..."

$tokenPolicyPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System"
$tokenPolicyName = "LocalAccountTokenFilterPolicy"

# Check if the registry value exists
$currentValue = Get-ItemProperty -Path $tokenPolicyPath -Name $tokenPolicyName -ErrorAction SilentlyContinue

if (-not $currentValue -or $currentValue.$tokenPolicyName -ne 1) {
    Write-LogMessage "Setting LocalAccountTokenFilterPolicy to 1 (disable token filtering)"

    # New-ItemProperty creates a new registry value
    # -PropertyType DWORD specifies a 32-bit integer
    # -Force overwrites if it exists
    New-ItemProperty -Path $tokenPolicyPath -Name $tokenPolicyName -Value 1 -PropertyType DWORD -Force | Out-Null
} else {
    Write-LogMessage "LocalAccountTokenFilterPolicy is already set to 1"
}

# -------------------------------------------------------------------------
# STEP 5: CONFIGURE FIREWALL RULES
# -------------------------------------------------------------------------
# Even though we disabled the firewall in bootstrap.ps1, we configure rules
# for when/if the firewall is re-enabled.
#
# WinRM uses:
# - Port 5985 for HTTP
# - Port 5986 for HTTPS

Write-LogMessage "Step 5: Configuring firewall rules for WinRM..."

# Create or update firewall rule for WinRM HTTP
$ruleName = "WinRM-HTTP-In-TCP"
$existingRule = Get-NetFirewallRule -Name $ruleName -ErrorAction SilentlyContinue

if (-not $existingRule) {
    Write-LogMessage "Creating firewall rule: $ruleName"

    # New-NetFirewallRule creates a Windows Firewall rule
    # Parameters:
    #   -Name: Unique identifier for the rule
    #   -DisplayName: Friendly name shown in GUI
    #   -Direction: Inbound or Outbound
    #   -Protocol: TCP, UDP, ICMPv4, etc.
    #   -LocalPort: Port number to allow
    #   -Action: Allow or Block
    New-NetFirewallRule `
        -Name $ruleName `
        -DisplayName "WinRM HTTP Inbound" `
        -Direction Inbound `
        -Protocol TCP `
        -LocalPort 5985 `
        -Action Allow `
        -Enabled True | Out-Null
} else {
    Write-LogMessage "Firewall rule exists, ensuring it's enabled..."
    Enable-NetFirewallRule -Name $ruleName -ErrorAction SilentlyContinue
}

# Also enable the built-in WinRM rules
Write-LogMessage "Enabling built-in WinRM firewall rules..."
Enable-NetFirewallRule -DisplayName "Windows Remote Management (HTTP-In)" -ErrorAction SilentlyContinue

# -------------------------------------------------------------------------
# STEP 6: TEST WINRM CONFIGURATION
# -------------------------------------------------------------------------
# Verify that WinRM is properly configured and accepting connections.

Write-LogMessage "Step 6: Testing WinRM configuration..."

# Test-WSMan tests WinRM connectivity
# When run locally without parameters, it tests the local WinRM configuration
try {
    $testResult = Test-WSMan -ErrorAction Stop
    Write-LogMessage "WinRM is responding correctly"
    Write-LogMessage "  ProductVendor: $($testResult.ProductVendor)"
    Write-LogMessage "  ProductVersion: $($testResult.ProductVersion)"
} catch {
    Write-LogMessage "WinRM test failed: $($_.Exception.Message)" -Level ERROR
    throw
}

# List current WinRM listeners
Write-LogMessage "Current WinRM listeners:"
$listeners = winrm enumerate winrm/config/listener 2>&1
$listeners -split "`n" | ForEach-Object {
    if ($_ -match "Transport|Address|Port") {
        Write-LogMessage "  $_"
    }
}

# Show WinRM authentication settings
Write-LogMessage "WinRM authentication configuration:"
$authConfig = winrm get winrm/config/service/auth 2>&1
$authConfig -split "`n" | ForEach-Object {
    if ($_ -match "(Basic|Kerberos|Negotiate|Certificate|CredSSP)\s+=") {
        Write-LogMessage "  $_"
    }
}

# -------------------------------------------------------------------------
# STEP 7: VERIFY FINAL STATE
# -------------------------------------------------------------------------
# Note: We DON'T restart WinRM here because Vagrant is connected via WinRM.
# Restarting would kill the connection and cause provisioning to fail.
# The configuration changes we made take effect immediately without restart.

Write-LogMessage "Step 7: Verifying final WinRM state..."

# Verify service is running
$serviceStatus = (Get-Service -Name WinRM).Status
if ($serviceStatus -eq 'Running') {
    Write-LogMessage "WinRM service is running"
} else {
    Write-LogMessage "WinRM service status: $serviceStatus" -Level WARN
}

# -------------------------------------------------------------------------
# FINAL STATUS
# -------------------------------------------------------------------------

Write-LogMessage "================================================"
Write-LogMessage "WinRM configuration complete!"
Write-LogMessage "================================================"
Write-LogMessage ""
Write-LogMessage "Connection details:"
Write-LogMessage "  Host: $env:COMPUTERNAME or IP address"
Write-LogMessage "  Port: 5985 (HTTP)"
Write-LogMessage "  Username: vagrant"
Write-LogMessage "  Password: vagrant"
Write-LogMessage ""
Write-LogMessage "Test from Linux/macOS host:"
Write-LogMessage "  pwsh -c `"Test-WSMan -ComputerName [ip-address]`""
Write-LogMessage ""
Write-LogMessage "WARNING: This configuration is for LAB USE ONLY!"
Write-LogMessage "Do not use these settings in production environments."

Stop-Transcript

exit 0
