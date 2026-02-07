<#
.SYNOPSIS
    Installs SCCM (Configuration Manager) Primary Site.

.DESCRIPTION
    This script performs an unattended installation of a standalone
    Configuration Manager Primary Site.

    ============================================================================
    TECHNOLOGY EXPLANATION: SCCM Installation
    ============================================================================

    WHAT IS SCCM?

    System Center Configuration Manager (SCCM), now called Microsoft Endpoint
    Configuration Manager or just Configuration Manager, is Microsoft's
    enterprise endpoint management platform.

    It handles:
    - Software deployment (applications, packages, updates)
    - Operating System Deployment (bare-metal to running OS)
    - Inventory (hardware and software)
    - Compliance settings
    - Remote control
    - Endpoint protection integration

    SCCM SITE TYPES:

    1. Central Administration Site (CAS)
       - Top of hierarchy, administrative only
       - No clients report directly to it
       - Used for very large environments (100,000+ clients)
       - NOT needed for labs or most organizations

    2. Primary Site (what we're installing)
       - The main site that manages clients
       - Has its own SQL database
       - Can exist standalone or under a CAS
       - Supports up to 150,000 clients

    3. Secondary Site
       - Child of a primary site
       - Used for remote offices with slow WAN links
       - Shares database with parent primary site
       - Provides local DP and MP services

    For our lab, we install a STANDALONE PRIMARY SITE.

    SCCM SITE SYSTEM ROLES:

    Site systems are servers that provide specific SCCM functionality:

    1. Site Server (installed with primary site)
       - Core SCCM services
       - Site database connection
       - Component management

    2. Site Database Server (SQL Server)
       - Stores all SCCM data
       - Can be same server or remote

    3. SMS Provider
       - WMI interface for SCCM administration
       - Console connects through this
       - Usually on site server

    4. Management Point (MP)
       - Client communication endpoint
       - Clients get policies from MP
       - Clients report status to MP
       - CRITICAL - without MP, no client management

    5. Distribution Point (DP)
       - Hosts content (packages, applications, images)
       - Clients download content from DP
       - Can have many DPs for geographic distribution

    INSTALLATION FILES:

    SCCM installation media contains:
    - Setup.exe - Main installer
    - SMSSETUP\ - Setup files
    - Tools\ - Various utilities

    The setup is driven by a script file (INI format) that specifies:
    - Site code and name
    - SQL Server location
    - Installation paths
    - Initial roles to install
    - License key (evaluation or full)

    INSTALLATION DURATION:

    SCCM installation takes 30-60 minutes because:
    - Creates large SQL database
    - Installs many Windows services
    - Configures IIS applications
    - Sets up management point/distribution point
    - Processes initial configuration

    POST-INSTALLATION:

    After setup completes, SCCM needs configuration:
    - Site boundaries and boundary groups
    - Discovery methods
    - Client settings
    - Client push or manual client installation

    ============================================================================

.PARAMETER SCCMMediaPath
    Path to SCCM installation media (root of ISO or extracted folder).
    Setup.exe should be at: <path>\SMSSETUP\BIN\X64\Setup.exe

.PARAMETER SiteCode
    Three-character site code (e.g., "PS1", "LAB").
    Must be unique across all SCCM sites you manage.
    Default: PS1

.PARAMETER SiteName
    Descriptive name for the site.
    Default: Primary Site 1

.PARAMETER SQLServerName
    Name of SQL Server (can include instance: SERVER\INSTANCE).
    Default: SCCM01 (localhost, default instance)

.PARAMETER InstallDir
    Installation directory for SCCM.
    Default: C:\Program Files\Microsoft Configuration Manager

.PARAMETER ProductKey
    SCCM product key. Leave empty for evaluation.
    Default: EVAL (180-day evaluation)

.EXAMPLE
    .\Install-SCCM.ps1 -SCCMMediaPath "D:\"

.EXAMPLE
    .\Install-SCCM.ps1 -SCCMMediaPath "C:\SCCM_Media" -SiteCode "LAB" -SiteName "Lab Site"

.NOTES
    Author: Homelab-SCCM Project
    Requires: All prerequisites installed, SQL Server running
    Run on: SCCM01
    Duration: 30-60 minutes
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$SCCMMediaPath,

    [Parameter(Mandatory = $false)]
    [ValidatePattern("^[A-Z0-9]{3}$")]
    [string]$SiteCode = "PS1",

    [Parameter(Mandatory = $false)]
    [string]$SiteName = "Primary Site 1",

    [Parameter(Mandatory = $false)]
    [string]$SQLServerName = $env:COMPUTERNAME,

    [Parameter(Mandatory = $false)]
    [string]$InstallDir = "C:\Program Files\Microsoft Configuration Manager",

    [Parameter(Mandatory = $false)]
    [string]$ProductKey = "EVAL"
)

