<#
.SYNOPSIS
    Installs the SCCM client on a workstation.

.DESCRIPTION
    This script installs the Configuration Manager client manually on a
    workstation. This is an alternative to Client Push installation.

    ============================================================================
    TECHNOLOGY EXPLANATION: SCCM Client Installation
    ============================================================================

    The SCCM client (ccmsetup.exe) is the agent that runs on managed devices.
    It enables:
    - Policy retrieval from Management Point
    - Software deployment reception
    - Hardware/software inventory collection
    - Compliance scanning
    - Remote control
    - Software update scanning

    INSTALLATION METHODS:

    1. Client Push Installation (automatic)
       - SCCM pushes client to discovered computers
       - Requires admin$ share access
       - Requires firewall rules (135, 139, 445)
       - Configured in SCCM Console

    2. Manual Installation (this script)
       - Run ccmsetup.exe on the client
       - Useful when push fails
       - Good for troubleshooting

    3. Group Policy Installation
       - Deploy via GPO software installation
       - Runs as computer at startup

    4. Logon Script Installation
       - Deploy via logon script
       - User needs admin rights

    5. Task Sequence Installation
       - Install during OSD
       - Most common for new deployments

    CLIENT INSTALLATION PARAMETERS:

    ccmsetup.exe supports many parameters:

    /mp:<ManagementPoint>
       - Specifies initial MP to contact
       - Example: /mp:sccm01.lab.local

    SMSSITECODE=<SiteCode>
       - Assigns client to specific site
       - Example: SMSSITECODE=PS1
       - Use SMSSITECODE=AUTO for automatic assignment

    /source:<Path>
       - UNC path to client installation files
       - Copies locally then installs

    /logon
       - Prevents installation if user is logged on

    /BITSPriority:<Priority>
       - BITS download priority (FOREGROUND, HIGH, NORMAL, LOW)

    /skipprereq:<Filename>
       - Skip specific prerequisite check

    /forceinstall
       - Force reinstall even if client exists

    FSP=<ServerName>
       - Fallback Status Point for offline reporting

    CCMHOSTNAME=<CMGHostname>
       - Cloud Management Gateway hostname (for cloud-managed clients)

    CLIENT INSTALLATION PROCESS:

    1. ccmsetup.exe starts
    2. Downloads prerequisites
    3. Contacts Management Point
    4. Downloads client files
    5. Installs client
    6. Client registers with site
    7. Receives policies

    LOGS:
    - Installation: C:\Windows\ccmsetup\Logs\ccmsetup.log
    - Client: C:\Windows\CCM\Logs\

    ============================================================================

.PARAMETER SCCMServer
    SCCM site server name or Management Point.
    Default: SCCM01

.PARAMETER SiteCode
    SCCM site code.
    Default: PS1

.PARAMETER SourcePath
    UNC path to client installation files.
    Default: \\SCCM01\SMS_PS1\Client

.PARAMETER ForceReinstall
    Force reinstallation even if client is already installed.

.EXAMPLE
    .\Install-SCCMClient.ps1

.EXAMPLE
    .\Install-SCCMClient.ps1 -SCCMServer "sccm01.lab.local" -SiteCode "PS1" -ForceReinstall

.NOTES
    Author: Homelab-SCCM Project
    Requires: Domain membership, network access to SCCM server
    Run on: CLIENT01, CLIENT02, etc.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$SCCMServer = "SCCM01",

    [Parameter(Mandatory = $false)]
    [ValidatePattern("^[A-Z0-9]{3}$")]
    [string]$SiteCode = "PS1",

    [Parameter(Mandatory = $false)]
    [string]$SourcePath,

    [Parameter(Mandatory = $false)]
    [switch]$ForceReinstall
)

# ============================================================================
# SCRIPT INITIALIZATION
# ============================================================================

$modulePath = Join-Path (Split-Path $PSScriptRoot -Parent) "modules"
Import-Module -Name (Join-Path $modulePath "Logger.psm1") -Force -ErrorAction Stop
Import-Module -Name (Join-Path $modulePath "Validator.psm1") -Force -ErrorAction Stop

Initialize-Logging -LogName "Install-SCCMClient"

Write-LogSection "SCCM Client Installation"

# ============================================================================
# PRE-INSTALLATION CHECKS
# ============================================================================

Write-Log "Performing pre-installation checks..." -Level INFO

# Check 1: Domain membership
if (-not (Test-DomainJoined)) {
    Write-LogError "This computer is not domain-joined."
    Write-Log "Join the domain before installing SCCM client." -Level ERROR
    throw "Domain membership required"
}

