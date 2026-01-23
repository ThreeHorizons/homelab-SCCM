#Requires -Version 5.1
<#
.SYNOPSIS
    Bootstrap script for SCCM homelab VMs.

.DESCRIPTION
    This script performs initial Windows configuration for lab VMs including:
    - Setting the computer name
    - Configuring timezone and regional settings
    - Disabling Windows Firewall (for lab use only!)
    - Configuring network adapter settings
    - Disabling Windows Update (prevents unexpected reboots during lab)
    - Enabling Remote Desktop
    - Setting PowerShell execution policy

    This script is designed to be IDEMPOTENT - safe to run multiple times.
    It checks the current state before making changes.

.PARAMETER ComputerName
    The desired computer name for this VM (e.g., DC01, SCCM01, CLIENT01)

.PARAMETER Role
    The role of this VM: DomainController, SCCMServer, or Client
    This affects which features and configurations are applied.

.EXAMPLE
    .\bootstrap.ps1 -ComputerName DC01 -Role DomainController

.NOTES
    Author: SCCM Homelab Project
    Version: 1.0

    WARNING: This script disables security features for lab convenience.
    DO NOT use these settings in production environments!

    POWERSHELL CONCEPTS EXPLAINED:

    1. Parameters block: Defines inputs to the script
       [CmdletBinding()] enables advanced function features
       [Parameter()] attributes define how parameters behave

    2. $ErrorActionPreference: Controls how errors are handled
       'Stop' = Errors throw exceptions (good for scripts)
       'Continue' = Errors show message but continue (default)

    3. Try/Catch: Exception handling for error recovery
       try { dangerous-thing } catch { handle-error }

    4. Splatting: Pass parameters as hashtables using @
       $params = @{Name='value'}; Command @params

    5. Here-strings: Multi-line strings using @" ... "@
       Useful for embedding scripts or large text blocks
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$ComputerName,

    [Parameter(Mandatory = $true)]
    [ValidateSet('DomainController', 'SCCMServer', 'Client')]
    [string]$Role
)

# -----------------------------------------------------------------------------
# SCRIPT CONFIGURATION
# -----------------------------------------------------------------------------

# Stop on any error - ensures we catch problems early
# This is critical for infrastructure scripts where partial execution is worse
# than failing fast and clearly
$ErrorActionPreference = 'Stop'

# Transcript logging - records all output to a file
# Useful for debugging provisioning issues
$LogPath = "C:\Logs"
if (-not (Test-Path $LogPath)) {
    New-Item -ItemType Directory -Path $LogPath -Force | Out-Null
}
Start-Transcript -Path "$LogPath\bootstrap-$(Get-Date -Format 'yyyyMMdd-HHmmss').log"

# -----------------------------------------------------------------------------
# HELPER FUNCTIONS
# -----------------------------------------------------------------------------

function Write-LogMessage {
    <#
    .SYNOPSIS
        Writes a timestamped log message to the console.

    .DESCRIPTION
        PowerShell function syntax:
        - function Name { } defines a function
        - param() block defines parameters (optional)
        - Everything after param() is the function body

        String formatting:
        - "Text $(expression)" evaluates expression inside string
        - This is called variable expansion or interpolation

    .PARAMETER Message
        The message to log

    .PARAMETER Level
        Log level: INFO, WARN, ERROR
    #>
    param(
        [string]$Message,
        [ValidateSet('INFO', 'WARN', 'ERROR')]
        [string]$Level = 'INFO'
    )

    # Get-Date -Format returns a formatted date string
    # 'yyyy-MM-dd HH:mm:ss' is a .NET date format string
    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'

    # String formatting with padded level for alignment
    # PadRight(5) adds spaces to make all levels same width
    Write-Host "[$timestamp] [$($Level.PadRight(5))] $Message"
}

