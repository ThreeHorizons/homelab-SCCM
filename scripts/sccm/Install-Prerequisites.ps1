<#
.SYNOPSIS
    Installs all prerequisites required for SCCM Primary Site installation.

.DESCRIPTION
    This script prepares the SCCM01 server with all required Windows features,
    roles, and components necessary before SCCM can be installed.

    ============================================================================
    TECHNOLOGY EXPLANATION: SCCM Prerequisites
    ============================================================================

    SCCM (System Center Configuration Manager) is a complex enterprise application
    that requires many Windows features and components to function. This script
    installs all of them in the correct order.

    WINDOWS FEATURES REQUIRED:

    1. .NET Framework 3.5 (NET-Framework-Core)
       - Legacy .NET runtime required by some SCCM components
       - Must be installed BEFORE SQL Server
       - May require Windows Server installation media as source

    2. .NET Framework 4.8+ (NET-Framework-45-Features)
       - Modern .NET runtime for SCCM application code
       - Usually already present on Windows Server 2019/2022

    3. BITS Server Extensions (BITS-IIS-Ext)
       - Background Intelligent Transfer Service
       - Used for client content downloads (packages, updates, etc.)
       - Clients use BITS to download content from Distribution Points

    4. Remote Differential Compression (RDC)
       - Optimizes data transfer by sending only changed portions
       - Used for replication between sites
       - Reduces bandwidth for large file transfers

    5. IIS (Web-Server)
       - Internet Information Services web server
       - Hosts Management Point, Distribution Point, and other SCCM web services
       - Specific IIS features required for different SCCM roles

    REQUIRED IIS ROLE SERVICES:

    Management Point requires:
    - Web-Default-Doc (Default Document)
    - Web-Dir-Browsing (Directory Browsing)
    - Web-Http-Errors (HTTP Errors)
    - Web-Static-Content (Static Content)
    - Web-Http-Logging (HTTP Logging)
    - Web-Stat-Compression (Static Content Compression)
    - Web-Filtering (Request Filtering)
    - Web-Windows-Auth (Windows Authentication)
    - Web-Metabase (IIS 6 Metabase Compatibility)
    - Web-WMI (IIS 6 WMI Compatibility)
    - Web-ISAPI-Ext (ISAPI Extensions)
    - Web-Asp-Net (ASP.NET - legacy)
    - Web-Asp-Net45 (ASP.NET 4.5+)
    - Web-Net-Ext45 (.NET Extensibility 4.5)

    Distribution Point adds:
    - Web-WebSockets (WebSocket Protocol)
    - All MP requirements

    ADDITIONAL REQUIRED COMPONENTS:

    1. Windows ADK (Assessment and Deployment Kit)
       - Required for OS deployment features
       - Contains boot image tools and deployment utilities
       - Components needed: Deployment Tools, User State Migration Tool

    2. Windows PE Add-on
       - Extends ADK with Windows Preinstallation Environment
       - Required for PXE boot and task sequences
       - Must match ADK version

    3. ODBC Driver for SQL Server
       - Newer SCCM versions require ODBC Driver 18.4.1+
       - Used for SQL Server connectivity

    4. Microsoft Visual C++ Redistributables
       - Runtime libraries required by various components
       - Usually multiple versions needed (2012, 2013, 2015-2022)

    ============================================================================

.PARAMETER SkipADK
    Skip Windows ADK installation (if already installed).

.PARAMETER ADKPath
    Path to Windows ADK installer (adksetup.exe).
    If not specified, will attempt to download.

.PARAMETER WinPEPath
    Path to Windows PE add-on installer (adkwinpesetup.exe).
    If not specified, will attempt to download.

.PARAMETER DownloadPath
    Directory to download installers to.
    Default: C:\Temp\SCCMPrereqs

.EXAMPLE
    .\Install-Prerequisites.ps1

.EXAMPLE
    .\Install-Prerequisites.ps1 -ADKPath "D:\ADK\adksetup.exe" -WinPEPath "D:\ADK\adkwinpesetup.exe"