# ============================================================================
# SCRIPT INITIALIZATION
# ============================================================================

$modulePath = Join-Path (Split-Path $PSScriptRoot -Parent) "modules"
Import-Module -Name (Join-Path $modulePath "Logger.psm1") -Force -ErrorAction Stop
Import-Module -Name (Join-Path $modulePath "Validator.psm1") -Force -ErrorAction Stop

Initialize-Logging -LogName "Install-SCCM"

Write-LogSection "SCCM Primary Site Installation"

# ============================================================================
# PRE-INSTALLATION CHECKS
# ============================================================================

Write-Log "Performing pre-installation verification..." -Level INFO

# Check 1: Verify SCCM isn't already installed
if (Test-SCCMInstalled) {
    Write-Log "SCCM is already installed on this system." -Level WARN

    # Check if our site code exists
    $existingSite = Get-WmiObject -Namespace "root\SMS" -Class "SMS_ProviderLocation" -ErrorAction SilentlyContinue
    if ($existingSite) {
        Write-Log "Existing site detected: $($existingSite.SiteCode)" -Level INFO
    }

    Write-Log "If you need to reinstall, uninstall first via setup.exe /uninstall" -Level INFO
    Complete-Logging
    return
}

# Check 2: Verify Setup.exe exists
$setupExe = Join-Path $SCCMMediaPath "SMSSETUP\BIN\X64\Setup.exe"
if (-not (Test-Path $setupExe)) {
    Write-LogError "SCCM Setup.exe not found at: $setupExe"
    Write-Log "Verify SCCMMediaPath points to valid SCCM installation media." -Level ERROR
    throw "Setup.exe not found"
}

Write-Log "SCCM Setup found: $setupExe" -Level SUCCESS

# Check 3: Verify SQL Server is running
Write-Log "Verifying SQL Server..." -Level INFO

if (-not (Test-SQLServerInstalled)) {
    Write-LogError "SQL Server is not installed or not running."
    Write-Log "Install SQL Server before installing SCCM." -Level ERROR
    throw "SQL Server required"
}

# Verify we can connect to SQL
try {
    $sqlConnection = Invoke-Sqlcmd -Query "SELECT 1 AS Test" -ServerInstance $SQLServerName -ErrorAction Stop
    Write-Log "SQL Server connection verified: $SQLServerName" -Level SUCCESS
}
catch {
    Write-LogError "Cannot connect to SQL Server: $SQLServerName"
    Write-Log "Error: $_" -Level ERROR
    throw "SQL Server connection failed"
}

# Verify SQL collation
try {
    $collation = Invoke-Sqlcmd -Query "SELECT SERVERPROPERTY('Collation') AS Collation" -ServerInstance $SQLServerName
    if ($collation.Collation -ne "SQL_Latin1_General_CP1_CI_AS") {
        Write-LogError "SQL Server collation is incorrect: $($collation.Collation)"
        Write-Log "SCCM requires: SQL_Latin1_General_CP1_CI_AS" -Level ERROR
        throw "Invalid SQL collation"
    }
    Write-Log "SQL Server collation verified: $($collation.Collation)" -Level SUCCESS
}
catch {
    if ($_.Exception.Message -notmatch "Invalid SQL collation") {
        Write-Log "Could not verify SQL collation. Continuing..." -Level WARN
    } else {
        throw
    }
}