function Test-IsRebootPending {
    <#
    .SYNOPSIS
        Checks if a reboot is pending from Windows Update or other sources.

    .DESCRIPTION
        This function checks various registry keys that Windows uses to track
        pending reboots. Important for automation to know if we need to reboot.

        Registry access in PowerShell:
        - Get-ItemProperty reads registry values
        - Test-Path checks if a key exists
        - Registry paths use special drives: HKLM:, HKCU:
    #>

    # Check Component Based Servicing (CBS) - Windows Update reboots
    $cbsReboot = Test-Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending"

    # Check Windows Update reboot flag
    $wuReboot = Test-Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired"

    # Check pending file rename operations (often from updates)
    $pendingFileRename = (Get-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager" -Name PendingFileRenameOperations -ErrorAction SilentlyContinue).PendingFileRenameOperations

    # Return true if any reboot indicator is present
    # -or is the logical OR operator in PowerShell
    return $cbsReboot -or $wuReboot -or ($null -ne $pendingFileRename)
}

# -----------------------------------------------------------------------------
# MAIN SCRIPT EXECUTION
# -----------------------------------------------------------------------------

Write-LogMessage "Starting bootstrap for $ComputerName (Role: $Role)"
Write-LogMessage "PowerShell Version: $($PSVersionTable.PSVersion)"
Write-LogMessage "Operating System: $((Get-CimInstance Win32_OperatingSystem).Caption)"

# Track if we need to reboot at the end
$rebootRequired = $false

# -------------------------------------------------------------------------
# STEP 1: SET COMPUTER NAME
# -------------------------------------------------------------------------
# Windows computer names are limited to 15 characters (NetBIOS legacy)
# The name is stored in the registry and takes effect after reboot

Write-LogMessage "Checking computer name..."

# $env:COMPUTERNAME is an environment variable with the current name
# PowerShell comparison operators: -ne (not equal), -eq (equal)
if ($env:COMPUTERNAME -ne $ComputerName) {
    Write-LogMessage "Renaming computer from '$env:COMPUTERNAME' to '$ComputerName'"

    # Rename-Computer changes the computer name
    # -Force suppresses confirmation prompts
    # -PassThru returns the result object (optional, for logging)
    Rename-Computer -NewName $ComputerName -Force
    $rebootRequired = $true
} else {
    Write-LogMessage "Computer name is already '$ComputerName'"
}

# -------------------------------------------------------------------------
# STEP 2: CONFIGURE TIMEZONE
# -------------------------------------------------------------------------
# Setting a consistent timezone prevents time sync issues in Active Directory
# AD Kerberos authentication is sensitive to time differences (>5 min skew = fail)

Write-LogMessage "Configuring timezone..."

# Get current timezone using Get-TimeZone cmdlet
$currentTz = (Get-TimeZone).Id

# Set to US Eastern Time - adjust this for your location
# Common timezones: "Pacific Standard Time", "UTC", "Central Standard Time"
$targetTz = "Eastern Standard Time"

if ($currentTz -ne $targetTz) {
    Write-LogMessage "Setting timezone from '$currentTz' to '$targetTz'"
    Set-TimeZone -Id $targetTz
} else {
    Write-LogMessage "Timezone is already '$targetTz'"
}

# -------------------------------------------------------------------------
# STEP 3: DISABLE WINDOWS FIREWALL (LAB ONLY!)
# -------------------------------------------------------------------------
# SECURITY WARNING: This is for lab convenience only!
# In production, you would configure specific firewall rules instead.
#
# Windows Firewall has three profiles:
# - Domain: Applied when connected to an AD domain
# - Private: Applied on private networks (home, work)
# - Public: Applied on public networks (coffee shop, airport)

Write-LogMessage "Configuring Windows Firewall..."

# Get-NetFirewallProfile retrieves firewall profile settings
# Where-Object filters the results (alias: ?)
# $_ represents the current item in the pipeline
$enabledProfiles = Get-NetFirewallProfile | Where-Object { $_.Enabled -eq $true }

if ($enabledProfiles) {
    Write-LogMessage "SECURITY WARNING: Disabling Windows Firewall for all profiles"

    # Set-NetFirewallProfile modifies firewall settings
    # -Profile specifies which profiles to modify
    # -Enabled $false turns off the firewall
    Set-NetFirewallProfile -Profile Domain, Private, Public -Enabled False
} else {
    Write-LogMessage "Windows Firewall is already disabled"
}

# -------------------------------------------------------------------------
# STEP 4: CONFIGURE NETWORK ADAPTERS
# -------------------------------------------------------------------------
# VirtualBox creates two network adapters:
# 1. NAT adapter (Ethernet) - Provides internet access
# 2. Host-Only adapter (Ethernet 2) - Lab network 192.168.56.x
#
# We want the Host-Only adapter to be primary for DNS/routing in the lab

Write-LogMessage "Configuring network adapters..."

# Get all network adapters
# Get-NetAdapter returns adapter objects with properties like Name, Status
$adapters = Get-NetAdapter | Where-Object { $_.Status -eq 'Up' }

Write-LogMessage "Found $($adapters.Count) active network adapter(s)"

foreach ($adapter in $adapters) {
    Write-LogMessage "  - $($adapter.Name): $($adapter.InterfaceDescription)"

    # Get IP configuration for this adapter
    # Get-NetIPAddress returns IP addresses bound to an adapter
    # -AddressFamily IPv4 filters to only IPv4 addresses
    $ipConfig = Get-NetIPAddress -InterfaceIndex $adapter.InterfaceIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue

    if ($ipConfig) {
        Write-LogMessage "    IP: $($ipConfig.IPAddress)"
    }
}

# -------------------------------------------------------------------------
# STEP 5: DISABLE WINDOWS UPDATE
# -------------------------------------------------------------------------
# Automatic updates can cause unexpected reboots during lab sessions.
# We disable the Windows Update service for lab convenience.
#
# Services in Windows:
# - Managed via sc.exe or PowerShell's *-Service cmdlets
# - StartType: Automatic, Manual, Disabled
# - Status: Running, Stopped, Paused

Write-LogMessage "Configuring Windows Update service..."

# Get-Service retrieves service status
$wuService = Get-Service -Name "wuauserv" -ErrorAction SilentlyContinue

if ($wuService) {
    if ($wuService.StartType -ne 'Disabled') {
        Write-LogMessage "Disabling Windows Update service"

        # Stop-Service stops a running service
        # Set-Service modifies service configuration
        # Use a timeout approach to avoid hanging indefinitely
        try {
            # Stop the service with a timeout
            Write-LogMessage "Stopping Windows Update service (this may take a moment)..."
            $wuService | Stop-Service -Force -NoWait -ErrorAction SilentlyContinue

            # Wait for service to stop, with timeout
            $timeout = 30  # seconds
            $elapsed = 0
            while ($wuService.Status -ne 'Stopped' -and $elapsed -lt $timeout) {
                Start-Sleep -Seconds 2
                $wuService.Refresh()
                $elapsed += 2
            }

            if ($wuService.Status -ne 'Stopped') {
                Write-LogMessage "Warning: Windows Update service did not stop within $timeout seconds, continuing anyway..." "WARN"
            } else {
                Write-LogMessage "Windows Update service stopped successfully"
            }
        }
        catch {
            Write-LogMessage "Warning: Failed to stop Windows Update service: $($_.Exception.Message)" "WARN"
        }

        # Set to disabled regardless of whether stop succeeded
        Set-Service -Name "wuauserv" -StartupType Disabled -ErrorAction SilentlyContinue
        Write-LogMessage "Windows Update service set to Disabled"
    } else {
        Write-LogMessage "Windows Update service is already disabled"
    }
}

# -------------------------------------------------------------------------
# STEP 6: ENABLE REMOTE DESKTOP
# -------------------------------------------------------------------------
# Remote Desktop Protocol (RDP) allows GUI access to Windows remotely.
# Required settings:
# 1. Enable RDP in the registry
# 2. Allow RDP through firewall (already disabled, but setting for when re-enabled)
# 3. Add users to Remote Desktop Users group (optional)

Write-LogMessage "Configuring Remote Desktop..."

# Check current RDP status via registry
# Registry path: HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server
# fDenyTSConnections: 0 = RDP enabled, 1 = RDP disabled
$rdpRegPath = "HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server"
$rdpEnabled = (Get-ItemProperty -Path $rdpRegPath -Name "fDenyTSConnections" -ErrorAction SilentlyContinue).fDenyTSConnections -eq 0

if (-not $rdpEnabled) {
    Write-LogMessage "Enabling Remote Desktop"

    # Set-ItemProperty modifies registry values
    Set-ItemProperty -Path $rdpRegPath -Name "fDenyTSConnections" -Value 0

    # Also disable Network Level Authentication (NLA) for easier access in lab
    # NLA requires authentication before connection - complicates testing
    Set-ItemProperty -Path $rdpRegPath -Name "UserAuthentication" -Value 0

    # Enable the RDP firewall rule (for when firewall is re-enabled)
    Enable-NetFirewallRule -DisplayGroup "Remote Desktop" -ErrorAction SilentlyContinue
} else {
    Write-LogMessage "Remote Desktop is already enabled"
}

# -------------------------------------------------------------------------
# STEP 7: SET POWERSHELL EXECUTION POLICY
# -------------------------------------------------------------------------
# Execution Policy controls which scripts can run:
# - Restricted: No scripts (default on client Windows)
# - AllSigned: Only signed scripts
# - RemoteSigned: Local scripts run, remote scripts need signatures
# - Unrestricted: All scripts run with warnings
# - Bypass: All scripts run without warnings (for automation)

Write-LogMessage "Configuring PowerShell execution policy..."

# Get-ExecutionPolicy returns current policy
# -Scope LocalMachine affects all users on this computer
$currentPolicy = Get-ExecutionPolicy -Scope LocalMachine
$effectivePolicy = Get-ExecutionPolicy

if ($currentPolicy -ne 'RemoteSigned' -and $effectivePolicy -ne 'Bypass' -and $effectivePolicy -ne 'Unrestricted') {
    Write-LogMessage "Setting execution policy from '$currentPolicy' to 'RemoteSigned'"

    # Set-ExecutionPolicy changes the policy
    # -Scope LocalMachine applies to all users
    # -Force suppresses confirmation
    # -ErrorAction Continue allows the script to continue even if overridden by Group Policy
    try {
        Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope LocalMachine -Force -ErrorAction SilentlyContinue
        Write-LogMessage "Execution policy set to RemoteSigned"
    }
    catch {
        Write-LogMessage "Note: Execution policy setting was overridden (effective policy: $effectivePolicy)" "INFO"
    }
} else {
    Write-LogMessage "Execution policy is already '$currentPolicy' (effective: $effectivePolicy)"
}

# -------------------------------------------------------------------------
# STEP 8: ROLE-SPECIFIC CONFIGURATION
# -------------------------------------------------------------------------
# Different VM roles need different Windows features and settings.
# We use a switch statement to handle each role.

Write-LogMessage "Applying role-specific configuration for: $Role"

# PowerShell switch statement - like if/elseif but cleaner for multiple values
switch ($Role) {
    'DomainController' {
        Write-LogMessage "Preparing for Domain Controller role..."

        # Note: Actual AD DS installation happens in Phase 3
        # Here we just prepare the system

        # Install required Windows features for AD DS
        # These are prerequisites for the domain controller role
        Write-LogMessage "Installing RSAT tools for future AD management..."

        # Check if RSAT-AD-Tools is available (Server OS only)
        $rsatFeature = Get-WindowsFeature -Name "RSAT-AD-Tools" -ErrorAction SilentlyContinue
        if ($rsatFeature -and $rsatFeature.InstallState -ne 'Installed') {
            # Install-WindowsFeature adds Windows Server roles/features
            Install-WindowsFeature -Name "RSAT-AD-Tools" -IncludeAllSubFeature -IncludeManagementTools
            Write-LogMessage "RSAT AD Tools installed"
        }
    }

    'SCCMServer' {
        Write-LogMessage "Preparing for SCCM Server role..."

        # SCCM requires various Windows features
        # Note: Actual SCCM prerequisites installed in Phase 3

        # Install IIS (required for SCCM management point and other roles)
        $iisFeature = Get-WindowsFeature -Name "Web-Server" -ErrorAction SilentlyContinue
        if ($iisFeature -and $iisFeature.InstallState -ne 'Installed') {
            Write-LogMessage "Installing IIS Web Server role..."
            Install-WindowsFeature -Name "Web-Server" -IncludeAllSubFeature -IncludeManagementTools
            Write-LogMessage "IIS installed"
            $rebootRequired = $true
        }

        # Install .NET Framework 3.5 (required for SCCM)
        $dotnet35 = Get-WindowsFeature -Name "NET-Framework-Core" -ErrorAction SilentlyContinue
        if ($dotnet35 -and $dotnet35.InstallState -ne 'Installed') {
            Write-LogMessage "Installing .NET Framework 3.5..."
            Install-WindowsFeature -Name "NET-Framework-Core"
            Write-LogMessage ".NET Framework 3.5 installed"
        }
    }

    'Client' {
        Write-LogMessage "Preparing for Client role..."

        # Clients don't need special features for now
        # They'll receive SCCM client after domain join

        # Enable ping responses (helpful for testing)
        Write-LogMessage "Ensuring ICMPv4 echo is allowed..."
        Enable-NetFirewallRule -Name "FPS-ICMP4-ERQ-In" -ErrorAction SilentlyContinue
    }
}

# -------------------------------------------------------------------------
# STEP 9: FINAL STATUS AND REBOOT CHECK
# -------------------------------------------------------------------------

Write-LogMessage "Bootstrap configuration complete for $ComputerName"

# Check for any pending reboots
if ($rebootRequired -or (Test-IsRebootPending)) {
    Write-LogMessage "NOTICE: A reboot is required to complete configuration"
    Write-LogMessage "The VM will reboot automatically..."

    # Don't actually reboot here - let Vagrant handle it
    # Vagrant will detect the pending reboot and handle it properly
} else {
    Write-LogMessage "No reboot required"
}

# Stop transcript logging
Stop-Transcript

# Exit with success code
# Exit codes: 0 = success, non-zero = error
exit 0
