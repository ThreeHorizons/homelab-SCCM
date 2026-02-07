<#
.SYNOPSIS
    Installs Microsoft SQL Server for SCCM on SCCM01.

.DESCRIPTION
    This script performs an unattended SQL Server installation configured
    specifically for System Center Configuration Manager (SCCM).

    ============================================================================
    TECHNOLOGY EXPLANATION: SQL Server for SCCM
    ============================================================================

    SQL Server is a relational database management system (RDBMS) that SCCM
    uses to store all configuration, inventory, and operational data.

    WHY SQL SERVER IS REQUIRED:
    - SCCM stores everything in SQL databases (site configuration, hardware
      inventory, software inventory, deployments, client data, etc.)
    - A typical SCCM site database can grow to 50GB-500GB+ depending on
      the number of clients and features enabled
    - SQL Server provides the performance, reliability, and query capabilities
      needed for SCCM's complex data operations

    CRITICAL SCCM SQL REQUIREMENTS:

    1. COLLATION: Must be SQL_Latin1_General_CP1_CI_AS
       - This is NON-NEGOTIABLE for SCCM
       - If wrong, SCCM installation will fail
       - "CI" = Case Insensitive, "AS" = Accent Sensitive
       - You CANNOT change collation after installation without reinstalling

    2. INSTANCE TYPE: Default instance recommended (MSSQLSERVER)
       - SCCM supports named instances but default is simpler
       - Named instances require specifying port numbers

    3. SERVICE ACCOUNTS: Domain accounts recommended
       - SQL Server service: LAB\SQL_Service
       - SQL Agent service: LAB\SQL_Service
       - These were created in the DC01 Create-ServiceAccounts.ps1 script

    4. AUTHENTICATION: Windows Authentication mode
       - Mixed mode works but Windows-only is more secure
       - SCCM uses Windows authentication exclusively

    5. MEMORY: Configure max memory to leave RAM for OS
       - On a 4GB server: Set max to 2GB (leave 2GB for Windows)
       - On a 8GB server: Set max to 6GB
       - Prevents SQL from starving the OS of memory

    6. FEATURES REQUIRED:
       - Database Engine Services (core)
       - SQL Server Replication (for SCCM replication)
       - Full-Text Search (optional, for content search)
       - Reporting Services (required for SCCM reports)

    INSTALLATION METHODS:

    This script supports two installation modes:

    1. CONFIGURATION FILE MODE (preferred):
       - Creates a ConfigurationFile.ini with all settings
       - Runs setup.exe /ConfigurationFile=<path>
       - Most reliable for automation

    2. COMMAND-LINE MODE:
       - Passes all parameters directly to setup.exe
       - Long command line but works well

    SQL SERVER EDITIONS:
    - Developer Edition: Free, full features (perfect for labs)
    - Standard Edition: Licensed, limited features
    - Enterprise Edition: Licensed, all features
    - Express Edition: Free but limited (max 10GB DB, 1 CPU)

    For this lab, we'll use Developer or Evaluation edition.

    ============================================================================

.PARAMETER SQLISOPath
    Path to the SQL Server ISO file or extracted setup directory.

.PARAMETER SQLServiceAccount
    Domain account for SQL Server services.
    Default: LAB\SQL_Service

.PARAMETER SQLServicePassword
    Password for the SQL service account.

.PARAMETER SQLAdmins
    Array of users/groups to add as SQL Server administrators.
    Default: BUILTIN\Administrators

.PARAMETER MaxMemoryMB
    Maximum memory SQL Server should use in MB.
    Default: 2048 (2GB)

.PARAMETER InstallPath
    Installation directory for SQL Server.
    Default: C:\Program Files\Microsoft SQL Server

.EXAMPLE
    .\Install-SQLServer.ps1 -SQLISOPath "D:\" -SQLServicePassword "P@ssw0rd123!"