.NOTES
    Author: Homelab-SCCM Project
    Requires: Windows Server 2019/2022, Administrator rights
    Run on: SCCM01 (after SQL Server installation)
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [switch]$SkipADK,

    [Parameter(Mandatory = $false)]
    [string]$ADKPath,

    [Parameter(Mandatory = $false)]
    [string]$WinPEPath,

    [Parameter(Mandatory = $false)]
    [string]$DownloadPath = "C:\Temp\SCCMPrereqs"
)

# ============================================================================
# SCRIPT INITIALIZATION
# ============================================================================

$modulePath = Join-Path (Split-Path $PSScriptRoot -Parent) "modules"
Import-Module -Name (Join-Path $modulePath "Logger.psm1") -Force -ErrorAction Stop
Import-Module -Name (Join-Path $modulePath "Validator.psm1") -Force -ErrorAction Stop

Initialize-Logging -LogDirectory "Install-SCCMPrereqs"

Write-LogSection "SCCM Prerequisites Installation"

# Create download directory if needed
if (-not (Test-Path $DownloadPath)) {
    Write-Log "Creating download directory: $DownloadPath" -Level INFO
    New-Item -Path $DownloadPath -ItemType Directory -Force | Out-Null
}

# ============================================================================
# WINDOWS FEATURES INSTALLATION
# ============================================================================

Write-LogSection "Installing Required Windows Features"

# Define all required Windows features in a structured array
# Each entry has:
#   Name: Feature name for Install-WindowsFeature
#   Description: Human-readable description
#   Required: Whether it's mandatory (vs. recommended)

$windowsFeatures = @(
    # .NET Framework
    @{Name = "NET-Framework-Core"; Description = ".NET Framework 3.5"; Required = $true},
    @{Name = "NET-Framework-45-Features"; Description = ".NET Framework 4.5+ Features"; Required = $true},
    @{Name = "NET-Framework-45-Core"; Description = ".NET Framework 4.5 Core"; Required = $true},
    @{Name = "NET-WCF-HTTP-Activation45"; Description = "WCF HTTP Activation"; Required = $true},
    @{Name = "NET-WCF-TCP-PortSharing45"; Description = "WCF TCP Port Sharing"; Required = $false},

    # BITS
    @{Name = "BITS"; Description = "Background Intelligent Transfer Service"; Required = $true},
    @{Name = "BITS-IIS-Ext"; Description = "BITS IIS Server Extension"; Required = $true},

    # Remote Differential Compression
    @{Name = "RDC"; Description = "Remote Differential Compression"; Required = $true},

    # IIS Web Server
    @{Name = "Web-Server"; Description = "Web Server (IIS)"; Required = $true},
    @{Name = "Web-WebServer"; Description = "Web Server Core"; Required = $true},

    # IIS Common HTTP Features
    @{Name = "Web-Common-Http"; Description = "Common HTTP Features"; Required = $true},
    @{Name = "Web-Default-Doc"; Description = "Default Document"; Required = $true},
    @{Name = "Web-Dir-Browsing"; Description = "Directory Browsing"; Required = $true},
    @{Name = "Web-Http-Errors"; Description = "HTTP Errors"; Required = $true},
    @{Name = "Web-Static-Content"; Description = "Static Content"; Required = $true},
    @{Name = "Web-Http-Redirect"; Description = "HTTP Redirection"; Required = $false},

    # IIS Health and Diagnostics
    @{Name = "Web-Health"; Description = "Health and Diagnostics"; Required = $true},
    @{Name = "Web-Http-Logging"; Description = "HTTP Logging"; Required = $true},
    @{Name = "Web-Log-Libraries"; Description = "Logging Tools"; Required = $false},
    @{Name = "Web-Request-Monitor"; Description = "Request Monitor"; Required = $false},
    @{Name = "Web-Http-Tracing"; Description = "HTTP Tracing"; Required = $false},

    # IIS Performance
    @{Name = "Web-Performance"; Description = "Performance Features"; Required = $true},
    @{Name = "Web-Stat-Compression"; Description = "Static Content Compression"; Required = $true},
    @{Name = "Web-Dyn-Compression"; Description = "Dynamic Content Compression"; Required = $false},

    # IIS Security
    @{Name = "Web-Security"; Description = "Security Features"; Required = $true},
    @{Name = "Web-Filtering"; Description = "Request Filtering"; Required = $true},
    @{Name = "Web-Windows-Auth"; Description = "Windows Authentication"; Required = $true},

    # IIS Application Development
    @{Name = "Web-App-Dev"; Description = "Application Development"; Required = $true},
    @{Name = "Web-Net-Ext"; Description = ".NET Extensibility 3.5"; Required = $true},
    @{Name = "Web-Net-Ext45"; Description = ".NET Extensibility 4.5"; Required = $true},
    @{Name = "Web-Asp-Net"; Description = "ASP.NET 3.5"; Required = $true},
    @{Name = "Web-Asp-Net45"; Description = "ASP.NET 4.5"; Required = $true},
    @{Name = "Web-ISAPI-Ext"; Description = "ISAPI Extensions"; Required = $true},
    @{Name = "Web-ISAPI-Filter"; Description = "ISAPI Filters"; Required = $true},
    @{Name = "Web-WebSockets"; Description = "WebSocket Protocol"; Required = $true},

    # IIS Management Tools
    @{Name = "Web-Mgmt-Tools"; Description = "Management Tools"; Required = $true},
    @{Name = "Web-Mgmt-Console"; Description = "IIS Management Console"; Required = $true},
    @{Name = "Web-Mgmt-Compat"; Description = "IIS 6 Management Compatibility"; Required = $true},
    @{Name = "Web-Metabase"; Description = "IIS 6 Metabase Compatibility"; Required = $true},
    @{Name = "Web-WMI"; Description = "IIS 6 WMI Compatibility"; Required = $true},
    @{Name = "Web-Scripting-Tools"; Description = "IIS Management Scripts"; Required = $false},

    # Additional Windows Features
    @{Name = "RSAT-AD-Tools"; Description = "AD DS Tools"; Required = $false},
    @{Name = "UpdateServices-RSAT"; Description = "WSUS Tools"; Required = $false}
)