$domain = (Get-WmiObject Win32_ComputerSystem).Domain
Write-Log "Domain membership verified: $domain" -Level SUCCESS

# Check 2: Check if client is already installed
if (Test-SCCMClientInstalled) {
    $ccmService = Get-Service -Name CcmExec -ErrorAction SilentlyContinue

    if ($ForceReinstall) {
        Write-Log "SCCM client already installed. ForceReinstall specified - will reinstall." -Level WARN
    } else {
        Write-Log "SCCM client is already installed and running." -Level INFO

        # Get client version
        try {
            $client = New-Object -ComObject Microsoft.SMS.Client
            Write-Log "Client Version: $($client.GetClientVersion())" -Level INFO
            Write-Log "Assigned Site: $($client.GetAssignedSite())" -Level INFO
        }
        catch {
            Write-Log "Could not get client details." -Level DEBUG
        }

        Write-Log "Use -ForceReinstall to reinstall." -Level INFO
        Complete-Logging
        return
    }
}

# Check 3: Network connectivity to SCCM server
Write-Log "Checking network connectivity to $SCCMServer..." -Level INFO

if (-not (Test-NetworkConnectivity -ComputerName $SCCMServer)) {
    Write-LogError "Cannot reach SCCM server: $SCCMServer"
    Write-Log "Verify network connectivity and firewall rules." -Level ERROR
    throw "Cannot reach SCCM server"
}

Write-Log "SCCM server is reachable." -Level SUCCESS

# Check 4: DNS resolution
Write-Log "Checking DNS resolution..." -Level INFO

try {
    $dnsResult = Resolve-DnsName -Name $SCCMServer -ErrorAction Stop
    Write-Log "DNS resolution successful: $($dnsResult.IPAddress)" -Level SUCCESS
}
catch {
    Write-LogError "DNS resolution failed for $SCCMServer"
    Write-Log "Verify DNS configuration." -Level ERROR
    throw "DNS resolution failed"
}

# ============================================================================
# LOCATE CLIENT INSTALLATION FILES
# ============================================================================

Write-LogSection "Locating Client Installation Files"

# Default source path is the SMS_<SiteCode>\Client share
if (-not $SourcePath) {
    $SourcePath = "\\$SCCMServer\SMS_$SiteCode\Client"
}

Write-Log "Checking for client files at: $SourcePath" -Level INFO

# Test access to the share
$ccmsetupSource = Join-Path $SourcePath "ccmsetup.exe"

if (-not (Test-Path $ccmsetupSource)) {
    Write-Log "Client files not found at default location." -Level WARN

    # Try alternate locations
    $alternatePaths = @(
        "\\$SCCMServer\ccmsetup$",
        "\\$SCCMServer\SMSCLIENT",
        "\\$SCCMServer\CCM_Client"
    )

    $found = $false
    foreach ($altPath in $alternatePaths) {
        $testPath = Join-Path $altPath "ccmsetup.exe"
        if (Test-Path $testPath) {
            $SourcePath = $altPath
            $ccmsetupSource = $testPath
            $found = $true
            Write-Log "Found client files at: $SourcePath" -Level SUCCESS
            break
        }
    }

    if (-not $found) {
        Write-LogError "Cannot find SCCM client installation files."
        Write-Log "Tried locations:" -Level ERROR
        Write-Log "  $SourcePath\ccmsetup.exe" -Level ERROR
        foreach ($alt in $alternatePaths) {
            Write-Log "  $alt\ccmsetup.exe" -Level ERROR
        }
        throw "Client files not found"
    }
} else {
    Write-Log "Client files found at: $SourcePath" -Level SUCCESS
}

# ============================================================================
# COPY CLIENT FILES LOCALLY
# ============================================================================

Write-LogSection "Copying Client Files"

$localClientDir = "C:\Temp\CCMSetup"

Write-Log "Creating local directory: $localClientDir" -Level INFO
New-Item -Path $localClientDir -ItemType Directory -Force | Out-Null

Write-Log "Copying ccmsetup.exe..." -Level INFO

try {
    Copy-Item -Path $ccmsetupSource -Destination $localClientDir -Force
    Write-Log "ccmsetup.exe copied successfully." -Level SUCCESS
}
catch {
    Write-LogError "Failed to copy ccmsetup.exe: $_"
    throw
}

$localCcmsetup = Join-Path $localClientDir "ccmsetup.exe"