.NOTES
    Author: Homelab-SCCM Project
    Requires: Windows Server 2019/2022, .NET Framework 3.5
    Run on: SCCM01 (must be domain-joined first)
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$SQLISOPath,

    [Parameter(Mandatory = $false)]
    [string]$SQLServiceAccount = "LAB\SQL_Service",

    [Parameter(Mandatory = $true)]
    [SecureString]$SQLServicePassword,

    [Parameter(Mandatory = $false)]
    [string[]]$SQLAdmins = @("BUILTIN\Administrators"),

    [Parameter(Mandatory = $false)]
    [int]$MaxMemoryMB = 2048,

    [Parameter(Mandatory = $false)]
    [string]$InstallPath = "C:\Program Files\Microsoft SQL Server"
)

# ============================================================================
# SCRIPT INITIALIZATION
# ============================================================================

# Import our logging module for consistent output
# The $PSScriptRoot variable contains the directory where this script lives
$modulePath = Join-Path (Split-Path $PSScriptRoot -Parent) "modules"

# SYNTAX EXPLANATION: Import-Module
# -Name: Path to the module file
# -Force: Reimport even if already loaded (ensures latest version)
# -ErrorAction Stop: Terminate script if module can't be loaded
Import-Module -Name (Join-Path $modulePath "Logger.psm1") -Force -ErrorAction Stop
Import-Module -Name (Join-Path $modulePath "Validator.psm1") -Force -ErrorAction Stop

# Initialize logging to file and console
# Logs go to C:\Logs\Lab\Install-SQLServer_<timestamp>.log
Initialize-Logging -LogName "Install-SQLServer"

Write-LogSection "SQL Server Installation for SCCM"

# ============================================================================
# PRE-REQUISITE CHECKS
# ============================================================================

Write-Log "Performing pre-installation checks..." -Level INFO

# Check 1: Verify we're on a domain-joined machine
# SCCM requires the SQL Server to be domain-joined for proper authentication
if (-not (Test-DomainJoined)) {
    Write-LogError "This computer is not joined to a domain. SQL Server for SCCM requires domain membership."
    Write-Log "Run Join-LabDomain.ps1 first, then restart and run this script again." -Level WARN
    throw "Domain membership required"
}

Write-Log "Domain membership verified: $((Get-WmiObject Win32_ComputerSystem).Domain)" -Level SUCCESS

# Check 2: Verify SQL Server isn't already installed
# Test-SQLServerInstalled checks for the MSSQLSERVER service
if (Test-SQLServerInstalled) {
    Write-Log "SQL Server is already installed on this system." -Level WARN

    # Verify collation is correct even if already installed
    # SYNTAX EXPLANATION: Invoke-Sqlcmd
    # This cmdlet runs T-SQL queries against SQL Server
    # SERVERPROPERTY('Collation') returns the server's collation setting
    try {
        $collation = Invoke-Sqlcmd -Query "SELECT SERVERPROPERTY('Collation') AS Collation" -ServerInstance "localhost" -ErrorAction Stop
        if ($collation.Collation -eq "SQL_Latin1_General_CP1_CI_AS") {
            Write-Log "SQL Server collation is correct: $($collation.Collation)" -Level SUCCESS
            Write-Log "Skipping installation - SQL Server already properly configured." -Level INFO
            Complete-Logging
            return
        } else {
            Write-LogError "SQL Server collation is INCORRECT: $($collation.Collation)"
            Write-Log "SCCM requires SQL_Latin1_General_CP1_CI_AS collation." -Level ERROR
            Write-Log "You must uninstall SQL Server and reinstall with correct collation." -Level ERROR
            throw "Incorrect SQL Server collation"
        }
    }
    catch {
        Write-Log "Could not verify collation. SQL Server may need configuration." -Level WARN
    }
}