# Track installation results
$installedFeatures = @()
$failedFeatures = @()
$skippedFeatures = @()

Write-Log "Installing $(($windowsFeatures | Where-Object {$_.Required}).Count) required features and $( ($windowsFeatures | Where-Object {-not $_.Required}).Count) optional features..." -Level INFO

foreach ($feature in $windowsFeatures) {
    Write-Log "Processing: $($feature.Description) ($($feature.Name))..." -Level DEBUG

    # SYNTAX EXPLANATION: Get-WindowsFeature
    # Returns the installation state of a Windows feature
    # Possible states: Available, Installed, Removed
    $featureState = Get-WindowsFeature -Name $feature.Name -ErrorAction SilentlyContinue

    if (-not $featureState) {
        Write-Log "Feature not available on this OS: $($feature.Name)" -Level WARN
        $skippedFeatures += $feature.Name
        continue
    }

    if ($featureState.InstallState -eq "Installed") {
        Write-Log "Already installed: $($feature.Description)" -Level DEBUG
        $skippedFeatures += $feature.Name
        continue
    }

    # Install the feature
    Write-Log "Installing: $($feature.Description)..." -Level INFO

    try {
        # SYNTAX EXPLANATION: Install-WindowsFeature
        # -Name: Feature to install
        # -IncludeAllSubFeature: Install all child features
        # -ErrorAction Stop: Throw exception on failure
        # For .NET 3.5, we might need -Source pointing to Windows Server ISO

        $installParams = @{
            Name = $feature.Name
            ErrorAction = 'Stop'
        }

        # .NET 3.5 often needs the Windows installation source
        # This allows it to work without specifying source manually
        if ($feature.Name -eq "NET-Framework-Core") {
            $installParams['IncludeAllSubFeature'] = $true
        }

        $result = Install-WindowsFeature @installParams

        if ($result.Success) {
            Write-Log "Installed: $($feature.Description)" -Level SUCCESS
            $installedFeatures += $feature.Name

            if ($result.RestartNeeded -eq "Yes") {
                Write-Log "Feature requires restart: $($feature.Name)" -Level WARN
            }
        } else {
            Write-Log "Installation returned failure for: $($feature.Name)" -Level ERROR
            $failedFeatures += $feature.Name
        }
    }
    catch {
        if ($feature.Required) {
            Write-LogError "Failed to install required feature: $($feature.Name)"
            Write-Log "Error: $_" -Level ERROR
            $failedFeatures += $feature.Name
        } else {
            Write-Log "Optional feature not installed: $($feature.Name) - $_" -Level WARN
            $skippedFeatures += $feature.Name
        }
    }
}