# ============================================================================
# BUILD INSTALLATION COMMAND
# ============================================================================

Write-LogSection "Building Installation Command"

# SYNTAX EXPLANATION: Client Installation Parameters
# Each parameter controls different aspects of installation

$installParams = @()

# Management Point - where to get policies from
# /mp specifies the initial MP for client registration
$installParams += "/mp:$SCCMServer"

# Site Code - which site to assign to
# Can also use SMSSITECODE=AUTO for automatic assignment
$installParams += "SMSSITECODE=$SiteCode"

# Source - where to download additional files from
$installParams += "/source:$SourcePath"

# Force reinstall if specified
if ($ForceReinstall) {
    $installParams += "/forceinstall"
}

# Additional useful parameters (uncomment as needed):
# $installParams += "/logon"  # Don't install if user logged on
# $installParams += "FSP=$SCCMServer"  # Fallback Status Point
# $installParams += "/BITSPriority:FOREGROUND"  # Download priority

$installCommand = $installParams -join " "

Write-Log "Installation command:" -Level INFO
Write-Log "  ccmsetup.exe $installCommand" -Level INFO

# ============================================================================
# INSTALL SCCM CLIENT
# ============================================================================

Write-LogSection "Installing SCCM Client"

Write-Log "Starting SCCM client installation..." -Level INFO
Write-Log "This may take 5-15 minutes depending on network speed." -Level INFO

# SYNTAX EXPLANATION: Start-Process for ccmsetup
# ccmsetup.exe runs asynchronously by default
# It spawns a background process and exits immediately
# The actual installation happens in the background
# Logs are written to C:\Windows\ccmsetup\Logs\ccmsetup.log

$process = Start-Process -FilePath $localCcmsetup `
    -ArgumentList $installCommand `
    -Wait:$false `
    -NoNewWindow `
    -PassThru

Write-Log "ccmsetup.exe started (PID: $($process.Id))." -Level INFO
Write-Log "ccmsetup spawns background processes for actual installation." -Level INFO

# Wait for the initial process to complete (this is quick)
$process.WaitForExit(60000) # 1 minute timeout for initial launch

# ============================================================================
# MONITOR INSTALLATION
# ============================================================================

Write-LogSection "Monitoring Installation Progress"

$ccmsetupLog = "C:\Windows\ccmsetup\Logs\ccmsetup.log"
$maxWaitMinutes = 15
$checkIntervalSeconds = 30
$elapsedMinutes = 0

Write-Log "Monitoring installation progress (max wait: $maxWaitMinutes minutes)..." -Level INFO
Write-Log "Log file: $ccmsetupLog" -Level INFO

while ($elapsedMinutes -lt $maxWaitMinutes) {
    Start-Sleep -Seconds $checkIntervalSeconds
    $elapsedMinutes += ($checkIntervalSeconds / 60)

    # Check for completion indicators

    # Check 1: Is the CcmExec service running?
    $ccmService = Get-Service -Name CcmExec -ErrorAction SilentlyContinue
    if ($ccmService -and $ccmService.Status -eq "Running") {
        Write-Log "CcmExec service is now running!" -Level SUCCESS
        break
    }

    # Check 2: Parse the log file for completion
    if (Test-Path $ccmsetupLog) {
        $logContent = Get-Content $ccmsetupLog -Tail 20 -ErrorAction SilentlyContinue

        # Look for completion messages
        $completed = $logContent | Select-String -Pattern "CcmSetup is exiting with return code 0"
        $failed = $logContent | Select-String -Pattern "CcmSetup failed|error code|installation failed"

        if ($completed) {
            Write-Log "Installation completed successfully per log file." -Level SUCCESS
            break
        }

        if ($failed) {
            Write-LogError "Installation appears to have failed."
            Write-Log "Check $ccmsetupLog for details." -Level ERROR
            break
        }

        # Show current status
        $status = $logContent | Select-String -Pattern "Installing|Downloading|Running|Copying" | Select-Object -Last 1
        if ($status) {
            Write-Log "Status: $($status.Line.Trim())" -Level DEBUG
        }
    }

    Write-Log "Waiting... ($([math]::Round($elapsedMinutes, 1)) minutes elapsed)" -Level DEBUG
}

# ============================================================================
# VERIFY INSTALLATION
# ============================================================================

Write-LogSection "Verifying Installation"

# Give client a moment to fully start
Start-Sleep -Seconds 10