# Check 4: Verify domain membership
if (-not (Test-DomainJoined)) {
    Write-LogError "This computer is not domain-joined."
    Write-Log "SCCM requires domain membership for proper functionality." -Level ERROR
    throw "Domain membership required"
}

Write-Log "Domain membership verified: $((Get-WmiObject Win32_ComputerSystem).Domain)" -Level SUCCESS

# Check 5: Verify Windows ADK
$adkPath = "C:\Program Files (x86)\Windows Kits\10\Assessment and Deployment Kit"
if (-not (Test-Path $adkPath)) {
    Write-LogError "Windows ADK not found at: $adkPath"
    Write-Log "Install Windows ADK before SCCM installation." -Level ERROR
    throw "Windows ADK required"
}

Write-Log "Windows ADK found." -Level SUCCESS

# Check Windows PE
$winPEPath = Join-Path $adkPath "Windows Preinstallation Environment"
if (-not (Test-Path $winPEPath)) {
    Write-Log "Windows PE add-on not found. OSD features may not work." -Level WARN
} else {
    Write-Log "Windows PE add-on found." -Level SUCCESS
}

# Check 6: Verify IIS and prerequisites
$iisFeature = Get-WindowsFeature -Name Web-Server
if ($iisFeature.InstallState -ne "Installed") {
    Write-LogError "IIS is not installed. Run Install-Prerequisites.ps1 first."
    throw "IIS required"
}

Write-Log "IIS is installed." -Level SUCCESS

# Check 7: Disk space
$installDrive = Split-Path $InstallDir -Qualifier
$disk = Get-WmiObject Win32_LogicalDisk -Filter "DeviceID='$installDrive'"
$freeSpaceGB = [math]::Round($disk.FreeSpace / 1GB, 2)

if ($freeSpaceGB -lt 20) {
    Write-LogError "Insufficient disk space on $installDrive. Need 20GB, have $freeSpaceGB GB."
    throw "Insufficient disk space"
}

Write-Log "Disk space on $installDrive`: $freeSpaceGB GB free" -Level SUCCESS

# ============================================================================
# CREATE CONFIGURATION FILE
# ============================================================================

Write-LogSection "Creating SCCM Setup Configuration File"

# The setup script (INI file) tells SCCM setup all the options
# This avoids interactive prompts during installation

$configContent = @"
; ============================================================================
; SCCM PRIMARY SITE INSTALLATION CONFIGURATION
; ============================================================================
; Generated by Install-SCCM.ps1
; Date: $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")
;
; This file is used for unattended SCCM installation.
; Reference: https://learn.microsoft.com/en-us/mem/configmgr/core/servers/deploy/install/command-line-options-for-setup
; ============================================================================

[Identification]
; Action: What type of installation
; InstallPrimarySite = Install a new primary site
; Other options: InstallCAS, RecoverPrimarySite, UpgradePrimarySite, etc.
Action=InstallPrimarySite

[Options]
; ProductID: License key or EVAL for evaluation
; EVAL gives 180-day evaluation period (sufficient for lab)
ProductID=$ProductKey

; SiteCode: Three-character unique site identifier
; Used in all SCCM references to this site
; Cannot be changed after installation
SiteCode=$SiteCode

; SiteName: Human-readable site description
SiteName=$SiteName

; SMSInstallDir: Where to install SCCM
; Default: C:\Program Files\Microsoft Configuration Manager
SMSInstallDir=$InstallDir

; SDKServer: Server hosting the SMS Provider (WMI)
; Usually the site server itself
SDKServer=$env:COMPUTERNAME

; RoleCommunicationProtocol: HTTP or HTTPS
; For lab, HTTP is fine; production should use HTTPS
RoleCommunicationProtocol=HTTPorHTTPS

; ClientsUsePKICertificate: Whether clients use PKI certificates
; 0 = No (self-signed certificates)
; 1 = Yes (requires PKI infrastructure)
; For lab without PKI, use 0
ClientsUsePKICertificate=0