# Summary of Windows Features
Write-Log "" -Level INFO
Write-Log "Windows Features Summary:" -Level INFO
Write-Log "  Installed: $($installedFeatures.Count)" -Level SUCCESS
Write-Log "  Skipped (already installed or N/A): $($skippedFeatures.Count)" -Level INFO
Write-Log "  Failed: $($failedFeatures.Count)" -Level $(if ($failedFeatures.Count -gt 0) {"ERROR"} else {"INFO"})

if ($failedFeatures.Count -gt 0) {
    Write-Log "Failed features: $($failedFeatures -join ', ')" -Level ERROR
}

# ============================================================================
# WINDOWS ADK INSTALLATION
# ============================================================================

if (-not $SkipADK) {
    Write-LogSection "Installing Windows ADK"

    # Check if ADK is already installed
    # ADK installs to a standard location and creates registry entries
    $adkPath = "C:\Program Files (x86)\Windows Kits\10\Assessment and Deployment Kit"
    $adkInstalled = Test-Path $adkPath

    if ($adkInstalled) {
        Write-Log "Windows ADK appears to be already installed at: $adkPath" -Level INFO

        # Check for specific required components
        $deploymentTools = Test-Path (Join-Path $adkPath "Deployment Tools")
        $userStateMT = Test-Path (Join-Path $adkPath "User State Migration Tool")

        Write-Log "  Deployment Tools: $(if ($deploymentTools) {'Present'} else {'Missing'})" -Level $(if ($deploymentTools) {"SUCCESS"} else {"WARN"})
        Write-Log "  User State Migration Tool: $(if ($userStateMT) {'Present'} else {'Missing'})" -Level $(if ($userStateMT) {"SUCCESS"} else {"WARN"})
    }

    # If ADK installer path provided, use it
    if ($ADKPath -and (Test-Path $ADKPath)) {
        Write-Log "Using ADK installer from: $ADKPath" -Level INFO

        # SYNTAX EXPLANATION: ADK Silent Installation
        # /quiet: No UI
        # /norestart: Don't auto-restart
        # /ceip off: Disable Customer Experience Improvement Program
        # /features: Which components to install
        #   OptionId.DeploymentTools: Deployment Tools (required for SCCM)
        #   OptionId.UserStateMigrationTool: USMT for user data migration
        #   OptionId.ImagingAndConfigurationDesigner: Windows ICD
        #   OptionId.ICDConfigurationDesigner: Configuration Designer

        Write-Log "Starting ADK installation (this may take 10-15 minutes)..." -Level INFO

        $adkArgs = @(
            "/quiet",
            "/norestart",
            "/ceip off",
            "/features OptionId.DeploymentTools OptionId.UserStateMigrationTool"
        )

        $process = Start-Process -FilePath $ADKPath -ArgumentList $adkArgs -Wait -NoNewWindow -PassThru

        if ($process.ExitCode -eq 0) {
            Write-Log "Windows ADK installed successfully." -Level SUCCESS
        } elseif ($process.ExitCode -eq 3010) {
            Write-Log "Windows ADK installed. Reboot required." -Level WARN
        } else {
            Write-Log "ADK installation completed with exit code: $($process.ExitCode)" -Level WARN
            Write-Log "Check %TEMP%\adk\*.log for details." -Level INFO
        }
    } elseif (-not $adkInstalled) {
        Write-Log "Windows ADK not installed and no installer provided." -Level WARN
        Write-Log "Download ADK from: https://learn.microsoft.com/en-us/windows-hardware/get-started/adk-install" -Level INFO
        Write-Log "Or provide path with -ADKPath parameter" -Level INFO
    }

    # Windows PE Add-on
    Write-LogSection "Installing Windows PE Add-on"

    $winPEPath = "C:\Program Files (x86)\Windows Kits\10\Assessment and Deployment Kit\Windows Preinstallation Environment"
    $winPEInstalled = Test-Path $winPEPath

    if ($winPEInstalled) {
        Write-Log "Windows PE Add-on appears to be installed." -Level INFO
    }

    if ($WinPEPath -and (Test-Path $WinPEPath)) {
        Write-Log "Using WinPE installer from: $WinPEPath" -Level INFO
        Write-Log "Starting WinPE Add-on installation..." -Level INFO

        $winPEArgs = @(
            "/quiet",
            "/norestart",
            "/ceip off",
            "/features OptionId.WindowsPreinstallationEnvironment"
        )

        $process = Start-Process -FilePath $WinPEPath -ArgumentList $winPEArgs -Wait -NoNewWindow -PassThru

        if ($process.ExitCode -eq 0) {
            Write-Log "Windows PE Add-on installed successfully." -Level SUCCESS
        } elseif ($process.ExitCode -eq 3010) {
            Write-Log "Windows PE Add-on installed. Reboot required." -Level WARN
        } else {
            Write-Log "WinPE installation completed with exit code: $($process.ExitCode)" -Level WARN
        }
    } elseif (-not $winPEInstalled) {
        Write-Log "Windows PE Add-on not installed and no installer provided." -Level WARN
        Write-Log "Download from: https://learn.microsoft.com/en-us/windows-hardware/get-started/adk-install" -Level INFO
    }
} else {
    Write-Log "Skipping ADK installation (SkipADK parameter specified)" -Level INFO
}

