#Requires -Version 5.1
#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Promotes a Windows Server to a Domain Controller, creating a new AD forest.

.DESCRIPTION
    This script promotes the server to be the first domain controller in a new
    Active Directory forest named "lab.local". This is the second step after
    installing the AD DS role (Install-ADDS.ps1).

    WHAT HAPPENS DURING PROMOTION:
    ------------------------------
    1. A new AD forest is created (lab.local)
    2. A new AD domain is created within that forest
    3. DNS Server role is installed and configured for AD
    4. This server becomes a Global Catalog server
    5. The SYSVOL and NTDS folders are created
    6. The server REBOOTS automatically

    IMPORTANT CONCEPTS:
    -------------------

    FOREST: The top-level container in Active Directory. A forest can contain
    multiple domains that share a common schema. In our lab, we have one forest
    with one domain.

    DOMAIN: A logical group of objects (users, computers, groups) that share a
    common directory database. Our domain is "lab.local".

    FUNCTIONAL LEVEL: Determines which AD features are available. Higher levels
    enable more features but require all DCs to run newer Windows versions.
    We use "WinThreshold" (Windows Server 2016) for broad compatibility.

    DSRM PASSWORD: Directory Services Restore Mode password. Used to access the
    DC in recovery mode if AD is broken. CRITICAL to remember this password!

    SYSVOL: System Volume - shared folder containing Group Policy templates and
    logon scripts. Replicated between all DCs.

    NTDS: NT Directory Services - the AD database files stored in
    C:\Windows\NTDS by default.

.PARAMETER DomainName
    The FQDN of the new domain. Defaults to "lab.local".

.PARAMETER NetBIOSName
    The NetBIOS (pre-Windows 2000) name of the domain. Defaults to "LAB".
    Limited to 15 characters.

.PARAMETER DSRMPassword
    The Directory Services Restore Mode password. If not provided, you'll be
    prompted for it (or a default is used in -Force mode).

.PARAMETER Force
    Skip confirmation prompts and use default DSRM password. For automated
    deployment only!

.EXAMPLE
    # Interactive promotion (will prompt for DSRM password)
    .\Promote-DC.ps1

.EXAMPLE
    # Automated promotion with custom DSRM password
    $securePassword = ConvertTo-SecureString "P@ssw0rd123!" -AsPlainText -Force
    .\Promote-DC.ps1 -DSRMPassword $securePassword -Force

.EXAMPLE
    # Custom domain name
    .\Promote-DC.ps1 -DomainName "mylab.local" -NetBIOSName "MYLAB"

.NOTES
    Author: SCCM Homelab Project
    Version: 1.0

    PREREQUISITES:
    - AD DS role must be installed (run Install-ADDS.ps1 first)
    - Administrator privileges
    - Static IP address configured
    - At least 2GB RAM recommended

    WARNING:
    - This script will AUTOMATICALLY REBOOT the server!
    - After reboot, login with: DOMAIN\Administrator (not local admin)
    - Example: LAB\Administrator with the vagrant password

    NEXT STEPS:
    After reboot, run Configure-DNS.ps1 to complete DNS configuration.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$DomainName = "lab.local",

    [Parameter(Mandatory = $false)]
    [ValidateLength(1, 15)]  # NetBIOS name max 15 chars
    [string]$NetBIOSName = "LAB",

    [Parameter(Mandatory = $false)]
    [SecureString]$DSRMPassword = $null,

    [Parameter(Mandatory = $false)]
    [switch]$Force
)

# =============================================================================
# SCRIPT INITIALIZATION
# =============================================================================

$ErrorActionPreference = 'Stop'

# Import modules
$ScriptDir = Split-Path -Parent $PSScriptRoot