; PrerequisiteComp: Automatically download prerequisites
; 1 = Download prerequisites during setup
; 0 = Prerequisites already downloaded
PrerequisiteComp=1

; PrerequisitePath: Where to store/find prerequisite files
PrerequisitePath=C:\Temp\SCCMPrereqs

; AdminConsole: Install the SCCM console
; 1 = Yes
; 0 = No
AdminConsole=1

; JoinCEIP: Join Customer Experience Improvement Program
; 0 = No
; 1 = Yes
JoinCEIP=0

; MobileDeviceLanguage: Install mobile device language components
; 0 = No (not needed for most labs)
MobileDeviceLanguage=0

[SQLConfigOptions]
; SQLServerName: SQL Server name (and instance if not default)
; Format: SERVER or SERVER\INSTANCE
SQLServerName=$SQLServerName

; DatabaseName: Name for the SCCM database
; Format: CM_<SiteCode>
; This is created automatically by setup
DatabaseName=CM_$SiteCode

; SQLSSBPort: SQL Server Service Broker port
; Default is 4022
; Used for SCCM internal communication
SQLSSBPort=4022

; SQLDataFilePath: Where to put database data file (.mdf)
; Leave empty for SQL Server default
SQLDataFilePath=

; SQLLogFilePath: Where to put database log file (.ldf)
; Leave empty for SQL Server default
SQLLogFilePath=

[CloudConnectorOptions]
; CloudConnector: Enable cloud management features
; 0 = Disable (can enable later)
; 1 = Enable (requires Azure subscription)
CloudConnector=0

[SABranchOptions]
; SAActive: Software Assurance active (for Current Branch updates)
; 1 = Yes (enables automatic updates)
; 0 = No
SAActive=1

; CurrentBranch: Use Current Branch update channel
; 1 = Yes (recommended, gets regular updates)
CurrentBranch=1

[HierarchyExpansionOption]
; CCARSiteServer: Central Administration Site server (if any)
; Leave empty for standalone primary site
CCARSiteServer=

"@

$configPath = "C:\Temp\SCCMSetup.ini"
Write-Log "Writing configuration to: $configPath" -Level INFO

# Ensure directory exists
New-Item -Path (Split-Path $configPath -Parent) -ItemType Directory -Force -ErrorAction SilentlyContinue | Out-Null

Set-Content -Path $configPath -Value $configContent -Encoding ASCII
Write-Log "Configuration file created." -Level SUCCESS

# Display key settings
Write-Log "" -Level INFO
Write-Log "Installation Settings:" -Level INFO
Write-Log "  Site Code: $SiteCode" -Level INFO
Write-Log "  Site Name: $SiteName" -Level INFO
Write-Log "  SQL Server: $SQLServerName" -Level INFO
Write-Log "  Database: CM_$SiteCode" -Level INFO
Write-Log "  Install Directory: $InstallDir" -Level INFO
Write-Log "  Product Key: $(if ($ProductKey -eq 'EVAL') {'Evaluation (180 days)'} else {'Licensed'})" -Level INFO

# ============================================================================
# RUN PREREQUISITE CHECK
# ============================================================================

Write-LogSection "Running SCCM Prerequisite Check"

Write-Log "Running setup prerequisite checker..." -Level INFO
Write-Log "This verifies all requirements are met before installation." -Level INFO

# SYNTAX EXPLANATION: Setup.exe /PREREQ
# The /PREREQ switch runs only the prerequisite checker
# Exit code 0 = all prerequisites pass
# Non-zero = something failed

$prereqProcess = Start-Process -FilePath $setupExe `
    -ArgumentList "/PREREQ /SCRIPT `"$configPath`"" `
    -Wait -NoNewWindow -PassThru