# Check 3: Verify .NET Framework 3.5 is installed
# SQL Server requires .NET 3.5 for setup and certain features
# SYNTAX EXPLANATION: Get-WindowsFeature
# Returns information about Windows Server features
# NET-Framework-Core is the .NET 3.5 feature
$netFx35 = Get-WindowsFeature -Name NET-Framework-Core
if ($netFx35.InstallState -ne "Installed") {
    Write-Log ".NET Framework 3.5 is not installed. Installing now..." -Level WARN

    # SYNTAX EXPLANATION: Install-WindowsFeature
    # -Name: Feature to install
    # -Source: Optional source for feature files (Windows Server ISO)
    # If no source specified, Windows Update is used
    Install-WindowsFeature -Name NET-Framework-Core -ErrorAction Stop
    Write-Log ".NET Framework 3.5 installed successfully." -Level SUCCESS
} else {
    Write-Log ".NET Framework 3.5 is already installed." -Level SUCCESS
}

# Check 4: Verify SQL Server setup files exist
# Look for setup.exe in the specified path
$setupExe = Join-Path $SQLISOPath "setup.exe"
if (-not (Test-Path $setupExe)) {
    Write-LogError "SQL Server setup.exe not found at: $setupExe"
    Write-Log "Please verify SQLISOPath points to the SQL Server installation media." -Level ERROR
    throw "Setup.exe not found"
}

Write-Log "SQL Server setup found at: $setupExe" -Level SUCCESS

# ============================================================================
# CONFIGURATION FILE GENERATION
# ============================================================================

Write-LogSection "Creating SQL Server Configuration File"