try {
    Import-Module (Join-Path $ScriptDir "modules\Logger.psm1") -Force
    Import-Module (Join-Path $ScriptDir "modules\Validator.psm1") -Force
}
catch {
    Write-Host "[ERROR] Failed to import modules: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

Initialize-Logging -ScriptName "Promote-DC"

# =============================================================================
# CONFIGURATION
# =============================================================================

# Default DSRM password for automated deployment (LAB USE ONLY!)
# In production, NEVER hardcode passwords!
$DefaultDSRMPassword = "P@ssw0rd123!"

# Forest and Domain functional levels
# "WinThreshold" = Windows Server 2016 functional level
# This provides a good balance of features and compatibility
$ForestMode = "WinThreshold"
$DomainMode = "WinThreshold"

# =============================================================================
# MAIN SCRIPT LOGIC
# =============================================================================

try {
    Write-LogSection "Promoting Server to Domain Controller"

    # -------------------------------------------------------------------------
    # STEP 1: Prerequisite Checks
    # -------------------------------------------------------------------------
    Write-Log "Performing prerequisite checks..." -Level INFO

    # Check if AD DS role is installed
    if (-not (Test-ADDSInstalled)) {
        Write-Log "AD DS role is not installed!" -Level ERROR
        Write-Log "Please run Install-ADDS.ps1 first." -Level ERROR
        Complete-Logging -Success $false
        exit 1
    }
    Write-Log "  AD DS role is installed" -Level SUCCESS

    # Check if already a domain controller
    if (Test-IsDomainController) {
        Write-Log "This server is already a domain controller!" -Level WARN
        Write-Log "Skipping promotion." -Level INFO

        # Show domain info
        try {
            $domain = Get-ADDomain
            Write-Log "Current Domain: $($domain.DNSRoot)" -Level INFO
            Write-Log "Forest: $($domain.Forest)" -Level INFO
        }
        catch {
            Write-Log "Could not retrieve domain information." -Level WARN
        }

        Complete-Logging -Success $true
        exit 0
    }
    Write-Log "  Server is not yet a domain controller" -Level SUCCESS

    # -------------------------------------------------------------------------
    # STEP 2: Handle DSRM Password
    # -------------------------------------------------------------------------
    Write-Log "Configuring DSRM password..." -Level INFO

    <#
    DSRM PASSWORD EXPLAINED:
    ------------------------
    DSRM (Directory Services Restore Mode) is a special boot mode for domain
    controllers. It's used when:
    - AD is corrupted and needs to be restored from backup
    - You need to perform offline defragmentation of the AD database
    - AD services won't start and you need to troubleshoot

    The DSRM password is the local Administrator password when booting into
    DSRM. It's set during DC promotion and can be changed later with:
    ntdsutil "set dsrm password"

    SECURITY WARNING: We use a default password for lab convenience.
    In production, ALWAYS use a unique, strong password and store it securely!
    #>

    if ($null -eq $DSRMPassword) {
        if ($Force) {
            # Use default password for automated deployment
            Write-Log "Using default DSRM password (automated mode)" -Level WARN
            Write-Log "WARNING: Default password is for LAB USE ONLY!" -Level WARN
            $DSRMPassword = ConvertTo-SecureString $DefaultDSRMPassword -AsPlainText -Force
        }
        else {
            # Prompt for password interactively
            Write-Log "Please enter the DSRM (Directory Services Restore Mode) password." -Level INFO
            Write-Log "This password is used for recovery if AD becomes corrupted." -Level INFO
            $DSRMPassword = Read-Host "Enter DSRM password" -AsSecureString
        }
    }

    # -------------------------------------------------------------------------
    # STEP 3: Display Configuration
    # -------------------------------------------------------------------------
    Write-Log "" -Level INFO
    Write-LogSection "Configuration Summary"
    Write-Log "Domain Name (FQDN):  $DomainName" -Level INFO
    Write-Log "NetBIOS Name:        $NetBIOSName" -Level INFO
    Write-Log "Forest Mode:         $ForestMode (Windows Server 2016)" -Level INFO
    Write-Log "Domain Mode:         $DomainMode (Windows Server 2016)" -Level INFO
    Write-Log "Install DNS:         Yes (required for AD)" -Level INFO
    Write-Log "Global Catalog:      Yes (first DC is always GC)" -Level INFO
    Write-Log "" -Level INFO

    # -------------------------------------------------------------------------
    # STEP 4: Confirmation
    # -------------------------------------------------------------------------
    if (-not $Force) {
        Write-Log "WARNING: This operation will:" -Level WARN
        Write-Log "  - Create a new Active Directory forest" -Level WARN
        Write-Log "  - AUTOMATICALLY REBOOT this server" -Level WARN
        Write-Log "  - Change the Administrator password context to domain" -Level WARN
        Write-Log "" -Level INFO
        Write-Log "After reboot, login with: $NetBIOSName\Administrator" -Level INFO
        Write-Log "" -Level INFO

        $confirm = Read-Host "Do you want to continue? (Y/N)"
        if ($confirm -notmatch "^[Yy]") {
            Write-Log "Promotion cancelled by user." -Level WARN
            Complete-Logging -Success $false
            exit 0
        }
    }

    # -------------------------------------------------------------------------
    # STEP 5: Import ADDSDeployment Module
    # -------------------------------------------------------------------------
    Write-Log "Loading AD DS Deployment module..." -Level INFO

    <#
    ADDSDEPLOYMENT MODULE:
    ----------------------
    This module is installed with the AD DS role and contains cmdlets for:
    - Install-ADDSForest: Create a new forest (what we're doing)
    - Install-ADDSDomain: Add a domain to an existing forest
    - Install-ADDSDomainController: Add a DC to an existing domain
    - Test-ADDSForestInstallation: Test if forest installation will succeed
    - Uninstall-ADDSDomainController: Demote a domain controller
    #>

    Import-Module ADDSDeployment -ErrorAction Stop
    Write-Log "  ADDSDeployment module loaded" -Level SUCCESS

    # -------------------------------------------------------------------------
    # STEP 6: Run Pre-Installation Test (Optional but Recommended)
    # -------------------------------------------------------------------------
    Write-Log "Running pre-installation tests..." -Level INFO

    <#
    TEST-ADDSFORESTINSTALLATION:
    ----------------------------
    This cmdlet performs a "dry run" of the forest installation, checking:
    - DNS configuration requirements
    - Network adapter settings
    - Credential validity
    - Potential conflicts

    It's like running Install-ADDSForest but without actually doing it.
    Any errors here would also occur during actual installation.
    #>

    # Build parameter hashtable for splatting
    # Splatting (@params) passes a hashtable as cmdlet parameters
    # This is cleaner than very long command lines
    $testParams = @{
        DomainName                    = $DomainName
        DomainNetBIOSName             = $NetBIOSName
        ForestMode                    = $ForestMode
        DomainMode                    = $DomainMode
        InstallDNS                    = $true
        SafeModeAdministratorPassword = $DSRMPassword
        Force                         = $true
    }

    # Run the test
    $testResult = Test-ADDSForestInstallation @testParams

    # Check test results
    if ($testResult.Status -eq "Error") {
        Write-Log "Pre-installation test FAILED!" -Level ERROR
        foreach ($message in $testResult.Message) {
            Write-Log "  $message" -Level ERROR
        }
        Complete-Logging -Success $false
        exit 1
    }
    elseif ($testResult.Status -eq "Warning") {
        Write-Log "Pre-installation test completed with warnings:" -Level WARN
        foreach ($message in $testResult.Message) {
            Write-Log "  $message" -Level WARN
        }
        Write-Log "Proceeding anyway (warnings are typically non-fatal)..." -Level INFO
    }
    else {
        Write-Log "  Pre-installation test passed" -Level SUCCESS
    }

    # -------------------------------------------------------------------------
    # STEP 7: Install AD DS Forest (THE MAIN EVENT!)
    # -------------------------------------------------------------------------
    Write-LogSection "Installing Active Directory Forest"
    Write-Log "Creating new forest: $DomainName" -Level INFO
    Write-Log "This process takes 5-15 minutes and will REBOOT automatically!" -Level WARN
    Write-Log "" -Level INFO

    <#
    INSTALL-ADDSFOREST PARAMETERS EXPLAINED:
    ----------------------------------------

    -DomainName: The FQDN of the new domain. This becomes the DNS name.
        Example: "lab.local" means computers are "dc01.lab.local"

    -DomainNetBIOSName: Short name (max 15 chars) for pre-2000 compatibility.
        Example: "LAB" allows login as "LAB\username"

    -ForestMode/-DomainMode: Functional level determines available features.
        Higher = more features, but ALL DCs must support that level.
        "WinThreshold" = Windows Server 2016 level.

    -InstallDNS: Install and configure DNS Server role.
        DNS is REQUIRED for AD to function. AD uses DNS to locate:
        - Domain controllers (_ldap._tcp.lab.local SRV records)
        - Kerberos servers (_kerberos._tcp.lab.local SRV records)
        - Global Catalog servers (_gc._tcp.lab.local SRV records)

    -SafeModeAdministratorPassword: DSRM recovery password.
        Store this securely! Needed if AD needs repair.

    -DatabasePath: Where to store the AD database (ntds.dit).
        Default: C:\Windows\NTDS

    -SysvolPath: Where to store SYSVOL (Group Policy, scripts).
        Default: C:\Windows\SYSVOL

    -LogPath: Where to store AD transaction logs.
        Default: C:\Windows\NTDS

    -NoRebootOnCompletion: If $false, server reboots automatically.
        We want this so the DC is fully functional.

    -Force: Skip confirmation prompts.
    #>

    $installParams = @{
        DomainName                    = $DomainName
        DomainNetBIOSName             = $NetBIOSName
        ForestMode                    = $ForestMode
        DomainMode                    = $DomainMode
        InstallDNS                    = $true
        SafeModeAdministratorPassword = $DSRMPassword
        DatabasePath                  = "C:\Windows\NTDS"
        SysvolPath                    = "C:\Windows\SYSVOL"
        LogPath                       = "C:\Windows\NTDS"
        NoRebootOnCompletion          = $false  # Auto-reboot!
        Force                         = $true
    }

    Write-Log "Starting forest installation..." -Level INFO
    Write-Log "(The server will reboot automatically when complete)" -Level INFO
    Write-Log "" -Level INFO

    # This is the big moment - create the forest!
    # The -WarningAction SilentlyContinue suppresses non-critical warnings
    Install-ADDSForest @installParams -WarningAction SilentlyContinue

    # If we get here, something went wrong (should have rebooted)
    Write-Log "Installation command completed but server did not reboot." -Level WARN
    Write-Log "Please reboot manually to complete the installation." -Level WARN

    Complete-Logging -Success $true
    exit 0
}
catch {
    Write-LogError -ErrorRecord $_ -Message "An error occurred during DC promotion"

    # Provide specific guidance for common errors
    $errorMessage = $_.Exception.Message.ToLower()

    if ($errorMessage -match "network adapter") {
        Write-Log "" -Level INFO
        Write-Log "HINT: Make sure the network adapter has a static IP address." -Level INFO
        Write-Log "DC promotion requires a static IP for reliable DNS." -Level INFO
    }
    elseif ($errorMessage -match "dns") {
        Write-Log "" -Level INFO
        Write-Log "HINT: DNS issues are common during DC promotion." -Level INFO
        Write-Log "Ensure this server can reach the internet for DNS." -Level INFO
    }
    elseif ($errorMessage -match "password") {
        Write-Log "" -Level INFO
        Write-Log "HINT: The DSRM password may not meet complexity requirements." -Level INFO
        Write-Log "Use at least 8 characters with mixed case, numbers, symbols." -Level INFO
    }

    Complete-Logging -Success $false
    exit 1
}