if ($prereqProcess.ExitCode -ne 0) {
    Write-LogError "Prerequisite check failed with exit code: $($prereqProcess.ExitCode)"
    Write-Log "Check the prerequisite log for details:" -Level ERROR
    Write-Log "  C:\ConfigMgrPrereq.log" -Level ERROR

    # Try to display relevant errors
    $prereqLog = "C:\ConfigMgrPrereq.log"
    if (Test-Path $prereqLog) {
        Write-Log "`nPrerequisite failures:" -Level ERROR
        Get-Content $prereqLog | Where-Object { $_ -match "ERROR|FAIL" } | ForEach-Object {
            Write-Log "  $_" -Level ERROR
        }
    }

    throw "Prerequisite check failed"
}

Write-Log "Prerequisite check passed!" -Level SUCCESS

# ============================================================================
# INSTALL SCCM
# ============================================================================

Write-LogSection "Installing SCCM Primary Site"

Write-Log "" -Level INFO
Write-Log "========================================" -Level WARN
Write-Log "STARTING SCCM INSTALLATION" -Level WARN
Write-Log "This will take 30-60 minutes!" -Level WARN
Write-Log "Do not interrupt the process." -Level WARN
Write-Log "========================================" -Level WARN
Write-Log "" -Level INFO

# Create a background job to monitor progress
$logPath = Join-Path $InstallDir "Logs\ConfigMgrSetup.log"

Write-Log "Starting SCCM setup..." -Level INFO
Write-Log "Setup command: $setupExe /SCRIPT `"$configPath`"" -Level DEBUG

# Start the installation
# SYNTAX EXPLANATION: Setup.exe /SCRIPT
# /SCRIPT: Path to configuration file for unattended install
# The process will run for 30-60 minutes

$installProcess = Start-Process -FilePath $setupExe `
    -ArgumentList "/SCRIPT `"$configPath`"" `
    -Wait -NoNewWindow -PassThru

$exitCode = $installProcess.ExitCode

# ============================================================================
# CHECK INSTALLATION RESULT
# ============================================================================

Write-LogSection "Installation Result"

# Check exit code
switch ($exitCode) {
    0 {
        Write-Log "SCCM installation completed successfully!" -Level SUCCESS
    }
    default {
        Write-LogError "SCCM installation failed with exit code: $exitCode"
        Write-Log "Check the setup log for details:" -Level ERROR

        # Find the setup log
        $setupLogs = Get-ChildItem -Path "C:\ConfigMgrSetup*.log" -ErrorAction SilentlyContinue
        foreach ($log in $setupLogs) {
            Write-Log "  $($log.FullName)" -Level ERROR
        }

        # Also check the main SCCM log directory if it exists
        if (Test-Path $logPath) {
            Write-Log "  $logPath" -Level ERROR
        }

        throw "SCCM installation failed"
    }
}

# ============================================================================
# VERIFY INSTALLATION
# ============================================================================

Write-LogSection "Verifying SCCM Installation"

# Check 1: SCCM Services
Write-Log "Checking SCCM services..." -Level INFO

$sccmServices = @(
    @{Name = "SMS_EXECUTIVE"; Description = "SMS Executive"},
    @{Name = "SMS_SITE_COMPONENT_MANAGER"; Description = "Site Component Manager"},
    @{Name = "SMS_NOTIFICATION_SERVER"; Description = "Notification Server"}
)

foreach ($svc in $sccmServices) {
    $service = Get-Service -Name $svc.Name -ErrorAction SilentlyContinue
    if ($service -and $service.Status -eq "Running") {
        Write-Log "$($svc.Description): Running" -Level SUCCESS
    } elseif ($service) {
        Write-Log "$($svc.Description): $($service.Status)" -Level WARN
    } else {
        Write-Log "$($svc.Description): Not found" -Level WARN
    }
}

# Check 2: SCCM WMI namespace
Write-Log "Checking SCCM WMI namespace..." -Level INFO

try {
    $smsNamespace = Get-WmiObject -Namespace "root\SMS\site_$SiteCode" -Class "SMS_Site" -ErrorAction Stop
    Write-Log "SCCM WMI namespace accessible: root\SMS\site_$SiteCode" -Level SUCCESS
}
catch {
    Write-Log "Could not access SCCM WMI namespace." -Level WARN
    Write-Log "Site may still be initializing. Wait a few minutes." -Level INFO
}