# Check 1: CcmExec service
Write-Log "Checking SMS Agent Host service (CcmExec)..." -Level INFO

$ccmService = Get-Service -Name CcmExec -ErrorAction SilentlyContinue

if ($ccmService) {
    if ($ccmService.Status -eq "Running") {
        Write-Log "SMS Agent Host service is running." -Level SUCCESS
    } else {
        Write-Log "SMS Agent Host service status: $($ccmService.Status)" -Level WARN
        Write-Log "Attempting to start service..." -Level INFO
        Start-Service -Name CcmExec -ErrorAction SilentlyContinue
    }
} else {
    Write-LogError "SMS Agent Host service not found."
    Write-Log "Installation may have failed." -Level ERROR
}

# Check 2: CCM client components
Write-Log "Checking client components..." -Level INFO

$ccmDir = "C:\Windows\CCM"
if (Test-Path $ccmDir) {
    Write-Log "CCM directory exists: $ccmDir" -Level SUCCESS
} else {
    Write-Log "CCM directory not found." -Level WARN
}

# Check 3: Control Panel applet
Write-Log "Checking Configuration Manager control panel..." -Level INFO

$cplPath = "C:\Windows\CCM\SMSCFGRC.cpl"
if (Test-Path $cplPath) {
    Write-Log "Configuration Manager control panel installed." -Level SUCCESS
} else {
    Write-Log "Control panel not found (may still be installing)." -Level WARN
}

# Check 4: Get client version and site assignment
Write-Log "Checking client registration..." -Level INFO

try {
    $client = New-Object -ComObject Microsoft.SMS.Client
    $version = $client.GetClientVersion()
    $assignedSite = $client.GetAssignedSite()

    Write-Log "Client Version: $version" -Level SUCCESS
    Write-Log "Assigned Site: $(if ($assignedSite) {$assignedSite} else {'Not yet assigned'})" -Level INFO
}
catch {
    Write-Log "Client COM object not available yet." -Level WARN
    Write-Log "Client may still be initializing." -Level INFO
}

# Check 5: Log file status
Write-Log "Checking installation log for errors..." -Level INFO

if (Test-Path $ccmsetupLog) {
    $errors = Get-Content $ccmsetupLog | Select-String -Pattern "error|failed" -CaseSensitive:$false

    if ($errors) {
        Write-Log "Potential issues found in log:" -Level WARN
        $errors | Select-Object -Last 5 | ForEach-Object {
            Write-Log "  $_" -Level WARN
        }
    } else {
        Write-Log "No critical errors found in log." -Level SUCCESS
    }
}

# ============================================================================
# SUMMARY
# ============================================================================

Write-LogSection "SCCM Client Installation Complete"

$ccmService = Get-Service -Name CcmExec -ErrorAction SilentlyContinue

if ($ccmService -and $ccmService.Status -eq "Running") {
    Write-Log "SCCM client installation completed successfully!" -Level SUCCESS
} else {
    Write-Log "SCCM client installation may be incomplete." -Level WARN
    Write-Log "Check logs and wait for services to start." -Level INFO
}

Write-Log "" -Level INFO
Write-Log "Installation Summary:" -Level INFO
Write-Log "  Server: $SCCMServer" -Level INFO
Write-Log "  Site Code: $SiteCode" -Level INFO
Write-Log "  Service Status: $(if ($ccmService) {$ccmService.Status} else {'Not Found'})" -Level INFO
Write-Log "" -Level INFO
Write-Log "Log Files:" -Level INFO
Write-Log "  Installation: $ccmsetupLog" -Level INFO
Write-Log "  Client Logs: C:\Windows\CCM\Logs\" -Level INFO
Write-Log "" -Level INFO
Write-Log "Next Steps:" -Level INFO
Write-Log "  1. Wait a few minutes for client to fully initialize" -Level INFO
Write-Log "  2. Open Configuration Manager in Control Panel" -Level INFO
Write-Log "  3. Click 'Actions' tab and run 'Machine Policy Retrieval'" -Level INFO
Write-Log "  4. Verify client appears in SCCM Console" -Level INFO
Write-Log "" -Level INFO
Write-Log "To open Configuration Manager applet:" -Level INFO
Write-Log "  Control Panel > Configuration Manager" -Level INFO
Write-Log "  Or run: control smscfgrc" -Level INFO

# Cleanup temp files
Write-Log "Cleaning up temporary files..." -Level DEBUG
Remove-Item -Path $localClientDir -Recurse -Force -ErrorAction SilentlyContinue

Complete-Logging