# ============================================================================
# ODBC DRIVER FOR SQL SERVER
# ============================================================================

Write-LogSection "Checking ODBC Driver for SQL Server"

# SCCM Current Branch requires ODBC Driver 18.4.1 or later
# Check if it's installed via registry
$odbcDriver = Get-ItemProperty -Path "HKLM:\SOFTWARE\ODBC\ODBCINST.INI\ODBC Driver 18 for SQL Server" -ErrorAction SilentlyContinue

if ($odbcDriver) {
    Write-Log "ODBC Driver 18 for SQL Server is installed." -Level SUCCESS
    Write-Log "Driver Path: $($odbcDriver.Driver)" -Level DEBUG
} else {
    # Check for ODBC Driver 17
    $odbcDriver17 = Get-ItemProperty -Path "HKLM:\SOFTWARE\ODBC\ODBCINST.INI\ODBC Driver 17 for SQL Server" -ErrorAction SilentlyContinue

    if ($odbcDriver17) {
        Write-Log "ODBC Driver 17 for SQL Server is installed (may need upgrade for newer SCCM)." -Level WARN
    } else {
        Write-Log "ODBC Driver for SQL Server not found." -Level WARN
        Write-Log "Download from: https://learn.microsoft.com/en-us/sql/connect/odbc/download-odbc-driver-for-sql-server" -Level INFO
        Write-Log "SCCM Current Branch requires ODBC Driver 18.4.1 or later." -Level INFO
    }
}

# ============================================================================
# VISUAL C++ REDISTRIBUTABLES
# ============================================================================

Write-LogSection "Checking Visual C++ Redistributables"

# SCCM requires various VC++ redistributables
# These are usually installed by SQL Server and other components
# But we check to make sure

# Check for VC++ 2015-2022 (most important for current SCCM)
$vcRedist = Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\VisualStudio\14.0\VC\Runtimes\x64" -ErrorAction SilentlyContinue

if ($vcRedist) {
    Write-Log "Visual C++ 2015-2022 Redistributable (x64) is installed." -Level SUCCESS
    Write-Log "Version: $($vcRedist.Version)" -Level DEBUG
} else {
    # Check WOW64 path for 32-bit
    $vcRedist32 = Get-ItemProperty "HKLM:\SOFTWARE\WOW6432Node\Microsoft\VisualStudio\14.0\VC\Runtimes\x64" -ErrorAction SilentlyContinue

    if ($vcRedist32) {
        Write-Log "Visual C++ 2015-2022 Redistributable (x64) is installed." -Level SUCCESS
    } else {
        Write-Log "Visual C++ 2015-2022 Redistributable may not be installed." -Level WARN
        Write-Log "This is usually installed by SQL Server. If SCCM setup fails, download from:" -Level INFO
        Write-Log "https://learn.microsoft.com/en-us/cpp/windows/latest-supported-vc-redist" -Level INFO
    }
}