# Convert SecureString password to plain text for the config file
# SYNTAX EXPLANATION: BSTR (Binary String) conversion
# This is the secure way to convert SecureString to plain text in PowerShell
# We need plain text for the config file (SQL setup requirement)
$BSTR = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($SQLServicePassword)
$plainPassword = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($BSTR)
# Clear the BSTR from memory immediately after use for security
[System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($BSTR)

# Format SQL Admins for configuration file
# Multiple admins need to be space-separated and quoted
$sqlAdminsFormatted = ($SQLAdmins | ForEach-Object { "`"$_`"" }) -join " "

# Configuration file content
# This is an INI-style file that SQL Server setup reads
# Each line is either [Section] or Key=Value
$configContent = @"

; ============================================================================
; SQL SERVER CONFIGURATION FILE FOR SCCM
; ============================================================================
; Generated by Install-SQLServer.ps1
; Date: $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")
;
; This file contains all settings for unattended SQL Server installation.
; Settings are specifically configured for SCCM compatibility.
; ============================================================================

[OPTIONS]

; ACTION: What operation to perform
; Install = New installation
; Other options: Upgrade, Repair, Uninstall, etc.
ACTION="Install"

; FEATURES: Which SQL Server components to install
; SQLENGINE = Database Engine (core SQL Server)
; REPLICATION = SQL Server Replication (used by SCCM for data replication)
; FULLTEXT = Full-Text Search (optional, for content searching)
; RS = Reporting Services (required for SCCM reports)
; SSMS is no longer bundled with SQL Server 2016+, install separately
FEATURES=SQLENGINE,REPLICATION,FULLTEXT,RS

; INSTANCENAME: Name of the SQL instance
; MSSQLSERVER = Default instance (connect as "SERVERNAME")
; Named instance would be like "SCCM" (connect as "SERVERNAME\SCCM")
; Default instance is simpler and recommended for SCCM
INSTANCENAME="MSSQLSERVER"

; INSTANCEID: Identifier for instance directories and registry
; Usually matches INSTANCENAME
INSTANCEID="MSSQLSERVER"

; INSTANCEDIR: Installation directory for instance files
INSTANCEDIR="$InstallPath"

; QUIET: Suppress UI during installation
; True = No UI, runs completely silently
QUIET="True"

; QUIETSIMPLE: Similar to QUIET but shows progress
; We use QUIET for full automation
QUIETSIMPLE="False"

; IACCEPTSQLSERVERLICENSETERMS: Accept the SQL Server license
; Must be True for unattended installation
IACCEPTSQLSERVERLICENSETERMS="True"

; INDICATEPROGRESS: Show installation progress
; Useful for monitoring in logs
INDICATEPROGRESS="True"

; ============================================================================
; COLLATION SETTINGS - CRITICAL FOR SCCM
; ============================================================================

; SQLCOLLATION: The collation for the SQL Server instance
; SQL_Latin1_General_CP1_CI_AS is REQUIRED for SCCM
;
; Breaking down the collation name:
; - SQL_Latin1 = SQL Server Latin character set
; - General = General sorting rules
; - CP1 = Code Page 1252 (Windows Western European)
; - CI = Case Insensitive (A = a)
; - AS = Accent Sensitive (a != à)
;
; If this is wrong, SCCM WILL NOT INSTALL!
SQLCOLLATION="SQL_Latin1_General_CP1_CI_AS"

; ============================================================================
; SERVICE ACCOUNTS
; ============================================================================

; SQLSVCACCOUNT: Account to run the SQL Server Database Engine service
; Using a domain account allows proper Kerberos authentication
SQLSVCACCOUNT="$SQLServiceAccount"

; SQLSVCPASSWORD: Password for the SQL Server service account
SQLSVCPASSWORD="$plainPassword"

; SQLSVCSTARTUPTYPE: When should the SQL Server service start?
; Automatic = Start with Windows (what we want)
SQLSVCSTARTUPTYPE="Automatic"

; AGTSVCACCOUNT: Account for SQL Server Agent service
; Agent runs scheduled jobs, maintenance tasks, etc.
; Using same account as SQL Server for simplicity
AGTSVCACCOUNT="$SQLServiceAccount"

; AGTSVCPASSWORD: Password for SQL Agent account
AGTSVCPASSWORD="$plainPassword"

; AGTSVCSTARTUPTYPE: SQL Agent startup type
; Automatic = Start with Windows
AGTSVCSTARTUPTYPE="Automatic"

; RSSVCACCOUNT: Account for Reporting Services
; Using same account for simplicity in lab environment
RSSVCACCOUNT="$SQLServiceAccount"

; RSSVCPASSWORD: Password for Reporting Services account
RSSVCPASSWORD="$plainPassword"

; RSSVCSTARTUPTYPE: Reporting Services startup type
RSSVCSTARTUPTYPE="Automatic"

; ============================================================================
; SECURITY CONFIGURATION
; ============================================================================

; SECURITYMODE: Authentication mode
; SQL = SQL Server and Windows Authentication (Mixed Mode)
; If not specified, Windows Authentication only (more secure)
; SCCM uses Windows Authentication so we don't need Mixed Mode
; Commented out = Windows Authentication only
; SECURITYMODE="SQL"

; SQLSYSADMINACCOUNTS: Users/groups with sysadmin privileges
; These accounts will have full control over SQL Server
; Including local Administrators ensures the SCCM setup can work
SQLSYSADMINACCOUNTS=$sqlAdminsFormatted

; ============================================================================
; FILE LOCATIONS
; ============================================================================

; SQLUSERDBDIR: Default directory for user database files (.mdf)
SQLUSERDBDIR="$InstallPath\MSSQL\Data"

; SQLUSERDBLOGDIR: Default directory for user database logs (.ldf)
SQLUSERDBLOGDIR="$InstallPath\MSSQL\Data"

; SQLTEMPDBDIR: Directory for TempDB data files
; TempDB is a system database that SQL recreates on every startup
; Putting it on fast storage improves performance
SQLTEMPDBDIR="$InstallPath\MSSQL\Data"

; SQLTEMPDBLOGDIR: Directory for TempDB log files
SQLTEMPDBLOGDIR="$InstallPath\MSSQL\Data"

; SQLBACKUPDIR: Default directory for database backups
SQLBACKUPDIR="$InstallPath\MSSQL\Backup"

; ============================================================================
; NETWORKING
; ============================================================================

; TCPENABLED: Enable TCP/IP protocol
; Required for remote connections to SQL Server
; 1 = Enabled, 0 = Disabled
TCPENABLED="1"

; NPENABLED: Enable Named Pipes protocol
; Optional legacy protocol, TCP/IP is preferred
; 0 = Disabled
NPENABLED="0"

; BROWSERSVCSTARTUPTYPE: SQL Server Browser service
; Browser helps clients find SQL instances
; For default instance, not strictly required
; Automatic = Start with Windows
BROWSERSVCSTARTUPTYPE="Automatic"

; ============================================================================
; REPORTING SERVICES CONFIGURATION
; ============================================================================

; RSINSTALLMODE: Reporting Services installation mode
; DefaultNativeMode = Standard installation with web portal
; FilesOnlyMode = Just install files, configure later
RSINSTALLMODE="DefaultNativeMode"

; ============================================================================
; UPDATE SETTINGS
; ============================================================================

; UPDATEENABLED: Check for SQL Server updates during installation
; True = Download and install updates (recommended)
; For lab environments, False is acceptable to speed installation
UPDATEENABLED="False"

; ============================================================================
; TELEMETRY
; ============================================================================

; SQLTELSVCSTARTUPTYPE: SQL Server Telemetry service
; Disabled for lab environments
SQLTELSVCSTARTUPTYPE="Disabled"

"@

# Clear the plain text password from memory
# SYNTAX EXPLANATION: Setting to $null helps garbage collection
$plainPassword = $null

# Write the configuration file
$configPath = "C:\SQLServerConfig.ini"
Write-Log "Writing configuration file to: $configPath" -Level INFO

# SYNTAX EXPLANATION: Set-Content
# Writes text to a file, replacing any existing content
# -Path: File to write
# -Value: Content to write
# -Encoding: Character encoding (ASCII is safest for INI files)
Set-Content -Path $configPath -Value $configContent -Encoding ASCII

Write-Log "Configuration file created successfully." -Level SUCCESS

# ============================================================================
# SQL SERVER INSTALLATION
# ============================================================================

Write-LogSection "Installing SQL Server"

Write-Log "Starting SQL Server installation (this may take 15-30 minutes)..." -Level INFO
Write-Log "Setup command: $setupExe /ConfigurationFile=$configPath" -Level DEBUG

# SYNTAX EXPLANATION: Start-Process
# Launches an external program and optionally waits for it
# -FilePath: Program to run
# -ArgumentList: Command line arguments
# -Wait: Wait for the process to complete before continuing
# -NoNewWindow: Don't open a new window (run in background)
# -PassThru: Return a process object so we can check exit code
$process = Start-Process -FilePath $setupExe `
    -ArgumentList "/ConfigurationFile=`"$configPath`"" `
    -Wait -NoNewWindow -PassThru

# Check the exit code
# SQL Server setup exit codes:
# 0 = Success
# 3010 = Success, reboot required
# Other = Various errors (see SQL Server documentation)
$exitCode = $process.ExitCode

Write-Log "SQL Server setup completed with exit code: $exitCode" -Level INFO

if ($exitCode -eq 0) {
    Write-Log "SQL Server installed successfully!" -Level SUCCESS
} elseif ($exitCode -eq 3010) {
    Write-Log "SQL Server installed successfully. A reboot is required." -Level WARN
} else {
    Write-LogError "SQL Server installation failed with exit code: $exitCode"
    Write-Log "Check the SQL Server setup log for details:" -Level ERROR
    Write-Log "C:\Program Files\Microsoft SQL Server\*\Setup Bootstrap\Log\Summary.txt" -Level ERROR

    # Try to display the summary log if it exists
    $summaryLogs = Get-ChildItem -Path "C:\Program Files\Microsoft SQL Server" -Recurse -Filter "Summary.txt" -ErrorAction SilentlyContinue
    if ($summaryLogs) {
        Write-Log "`nSetup Summary:" -Level INFO
        Get-Content $summaryLogs[0].FullName | Select-Object -Last 50 | ForEach-Object {
            Write-Log $_ -Level DEBUG
        }
    }

    throw "SQL Server installation failed"
}

# Clean up configuration file (contains password)
Write-Log "Removing configuration file (contains sensitive data)..." -Level INFO
Remove-Item -Path $configPath -Force -ErrorAction SilentlyContinue

# ============================================================================
# POST-INSTALLATION CONFIGURATION
# ============================================================================

Write-LogSection "Configuring SQL Server Post-Installation"

# Wait for SQL Server service to be available
Write-Log "Waiting for SQL Server service to start..." -Level INFO
$maxWaitSeconds = 120
$waited = 0

# SYNTAX EXPLANATION: Get-Service
# Returns information about Windows services
# We wait for the MSSQLSERVER service to be in Running state
while ($waited -lt $maxWaitSeconds) {
    $sqlService = Get-Service -Name "MSSQLSERVER" -ErrorAction SilentlyContinue
    if ($sqlService -and $sqlService.Status -eq "Running") {
        Write-Log "SQL Server service is running." -Level SUCCESS
        break
    }
    Start-Sleep -Seconds 5
    $waited += 5
    Write-Log "Waiting for SQL Server service... ($waited seconds)" -Level DEBUG
}

if ($waited -ge $maxWaitSeconds) {
    Write-LogError "SQL Server service did not start within $maxWaitSeconds seconds"
    throw "SQL Server service not running"
}

# Configure SQL Server memory
# This is CRITICAL to prevent SQL Server from consuming all system RAM
Write-Log "Configuring SQL Server maximum memory to $MaxMemoryMB MB..." -Level INFO

# SYNTAX EXPLANATION: Invoke-Sqlcmd
# Runs T-SQL commands against SQL Server
# -Query: The SQL statement to execute
# -ServerInstance: Which SQL Server to connect to ("." means localhost)

# sp_configure: System stored procedure to change SQL Server configuration
# 'show advanced options': Must be enabled to change memory settings
# 'max server memory': Maximum RAM SQL Server will use (in MB)
# RECONFIGURE: Apply the configuration change immediately

try {
    # Enable advanced options (required to change memory settings)
    Invoke-Sqlcmd -Query "EXEC sp_configure 'show advanced options', 1; RECONFIGURE;" -ServerInstance "."

    # Set maximum memory
    Invoke-Sqlcmd -Query "EXEC sp_configure 'max server memory', $MaxMemoryMB; RECONFIGURE;" -ServerInstance "."

    Write-Log "SQL Server memory limit set to $MaxMemoryMB MB." -Level SUCCESS
}
catch {
    Write-Log "Could not configure SQL memory. Error: $_" -Level WARN
    Write-Log "You may need to configure this manually after installation." -Level WARN
}

# Verify collation
Write-Log "Verifying SQL Server collation..." -Level INFO

try {
    $collation = Invoke-Sqlcmd -Query "SELECT SERVERPROPERTY('Collation') AS Collation" -ServerInstance "."

    if ($collation.Collation -eq "SQL_Latin1_General_CP1_CI_AS") {
        Write-Log "SQL Server collation verified: $($collation.Collation)" -Level SUCCESS
    } else {
        Write-LogError "CRITICAL: SQL Server collation is incorrect: $($collation.Collation)"
        Write-Log "SCCM requires SQL_Latin1_General_CP1_CI_AS" -Level ERROR
        Write-Log "You must reinstall SQL Server with correct collation!" -Level ERROR
    }
}
catch {
    Write-Log "Could not verify collation. Error: $_" -Level WARN
}

# Verify TCP/IP is enabled
Write-Log "Verifying SQL Server network protocols..." -Level INFO

# SYNTAX EXPLANATION: WMI (Windows Management Instrumentation)
# WMI provides a way to query and manage Windows components
# SQL Server exposes its configuration through WMI
# ComputerManagement15 = SQL Server 2019, ComputerManagement16 = SQL Server 2022

try {
    # Try SQL Server 2022 namespace first, then 2019
    $wmiNamespaces = @(
        "root\Microsoft\SqlServer\ComputerManagement16",
        "root\Microsoft\SqlServer\ComputerManagement15",
        "root\Microsoft\SqlServer\ComputerManagement14"
    )

    foreach ($namespace in $wmiNamespaces) {
        try {
            $tcpProtocol = Get-WmiObject -Namespace $namespace -Class "ServerNetworkProtocol" `
                -Filter "ProtocolName='Tcp' AND InstanceName='MSSQLSERVER'" -ErrorAction Stop

            if ($tcpProtocol.Enabled) {
                Write-Log "TCP/IP protocol is enabled for SQL Server." -Level SUCCESS
            } else {
                Write-Log "Enabling TCP/IP protocol..." -Level WARN
                $tcpProtocol.SetEnable() | Out-Null
                Write-Log "TCP/IP enabled. SQL Server service restart may be required." -Level WARN
            }
            break
        }
        catch {
            continue
        }
    }
}
catch {
    Write-Log "Could not verify network protocols. Error: $_" -Level WARN
}

# ============================================================================
# CONFIGURE FIREWALL
# ============================================================================

Write-LogSection "Configuring Windows Firewall for SQL Server"

# SQL Server uses port 1433 by default for TCP connections
# We need to allow this through the firewall for remote connections

# SYNTAX EXPLANATION: New-NetFirewallRule
# Creates a Windows Firewall rule
# -DisplayName: Name shown in Windows Firewall console
# -Direction: Inbound (incoming) or Outbound (outgoing) traffic
# -LocalPort: Port number(s) to allow
# -Protocol: TCP or UDP
# -Action: Allow or Block
# -Profile: Domain, Private, Public, or Any
# -Enabled: True/False

# Check if rule already exists
$existingRule = Get-NetFirewallRule -DisplayName "SQL Server (TCP 1433)" -ErrorAction SilentlyContinue

if (-not $existingRule) {
    Write-Log "Creating firewall rule for SQL Server port 1433..." -Level INFO

    New-NetFirewallRule -DisplayName "SQL Server (TCP 1433)" `
        -Direction Inbound `
        -LocalPort 1433 `
        -Protocol TCP `
        -Action Allow `
        -Profile Domain,Private `
        -Enabled True `
        -Description "Allow SQL Server connections on port 1433"

    Write-Log "Firewall rule created for port 1433." -Level SUCCESS
} else {
    Write-Log "Firewall rule for SQL Server already exists." -Level INFO
}

# SQL Server Browser uses UDP 1434
$existingBrowserRule = Get-NetFirewallRule -DisplayName "SQL Server Browser (UDP 1434)" -ErrorAction SilentlyContinue

if (-not $existingBrowserRule) {
    Write-Log "Creating firewall rule for SQL Server Browser..." -Level INFO

    New-NetFirewallRule -DisplayName "SQL Server Browser (UDP 1434)" `
        -Direction Inbound `
        -LocalPort 1434 `
        -Protocol UDP `
        -Action Allow `
        -Profile Domain,Private `
        -Enabled True `
        -Description "Allow SQL Server Browser discovery"

    Write-Log "Firewall rule created for SQL Server Browser." -Level SUCCESS
} else {
    Write-Log "Firewall rule for SQL Server Browser already exists." -Level INFO
}

# ============================================================================
# VERIFICATION
# ============================================================================

Write-LogSection "SQL Server Installation Verification"

# Test 1: Service status
Write-Log "Checking SQL Server services..." -Level INFO

$services = @(
    @{Name = "MSSQLSERVER"; Description = "SQL Server Database Engine"},
    @{Name = "SQLSERVERAGENT"; Description = "SQL Server Agent"},
    @{Name = "ReportServer"; Description = "SQL Server Reporting Services"}
)

foreach ($svc in $services) {
    $service = Get-Service -Name $svc.Name -ErrorAction SilentlyContinue
    if ($service) {
        if ($service.Status -eq "Running") {
            Write-Log "$($svc.Description) ($($svc.Name)): Running" -Level SUCCESS
        } else {
            Write-Log "$($svc.Description) ($($svc.Name)): $($service.Status)" -Level WARN
        }
    } else {
        Write-Log "$($svc.Description) ($($svc.Name)): Not installed" -Level WARN
    }
}

# Test 2: Version and edition
Write-Log "Checking SQL Server version..." -Level INFO

try {
    $versionInfo = Invoke-Sqlcmd -Query @"
SELECT
    SERVERPROPERTY('ProductVersion') AS Version,
    SERVERPROPERTY('Edition') AS Edition,
    SERVERPROPERTY('ProductLevel') AS ProductLevel,
    SERVERPROPERTY('Collation') AS Collation
"@ -ServerInstance "."

    Write-Log "SQL Server Version: $($versionInfo.Version)" -Level SUCCESS
    Write-Log "SQL Server Edition: $($versionInfo.Edition)" -Level SUCCESS
    Write-Log "Product Level: $($versionInfo.ProductLevel)" -Level INFO
    Write-Log "Collation: $($versionInfo.Collation)" -Level INFO
}
catch {
    Write-Log "Could not retrieve SQL Server version information. Error: $_" -Level WARN
}

# Test 3: Create a test database to verify functionality
Write-Log "Testing database creation..." -Level INFO

try {
    # Create a test database
    Invoke-Sqlcmd -Query "IF NOT EXISTS (SELECT name FROM sys.databases WHERE name = 'TestDB') CREATE DATABASE TestDB" -ServerInstance "."

    # Verify it was created
    $testDb = Invoke-Sqlcmd -Query "SELECT name FROM sys.databases WHERE name = 'TestDB'" -ServerInstance "."

    if ($testDb) {
        Write-Log "Test database created successfully." -Level SUCCESS

        # Clean up test database
        Invoke-Sqlcmd -Query "DROP DATABASE TestDB" -ServerInstance "."
        Write-Log "Test database cleaned up." -Level DEBUG
    }
}
catch {
    Write-Log "Database creation test failed. Error: $_" -Level WARN
}

# ============================================================================
# SUMMARY
# ============================================================================

Write-LogSection "SQL Server Installation Complete"

Write-Log "SQL Server has been installed and configured for SCCM." -Level SUCCESS
Write-Log "" -Level INFO
Write-Log "Installation Summary:" -Level INFO
Write-Log "  Instance Name: MSSQLSERVER (default instance)" -Level INFO
Write-Log "  Collation: SQL_Latin1_General_CP1_CI_AS" -Level INFO
Write-Log "  Max Memory: $MaxMemoryMB MB" -Level INFO
Write-Log "  Service Account: $SQLServiceAccount" -Level INFO
Write-Log "  TCP Port: 1433" -Level INFO
Write-Log "" -Level INFO
Write-Log "Features Installed:" -Level INFO
Write-Log "  - Database Engine Services" -Level INFO
Write-Log "  - SQL Server Replication" -Level INFO
Write-Log "  - Full-Text Search" -Level INFO
Write-Log "  - Reporting Services" -Level INFO
Write-Log "" -Level INFO
Write-Log "Next Steps:" -Level INFO
Write-Log "  1. Install SQL Server Management Studio (SSMS)" -Level INFO
Write-Log "  2. Run SCCM prerequisite installation script" -Level INFO
Write-Log "  3. Run SCCM installation script" -Level INFO

if ($exitCode -eq 3010) {
    Write-Log "" -Level INFO
    Write-Log "NOTE: A system reboot is required to complete installation." -Level WARN
}

Complete-Logging