# Check 3: SCCM Console
Write-Log "Checking SCCM Console installation..." -Level INFO

$consolePath = "C:\Program Files (x86)\Microsoft Endpoint Manager\AdminConsole\bin\Microsoft.ConfigurationManagement.exe"
if (Test-Path $consolePath) {
    Write-Log "SCCM Console is installed." -Level SUCCESS
} else {
    # Try alternate path
    $consolePathAlt = "C:\Program Files (x86)\Microsoft Configuration Manager\AdminConsole\bin\Microsoft.ConfigurationManagement.exe"
    if (Test-Path $consolePathAlt) {
        Write-Log "SCCM Console is installed." -Level SUCCESS
    } else {
        Write-Log "SCCM Console not found in expected location." -Level WARN
    }
}

# Check 4: Database
Write-Log "Checking SCCM database..." -Level INFO

try {
    $database = Invoke-Sqlcmd -Query "SELECT name FROM sys.databases WHERE name = 'CM_$SiteCode'" -ServerInstance $SQLServerName
    if ($database) {
        Write-Log "SCCM database exists: CM_$SiteCode" -Level SUCCESS
    } else {
        Write-Log "SCCM database not found." -Level WARN
    }
}
catch {
    Write-Log "Could not verify SCCM database." -Level WARN
}

# Check 5: Management Point
Write-Log "Checking Management Point..." -Level INFO

try {
    $mp = Get-WmiObject -Namespace "root\SMS\site_$SiteCode" -Class "SMS_SCI_SysResUse" `
        -Filter "RoleName='SMS Management Point'" -ErrorAction Stop
    if ($mp) {
        Write-Log "Management Point is configured." -Level SUCCESS
    }
}
catch {
    Write-Log "Could not verify Management Point. May still be initializing." -Level INFO
}

# Check 6: Distribution Point
Write-Log "Checking Distribution Point..." -Level INFO

try {
    $dp = Get-WmiObject -Namespace "root\SMS\site_$SiteCode" -Class "SMS_SCI_SysResUse" `
        -Filter "RoleName='SMS Distribution Point'" -ErrorAction Stop
    if ($dp) {
        Write-Log "Distribution Point is configured." -Level SUCCESS
    }
}
catch {
    Write-Log "Could not verify Distribution Point. May still be initializing." -Level INFO
}

# ============================================================================
# SUMMARY
# ============================================================================

Write-LogSection "SCCM Installation Complete"

Write-Log "SCCM Primary Site has been installed!" -Level SUCCESS
Write-Log "" -Level INFO
Write-Log "Site Information:" -Level INFO
Write-Log "  Site Code: $SiteCode" -Level INFO
Write-Log "  Site Name: $SiteName" -Level INFO
Write-Log "  Site Server: $env:COMPUTERNAME" -Level INFO
Write-Log "  SQL Server: $SQLServerName" -Level INFO
Write-Log "  Database: CM_$SiteCode" -Level INFO
Write-Log "" -Level INFO
Write-Log "Console Location:" -Level INFO
Write-Log "  $consolePath" -Level INFO
Write-Log "" -Level INFO
Write-Log "Important Logs:" -Level INFO
Write-Log "  Setup Log: C:\ConfigMgrSetup.log" -Level INFO
Write-Log "  Site Logs: $InstallDir\Logs\" -Level INFO
Write-Log "" -Level INFO
Write-Log "Next Steps:" -Level INFO
Write-Log "  1. Launch the SCCM Console" -Level INFO
Write-Log "  2. Run Configure-SCCM.ps1 to set up boundaries and discovery" -Level INFO
Write-Log "  3. Configure client settings" -Level INFO
Write-Log "  4. Deploy SCCM client to workstations" -Level INFO
Write-Log "" -Level INFO
Write-Log "NOTE: SCCM site initialization continues in the background." -Level WARN
Write-Log "Wait 10-15 minutes before expecting all features to work." -Level WARN

# Clean up config file (contains no sensitive data but good practice)
Remove-Item -Path $configPath -Force -ErrorAction SilentlyContinue

Complete-Logging