# ============================================================================
# EXTEND ACTIVE DIRECTORY SCHEMA
# ============================================================================

Write-LogSection "Active Directory Schema Extension"

# SCCM requires the AD schema to be extended before installation
# This is done using extadsch.exe from the SCCM installation media
# We check if it's been done by looking for the System Management container

Write-Log "Checking if AD schema has been extended for SCCM..." -Level INFO

try {
    # SYNTAX EXPLANATION: AD Schema Check
    # The SCCM schema extension adds specific classes and attributes
    # We can check for the presence of SCCM-specific attributes
    # The System Management container is also required

    # Import AD module if available
    if (Get-Module -ListAvailable -Name ActiveDirectory) {
        Import-Module ActiveDirectory

        # Check for System Management container
        $domainDN = (Get-ADDomain).DistinguishedName
        $systemMgmtPath = "CN=System Management,CN=System,$domainDN"

        try {
            $systemMgmt = Get-ADObject -Identity $systemMgmtPath -ErrorAction Stop
            Write-Log "System Management container exists in AD." -Level SUCCESS

            # Check permissions on the container (SCCM server needs Full Control)
            Write-Log "NOTE: Verify SCCM01 computer account has Full Control on System Management container." -Level INFO
        }
        catch {
            Write-Log "System Management container does not exist." -Level WARN
            Write-Log "You need to:" -Level INFO
            Write-Log "  1. Run extadsch.exe from SCCM media on a Domain Controller" -Level INFO
            Write-Log "  2. Create 'System Management' container under CN=System" -Level INFO
            Write-Log "  3. Grant SCCM01 computer account Full Control on the container" -Level INFO
        }
    } else {
        Write-Log "Active Directory PowerShell module not available on this server." -Level INFO
        Write-Log "Schema extension check skipped. Ensure schema is extended before SCCM install." -Level WARN
    }
}
catch {
    Write-Log "Could not check AD schema status: $_" -Level WARN
}

# ============================================================================
# WSUS (WINDOWS SERVER UPDATE SERVICES) - OPTIONAL
# ============================================================================

Write-LogSection "WSUS Configuration Check (Optional)"

# SCCM can use WSUS for software updates management
# If you want to use SCCM for Windows Updates, you need WSUS

$wsusFeature = Get-WindowsFeature -Name UpdateServices -ErrorAction SilentlyContinue

if ($wsusFeature -and $wsusFeature.InstallState -eq "Installed") {
    Write-Log "WSUS is installed on this server." -Level SUCCESS
} else {
    Write-Log "WSUS is not installed." -Level INFO
    Write-Log "WSUS is required if you want to use SCCM for software updates." -Level INFO
    Write-Log "You can install WSUS later if needed, or as part of SCCM SUP role." -Level INFO
}

# ============================================================================
# SQL SERVER VERIFICATION
# ============================================================================

Write-LogSection "SQL Server Verification"

# Verify SQL Server is properly installed before SCCM installation
if (Test-SQLServerInstalled) {
    Write-Log "SQL Server is installed." -Level SUCCESS

    # Verify collation
    try {
        $collation = Invoke-Sqlcmd -Query "SELECT SERVERPROPERTY('Collation') AS Collation" -ServerInstance "." -ErrorAction Stop

        if ($collation.Collation -eq "SQL_Latin1_General_CP1_CI_AS") {
            Write-Log "SQL Server collation is correct: $($collation.Collation)" -Level SUCCESS
        } else {
            Write-LogError "CRITICAL: SQL Server collation is WRONG: $($collation.Collation)"
            Write-Log "SCCM installation WILL FAIL without correct collation!" -Level ERROR
            Write-Log "Required: SQL_Latin1_General_CP1_CI_AS" -Level ERROR
        }
    }
    catch {
        Write-Log "Could not verify SQL collation. Error: $_" -Level WARN
    }

    # Verify SQL Server services
    $sqlServices = @("MSSQLSERVER", "SQLSERVERAGENT", "ReportServer")
    foreach ($svc in $sqlServices) {
        $service = Get-Service -Name $svc -ErrorAction SilentlyContinue
        if ($service -and $service.Status -eq "Running") {
            Write-Log "Service $svc is running." -Level SUCCESS
        } else {
            Write-Log "Service $svc is not running or not installed." -Level WARN
        }
    }
} else {
    Write-LogError "SQL Server is NOT installed!"
    Write-Log "Install SQL Server before proceeding with SCCM installation." -Level ERROR
}

# ============================================================================
# NO_SMS_ON_DRIVE.SMS FILE
# ============================================================================

Write-LogSection "Drive Configuration for SCCM"

# SCCM allows you to exclude drives from content storage by placing
# a file named NO_SMS_ON_DRIVE.SMS in the root of the drive

# Get all fixed drives
$drives = Get-WmiObject -Class Win32_LogicalDisk -Filter "DriveType=3"

Write-Log "Fixed drives found:" -Level INFO
foreach ($drive in $drives) {
    $driveLetter = $drive.DeviceID
    $freeSpaceGB = [math]::Round($drive.FreeSpace / 1GB, 2)
    $totalSpaceGB = [math]::Round($drive.Size / 1GB, 2)
    $noSmsFile = Join-Path $driveLetter "NO_SMS_ON_DRIVE.SMS"
    $hasNoSms = Test-Path $noSmsFile

    Write-Log "  $driveLetter - $freeSpaceGB GB free of $totalSpaceGB GB $(if ($hasNoSms) {'[EXCLUDED from SCCM]'})" -Level INFO
}

Write-Log "" -Level INFO
Write-Log "To exclude a drive from SCCM content storage:" -Level INFO
Write-Log "  Create an empty file named NO_SMS_ON_DRIVE.SMS in the drive root" -Level INFO
Write-Log "  Example: New-Item -Path 'E:\NO_SMS_ON_DRIVE.SMS' -ItemType File" -Level INFO

# ============================================================================
# PREREQUISITES SUMMARY
# ============================================================================

Write-LogSection "SCCM Prerequisites Summary"

# Create a summary table
$prereqStatus = @(
    @{Component = "Windows Features (IIS, BITS, RDC, .NET)"; Status = $(if ($failedFeatures.Count -eq 0) {"Ready"} else {"Issues"})},
    @{Component = "SQL Server"; Status = $(if (Test-SQLServerInstalled) {"Installed"} else {"Missing"})},
    @{Component = "SQL Server Collation"; Status = "Verify Manually"},
    @{Component = "Windows ADK"; Status = $(if (Test-Path "C:\Program Files (x86)\Windows Kits\10\Assessment and Deployment Kit") {"Installed"} else {"Missing"})},
    @{Component = "Windows PE Add-on"; Status = $(if (Test-Path "C:\Program Files (x86)\Windows Kits\10\Assessment and Deployment Kit\Windows Preinstallation Environment") {"Installed"} else {"Missing"})},
    @{Component = "AD Schema Extension"; Status = "Verify Manually"},
    @{Component = "System Management Container"; Status = "Verify Manually"}
)

foreach ($item in $prereqStatus) {
    $level = switch ($item.Status) {
        "Ready" { "SUCCESS" }
        "Installed" { "SUCCESS" }
        "Missing" { "ERROR" }
        "Issues" { "WARN" }
        default { "INFO" }
    }
    Write-Log "  $($item.Component): $($item.Status)" -Level $level
}

Write-Log "" -Level INFO
Write-Log "Manual steps still required:" -Level INFO
Write-Log "  1. Download and install Windows ADK (if not done)" -Level INFO
Write-Log "  2. Download and install Windows PE Add-on (if not done)" -Level INFO
Write-Log "  3. Run extadsch.exe from SCCM media on DC01" -Level INFO
Write-Log "  4. Create System Management container in AD" -Level INFO
Write-Log "  5. Grant SCCM01$ Full Control on System Management container" -Level INFO
Write-Log "" -Level INFO
Write-Log "After completing prerequisites, run Install-SCCM.ps1" -Level INFO

# Check if reboot is needed
$pendingReboot = (Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing" -Name "RebootPending" -ErrorAction SilentlyContinue) -or
                 (Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update" -Name "RebootRequired" -ErrorAction SilentlyContinue)

if ($pendingReboot) {
    Write-Log "" -Level INFO
    Write-Log "A REBOOT IS REQUIRED before continuing with SCCM installation." -Level WARN
}

Complete-Logging
